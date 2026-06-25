# Abhash Jellyfin — Complete Setup Guide

This is the single end-to-end guide for the Abhash fork of Jellyfin. It covers:

1. What this repo is and how it is structured
2. The two Docker images that are produced
3. Building and running locally with Docker / Docker Compose
4. Deploying on **Dokploy**
5. Connecting media storage from **multiple VMs over Samba/CIFS**
6. How **upstream sync** keeps this fork up to date

---

## 1. What this repo is

This repository merges **two upstream projects into one repo** so they version,
build, and deploy together:

| Path           | Origin                              | Purpose                          |
|----------------|-------------------------------------|----------------------------------|
| repo root      | `jellyfin/jellyfin` (backend)       | .NET media server + API          |
| `jellyfin-web/`| `jellyfin/jellyfin-web` (frontend)  | React/webpack web client         |

`jellyfin-web/` is a vendored copy (plain files, kept in sync from upstream by
the sync workflow — see section 6). The default branch for this fork is
`Abhash-Main`.

---

## 2. The two Docker images

A single multi-stage `Dockerfile` produces **two images** from the same source:

| Image (GHCR)                                          | Dockerfile target | Contents                                   | Use when                                            |
|-------------------------------------------------------|-------------------|--------------------------------------------|-----------------------------------------------------|
| `ghcr.io/abhash-chakraborty/jellyfin-abhash`          | `runtime` (default) | server + ffmpeg + **bundled jellyfin-web** | Normal deployment — open the web UI in a browser     |
| `ghcr.io/abhash-chakraborty/jellyfin-abhash-server`   | `server-runtime`    | server + ffmpeg, **no web client**         | Backend-only (native apps, or web hosted separately) |

Both:
- Listen on port **8096** (`ASPNETCORE_URLS=http://+:8096`).
- Run as non-root **uid:gid 1000:1000**.
- Expose volumes `/config`, `/cache`, `/media`.
- Ship a Docker **HEALTHCHECK** hitting `/health`.

Tags published by CI: `:latest`, `:abhash-main`, `:<git-sha>`.

> **Verified:** both images build successfully, and the all-in-one image was
> runtime-tested — `/health` returns `Healthy`, `/web/` serves the client, and
> `/System/Info/Public` reports `Jellyfin Server` v12.0.0.

---

## 3. Build and run locally

### Prerequisites
- Docker (Docker Desktop on Windows/Mac, or Docker Engine on Linux).

### Build both images

```bash
# All-in-one (server + web)
docker build -t jellyfin-abhash:test --target runtime .

# Server-only
docker build -t jellyfin-abhash-server:test --target server-runtime .
```

### Run the all-in-one image directly

```bash
docker run -d --name jellyfin \
  --init \
  -p 8096:8096 \
  -v jellyfin_config:/config \
  -v jellyfin_cache:/cache \
  -v /path/to/media:/media:ro \
  jellyfin-abhash:test
```

Open <http://localhost:8096> and complete the setup wizard.

### Run with Docker Compose (recommended)

A ready-to-use `docker-compose.yml` is in the repo root. It can either build
locally or pull the GHCR image (edit the `image:`/`build:` keys):

```bash
docker compose up -d
docker compose logs -f jellyfin
```

Key points in the compose file:
- Runs as `1000:1000` (must match your media file ownership / CIFS `uid`).
- Named volumes `jellyfin_config` and `jellyfin_cache` persist data.
- Media is mounted **read-only**; add one bind mount per media source.
- A healthcheck polls `/health` so orchestrators know when it is ready.

---

## 4. Deploy on Dokploy

Dokploy runs on an Ubuntu (AMD64) host and deploys Docker Compose apps.

### 4.1 GitHub / GHCR setup

The CI workflow `publish-ghcr.yml` builds and pushes both images to GHCR on
every push to `Abhash-Main`. To enable it:

1. GitHub repo → **Settings → Actions → General**.
2. Set **Workflow permissions** to **Read and write**.
3. Enable **Allow GitHub Actions to create and approve pull requests**
   (needed by the sync workflow).
4. (Optional) Add secret **`ABHASH_BOT_TOKEN`** (a PAT) so the sync workflow
   acts as your user. Needed scopes: Contents RW, Pull requests RW, Actions RW.

If the GHCR package is **private**, create a PAT with `read:packages` and add it
to Dokploy as registry credentials so it can pull the image.

### 4.2 Create the Dokploy app

In Dokploy, create a **Compose** application and paste:

```yaml
services:
  jellyfin-abhash:
    image: ghcr.io/abhash-chakraborty/jellyfin-abhash:latest
    container_name: jellyfin-abhash
    restart: unless-stopped
    init: true
    user: "1000:1000"
    ports:
      - "8096:8096"
    environment:
      TZ: Asia/Kolkata
      JELLYFIN_PublishedServerUrl: "https://jellyfin.your-domain.com"
    volumes:
      - jellyfin_config:/config
      - jellyfin_cache:/cache
      - /srv/media:/media:ro          # media on the Dokploy host
      - /mnt/media-vm-1:/media-vm-1:ro # Samba mount from VM 1 (section 5)
      - /mnt/media-vm-2:/media-vm-2:ro # Samba mount from VM 2 (section 5)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8096/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

volumes:
  jellyfin_config:
  jellyfin_cache:
```

Change before deploying:
- `https://jellyfin.your-domain.com` → your real public URL.
- `/srv/media` → media stored on the Dokploy host (omit if none).
- `/mnt/media-vm-1`, `/mnt/media-vm-2` → your Samba mount points (section 5).

### 4.3 Domain / HTTPS

Add a domain in Dokploy pointing at the app, container port **8096**. Dokploy's
Traefik handles TLS. Set `JELLYFIN_PublishedServerUrl` to that HTTPS URL.

### 4.4 Permissions

The container runs as uid `1000`. Make every mounted media folder readable by
uid `1000` (for Samba use the `uid=1000` mount option in section 5; for local
folders `chown -R 1000:1000` or ensure world-readable).

---

## 5. Connect media from multiple VMs over Samba

Do all of this **on the Dokploy host** (not inside the container). Each remote
VM that holds media must already share a folder via Samba/SMB. We mount each
remote share onto the host, then bind-mount it into Jellyfin.

```
 VM1 (SMB share) ─┐
                  ├─► mounted on Dokploy host (/mnt/media-vm-N) ─► bind into container (/media-vm-N, ro)
 VM2 (SMB share) ─┘
```

### 5.1 Install the CIFS client

```bash
sudo apt update
sudo apt install -y cifs-utils
```

### 5.2 Create mount points

```bash
sudo mkdir -p /mnt/media-vm-1 /mnt/media-vm-2
```

### 5.3 Store credentials securely (one file per VM)

```bash
sudo mkdir -p /etc/samba/credentials
sudo nano /etc/samba/credentials/media-vm-1
```

Contents:

```ini
username=YOUR_SAMBA_USERNAME
password=YOUR_SAMBA_PASSWORD
domain=WORKGROUP
```

Lock it down:

```bash
sudo chmod 600 /etc/samba/credentials/media-vm-1
```

Repeat for `media-vm-2` if the second VM uses different credentials.

### 5.4 Test-mount one share

```bash
sudo mount -t cifs //VM1_IP_OR_HOST/SHARE_NAME /mnt/media-vm-1 \
  -o credentials=/etc/samba/credentials/media-vm-1,uid=1000,gid=1000,iocharset=utf8,vers=3.0,ro
ls /mnt/media-vm-1   # should list the remote media
```

`uid=1000,gid=1000` makes files appear owned by the Jellyfin container user.
`ro` mounts read-only (Jellyfin only needs to read media).

### 5.5 Make mounts persistent (survive reboot)

Edit `/etc/fstab` and add one line per share:

```fstab
//VM1_IP_OR_HOST/SHARE_NAME /mnt/media-vm-1 cifs credentials=/etc/samba/credentials/media-vm-1,uid=1000,gid=1000,iocharset=utf8,vers=3.0,ro,nofail,x-systemd.automount,_netdev 0 0
//VM2_IP_OR_HOST/SHARE_NAME /mnt/media-vm-2 cifs credentials=/etc/samba/credentials/media-vm-2,uid=1000,gid=1000,iocharset=utf8,vers=3.0,ro,nofail,x-systemd.automount,_netdev 0 0
```

- `nofail` — host still boots if a VM is offline.
- `x-systemd.automount` — mounts on first access (handles VMs that boot later).
- `_netdev` — wait for the network before mounting.

Apply:

```bash
sudo systemctl daemon-reload
sudo mount -a
```

### 5.6 Expose to Jellyfin

The compose file already bind-mounts `/mnt/media-vm-1` → `/media-vm-1` (ro). In
the Jellyfin UI: **Dashboard → Libraries → Add Media Library**, and add the
in-container paths:

```
/media          # local host media
/media-vm-1     # VM 1
/media-vm-2     # VM 2
```

Add more VMs by repeating: new credentials file → new `/mnt/media-vm-N` →
new fstab line → new `:/media-vm-N:ro` volume → add the path in Jellyfin.

> **Tip:** SMB **3.0+** is recommended. If a NAS/VM only supports older SMB,
> change `vers=` accordingly (e.g. `vers=2.1`), but avoid SMB 1.

---

## 6. Upstream sync

Two GitHub Actions workflows keep this fork current and publish images.

### `publish-ghcr.yml` — build & publish
On every push to `Abhash-Main` (and manual dispatch) it runs server + web
tests, then builds and pushes **both** images to GHCR.

### `sync-upstream.yml` — pull in upstream changes
Daily (and manual dispatch) it:
1. Creates a `sync/upstream-master` branch from `Abhash-Main`.
2. **Merges** `jellyfin/jellyfin:master` (the backend) into it.
3. **Mirrors** `jellyfin/jellyfin-web:master` into `jellyfin-web/` using
   `git archive` (a deterministic content overwrite — chosen because
   `jellyfin-web/` is a plain vendored copy, *not* a `git subtree`, so
   `git subtree pull` would fail on unrelated histories).
4. Runs the full test suite (server + web) on the merged result.
5. Opens a PR into `Abhash-Main`, merges it, and triggers `publish-ghcr.yml`.

If the backend merge hits conflicts, the workflow stops so you can resolve them
once locally. Enable conflict-resolution reuse in your clone:

```bash
git config rerere.enabled true
git config rerere.autoupdate true
```

`rerere` records your resolution so the same upstream conflict resolves
automatically next time.

---

## Quick mental model

GitHub builds the images → GHCR stores them → Dokploy pulls and runs the
all-in-one image → Samba mounts remote VM media onto the Dokploy host → Docker
passes those folders into Jellyfin as read-only libraries. The sync workflow
keeps both the server and the bundled web client current with upstream.
