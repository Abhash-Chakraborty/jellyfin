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

FROM node:24-bookworm-slim AS web-build
WORKDIR /src/jellyfin-web

COPY jellyfin-web/package.json jellyfin-web/package-lock.json ./
RUN npm ci
COPY jellyfin-web/ ./
RUN npm run build:production

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

RUN mkdir -p /jellyfin /config /cache /media \
    && chown -R 1000:1000 /jellyfin /config /cache /media /app

USER 1000:1000
EXPOSE 8096
VOLUME ["/config", "/cache", "/media"]

# Both image targets expose Jellyfin's /health endpoint on port 8096.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -fsS http://localhost:8096/health || exit 1

FROM base-runtime AS server-runtime
ENTRYPOINT ["dotnet", "/app/jellyfin.dll", "--service", "--nowebclient", "--ffmpeg", "/usr/bin/ffmpeg"]

FROM base-runtime AS runtime
COPY --from=web-build /src/jellyfin-web/dist/ /app/jellyfin-web/
ENTRYPOINT ["dotnet", "/app/jellyfin.dll", "--service", "--webdir", "/app/jellyfin-web", "--ffmpeg", "/usr/bin/ffmpeg"]
