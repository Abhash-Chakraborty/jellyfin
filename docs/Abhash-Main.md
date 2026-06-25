# Abhash-Main Operations

`Abhash-Main` is the personal default branch for Abhash Chakraborty's
Jellyfin fork. It keeps the upstream GPL-2.0 license intact and adds
`MODIFICATION_NOTICE.md` to identify this branch as the Abhash version.

## CI kept on this branch

- `Publish GHCR Image` tests the repository, builds a linux/amd64 Docker
  image, and pushes it to GHCR whenever `Abhash-Main` changes.
- `Sync Upstream` fetches `jellyfin/jellyfin:master`, merges it into a sync
  branch, tests the merged result, opens a pull request into `Abhash-Main`,
  merges that PR after the tests pass, and dispatches the publish workflow.

## Local rerere setup

Run this once in every clone where you resolve upstream conflicts:

```bash
git config rerere.enabled true
git config rerere.autoupdate true
```

`rerere` remembers how you resolved a conflict. If the same conflict appears
again during future upstream syncs, Git can reuse your previous resolution.

## GHCR image

The publish workflow writes this linux/amd64 image:

```text
ghcr.io/abhash-chakraborty/jellyfin-abhash:latest
```

The Dockerfile packages the backend server and ffmpeg. This source repository
does not include the Jellyfin web client, so the image starts with
`--nowebclient`. Use a Jellyfin app/client or provide a compatible web client
separately if you want the browser UI from this image.

