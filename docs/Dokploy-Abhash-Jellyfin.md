# Dokploy Setup for Abhash Jellyfin

This guide deploys the all-in-one Abhash Jellyfin image on an Ubuntu AMD64
server. The image includes the Jellyfin server, ffmpeg, and the bundled
`jellyfin-web` build.

## Image Names

Use this for Dokploy:

```text
ghcr.io/abhash-chakraborty/jellyfin-abhash:latest
```

There is also a backend-only image:

```text
ghcr.io/abhash-chakraborty/jellyfin-abhash-server:latest
```

## GitHub Setup

1. Open your GitHub repository.
2. Go to `Settings` -> `Actions` -> `General`.
3. Set workflow permissions to `Read and write permissions`.
4. Enable `Allow GitHub Actions to create and approve pull requests`.
5. Go to `Settings` -> `Secrets and variables` -> `Actions`.
6. Add `ABHASH_BOT_TOKEN` if you want the sync workflow to behave like your
   own bot user instead of the default GitHub Actions bot.

The token only needs repository access for:

```text
Contents: Read and write
Pull requests: Read and write
Actions: Read and write
```

If the GHCR package is private, create a GitHub personal access token with
`read:packages` and add it to Dokploy as registry credentials.

## Dokploy Compose

Paste this into Dokploy as a Docker Compose app:

```yaml
services:
  jellyfin-abhash:
    image: ghcr.io/abhash-chakraborty/jellyfin-abhash:latest
    container_name: jellyfin-abhash
    restart: unless-stopped
    ports:
      - "8096:8096"
    environment:
      TZ: Asia/Kolkata
      JELLYFIN_PublishedServerUrl: "https://jellyfin.your-domain.com"
    volumes:
      - jellyfin_config:/config
      - jellyfin_cache:/cache
      - /srv/media:/media:ro
      - /mnt/media-vm-1:/media-vm-1:ro
      - /mnt/media-vm-2:/media-vm-2:ro

volumes:
  jellyfin_config:
  jellyfin_cache:
```

Change these before deploying:

```text
https://jellyfin.your-domain.com -> your real domain
/srv/media -> media stored on the Dokploy server
/mnt/media-vm-1 -> first Samba-mounted remote VM
/mnt/media-vm-2 -> second Samba-mounted remote VM
```

## Environment Variables

Required:

```text
TZ=Asia/Kolkata
JELLYFIN_PublishedServerUrl=https://jellyfin.your-domain.com
```

The current image runs as Linux user id `1000`. Make mounted folders readable
by uid `1000`, or adjust ownership/permissions on the host.

## Samba Storage From Other VMs

Do this on the Dokploy Ubuntu server, not inside the container.

1. Install Samba client tools:

```bash
sudo apt update
sudo apt install -y cifs-utils
```

2. Create mount folders:

```bash
sudo mkdir -p /mnt/media-vm-1 /mnt/media-vm-2
```

3. Create a credentials file:

```bash
sudo mkdir -p /etc/samba/credentials
sudo nano /etc/samba/credentials/media-vm-1
```

Put this inside:

```text
username=YOUR_SAMBA_USERNAME
password=YOUR_SAMBA_PASSWORD
domain=WORKGROUP
```

Lock the file:

```bash
sudo chmod 600 /etc/samba/credentials/media-vm-1
```

Repeat for `/etc/samba/credentials/media-vm-2` if the second VM has different
login details.

4. Test one mount:

```bash
sudo mount -t cifs //VM1_IP_OR_HOSTNAME/SHARE_NAME /mnt/media-vm-1 \
  -o credentials=/etc/samba/credentials/media-vm-1,uid=1000,gid=1000,iocharset=utf8,vers=3.0,ro
```

If it works, check files:

```bash
ls /mnt/media-vm-1
```

5. Make mounts survive reboot:

```bash
sudo nano /etc/fstab
```

Add one line per remote share:

```text
//VM1_IP_OR_HOSTNAME/SHARE_NAME /mnt/media-vm-1 cifs credentials=/etc/samba/credentials/media-vm-1,uid=1000,gid=1000,iocharset=utf8,vers=3.0,ro,nofail,x-systemd.automount,_netdev 0 0
//VM2_IP_OR_HOSTNAME/SHARE_NAME /mnt/media-vm-2 cifs credentials=/etc/samba/credentials/media-vm-2,uid=1000,gid=1000,iocharset=utf8,vers=3.0,ro,nofail,x-systemd.automount,_netdev 0 0
```

6. Reload and mount:

```bash
sudo systemctl daemon-reload
sudo mount -a
```

7. Add the mounted folders to Jellyfin:

```text
/media
/media-vm-1
/media-vm-2
```

## Simple Mental Model

GitHub builds the image. GHCR stores the image. Dokploy pulls the image. Samba
mounts remote VM media folders onto the Dokploy host. Docker passes those host
folders into Jellyfin as read-only media libraries.
