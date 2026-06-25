# Abhash-Main Operations

`Abhash-Main` is the personal default branch for Abhash Chakraborty's
Jellyfin fork. It keeps the upstream GPL-2.0 license intact and adds
`MODIFICATION_NOTICE.md` to identify this branch as the Abhash version.

## CI kept on this branch

- `Publish GHCR Image` tests the repository, builds a linux/amd64 Docker
  image, and pushes it to GHCR whenever `Abhash-Main` changes.
- `Sync Upstream` fetches `jellyfin/jellyfin:master`, merges it into a sync
  branch, syncs `jellyfin-web/` from `jellyfin/jellyfin-web:master`, tests the
  merged result, opens a pull request into `Abhash-Main`, merges that PR after
  the tests pass, and dispatches the publish workflow.

## Local rerere setup

Run this once in every clone where you resolve upstream conflicts:

```bash
git config rerere.enabled true
git config rerere.autoupdate true
```

`rerere` remembers how you resolved a conflict. If the same conflict appears
again during future upstream syncs, Git can reuse your previous resolution.

## GHCR images

The publish workflow writes these linux/amd64 images:

```text
ghcr.io/abhash-chakraborty/jellyfin-abhash:latest
ghcr.io/abhash-chakraborty/jellyfin-abhash-server:latest
```

Use `jellyfin-abhash:latest` for normal Dokploy deployments. It includes the
backend server, ffmpeg, and the bundled `jellyfin-web` build.

Use `jellyfin-abhash-server:latest` only when you want a smaller backend-only
image and will connect with apps or host the web client separately.
