# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS build
WORKDIR /src

COPY . .
RUN dotnet restore Jellyfin.Server/Jellyfin.Server.csproj
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

RUN useradd --system --uid 1000 --create-home --home-dir /jellyfin jellyfin \
    && mkdir -p /config /cache /media \
    && chown -R jellyfin:jellyfin /config /cache /media /app

USER jellyfin
EXPOSE 8096
VOLUME ["/config", "/cache", "/media"]

FROM base-runtime AS server-runtime
ENTRYPOINT ["dotnet", "/app/jellyfin.dll", "--service", "--nowebclient", "--ffmpeg", "/usr/bin/ffmpeg"]

FROM base-runtime AS runtime
COPY --from=web-build /src/jellyfin-web/dist/ /app/jellyfin-web/
ENTRYPOINT ["dotnet", "/app/jellyfin.dll", "--service", "--webdir", "/app/jellyfin-web", "--ffmpeg", "/usr/bin/ffmpeg"]
