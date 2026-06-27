# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS build
WORKDIR /src

COPY . .
# Retry restore to survive transient NuGet/network failures (observed in CI
# and container builds, e.g. SkiaSharp native asset download flakes).
RUN dotnet restore Jellyfin.Server/Jellyfin.Server.csproj \
    || (sleep 15 && dotnet restore Jellyfin.Server/Jellyfin.Server.csproj) \
    || (sleep 30 && dotnet restore Jellyfin.Server/Jellyfin.Server.csproj)
RUN dotnet publish Jellyfin.Server/Jellyfin.Server.csproj \
    --configuration Release \
    --output /app/publish \
    --no-restore \
    -p:UseAppHost=false

# Build the bundled Abhash Themes plugin against THIS server tree so it is
# guaranteed ABI-compatible with the server (version 12.0.0). We stage only the
# plugin's own assembly plus its meta.json: the shared MediaBrowser.* assemblies
# are resolved from the host at load time (see PluginLoadContext), and shipping
# duplicates would break type identity.
ARG ABHASH_THEMES_VERSION=1.0.0.0
RUN dotnet publish plugins/Jellyfin.Plugin.AbhashThemes/Jellyfin.Plugin.AbhashThemes.csproj \
        --configuration Release \
        --output /app/plugin-build \
        -p:UseAppHost=false \
    && mkdir -p "/app/bundled-plugins/AbhashThemes_${ABHASH_THEMES_VERSION}" \
    && cp /app/plugin-build/Jellyfin.Plugin.AbhashThemes.dll \
          "/app/bundled-plugins/AbhashThemes_${ABHASH_THEMES_VERSION}/" \
    && cp plugins/Jellyfin.Plugin.AbhashThemes/meta.json \
          "/app/bundled-plugins/AbhashThemes_${ABHASH_THEMES_VERSION}/"

FROM node:24-bookworm-slim AS web-build
WORKDIR /src/jellyfin-web

COPY jellyfin-web/package.json jellyfin-web/package-lock.json ./
RUN npm ci
COPY jellyfin-web/ ./
RUN npm run build:production

# Apply the Jellyfin Web null ApiClient hotfix to the freshly built bundles.
# python3 is only needed here in the throwaway web-build stage; it never lands
# in the final runtime image.
COPY scripts/patch-jellyfin-web.sh /usr/local/bin/patch-jellyfin-web.sh
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/* \
    && JELLYFIN_WEB_ROOT=/src/jellyfin-web/dist sh /usr/local/bin/patch-jellyfin-web.sh

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble AS base-runtime

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        fonts-dejavu-core \
        libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

ENV ASPNETCORE_URLS=http://+:8096 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    JELLYFIN_DATA_DIR=/config \
    JELLYFIN_CONFIG_DIR=/config/config \
    JELLYFIN_CACHE_DIR=/cache \
    JELLYFIN_LOG_DIR=/config/log

WORKDIR /app
COPY --from=build /app/publish/ ./

# Stage the bundled plugin(s); the entrypoint seeds them into /config/plugins on
# start (see scripts/docker-entrypoint.sh).
COPY --from=build /app/bundled-plugins/ /app/bundled-plugins/
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && mkdir -p /jellyfin /config /cache /media \
    && chown -R 1000:1000 /jellyfin /config /cache /media /app

USER 1000:1000
EXPOSE 8096
VOLUME ["/config", "/cache", "/media"]

# Both image targets expose Jellyfin's /health endpoint on port 8096.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -fsS http://localhost:8096/health || exit 1

FROM base-runtime AS server-runtime
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh", "dotnet", "/app/jellyfin.dll", "--service", "--nowebclient", "--ffmpeg", "/usr/bin/ffmpeg"]

FROM base-runtime AS runtime
COPY --from=web-build /src/jellyfin-web/dist/ /app/jellyfin-web/
# Fail the build if the Jellyfin Web null ApiClient hotfix is not present in the
# final web root (it is applied during the web-build stage above).
RUN grep -q "getApiClient called with null in main bundle" /app/jellyfin-web/main.jellyfin.bundle.js \
    && grep -q "main.jellyfin.bundle.js?patched-main-v2" /app/jellyfin-web/index.html
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh", "dotnet", "/app/jellyfin.dll", "--service", "--webdir", "/app/jellyfin-web", "--ffmpeg", "/usr/bin/ffmpeg"]
