# Plugins on Abhash Jellyfin

This document explains two things:

1. **Why most third-party Jellyfin plugins do not load on this fork** (the root
   cause of "I add a plugin and it never shows up").
2. **The bundled "Abhash Themes" plugin** — how to use it to restyle the web
   client, and how to update themes later without rebuilding anything.

---

## 1. Why community plugins don't appear

### What you observe

You connect a plugin repository (for example the default
`https://repo.jellyfin.org/.../manifest.json`), install a plugin, restart, and
the plugin never becomes active — it either silently disappears or shows as
**Not Supported / Malfunctioned**.

### The actual cause: ABI version mismatch

This fork tracks **upstream Jellyfin `master`**, which reports application
version **`12.0.0`** (see `SharedVersion.cs`). `master` is a *pre-release*
development line, not a stable release.

Almost every community plugin in the ecosystem is compiled against the **stable
`10.x` ABI** (`10.8`, `10.9`, `10.10`, …). On a `12.0.0` server:

- The plugin catalog **shows** those plugins, because the catalog keeps any
  version whose `targetAbi` is **≤** the server version, and `12.0.0` is greater
  than `10.x`. (See `InstallationManager.GetPackages`.)
- But when the server tries to **load** the plugin assembly, it calls
  `Assembly.GetTypes()` (`PluginManager.LoadAssemblies`). A plugin built against
  `10.x` references types/method signatures that changed on `master`, so this
  throws `ReflectionTypeLoadException`. The plugin is then marked
  **`NotSupported`** and never activates.

So the install "succeeds," the catalog lists it, but it can never run. This is
**inherent to running a `master`/`12.0.0` build** — it is not a bug introduced by
this fork (the plugin subsystem here is unmodified upstream code).

### How to confirm it yourself

Check the server log (under `/config/log`). A rejected plugin logs a line like:

```
Failed to load assembly ... This error occurs when a plugin references an
incompatible version of one of the shared libraries. Disabling plugin
```

### Your options

| Option | What it means | Trade-off |
|--------|---------------|-----------|
| **Use plugins built for 12.0.0** | Only install plugins explicitly compiled against this server ABI (e.g. ones you build yourself from this tree, like the bundled theme plugin below). | Guaranteed to load; small ecosystem. |
| **Pin the fork to a stable 10.x** | Change `SharedVersion.cs` to a stable release version so the whole `10.x` plugin ecosystem becomes ABI-compatible. | Permanent core change; conflicts with the daily upstream-`master` sync workflow, which would keep pulling `master` back in. Not recommended unless you stop tracking `master`. |
| **Ship UI changes as our own plugin** | Build the customization you actually want against this exact tree, so it always loads. | This is what the **Abhash Themes** plugin does. |

---

## 2. The Abhash Themes plugin

`Abhash Themes` is a small plugin **built from this repository against the
12.0.0 server**, so it is always ABI-compatible and always loads. It lets you
inject a CSS theme (and, optionally, JavaScript) into the web client, and change
it any time from the dashboard — **no image rebuild required**.

It lives at `plugins/Jellyfin.Plugin.AbhashThemes/` and is bundled into the
Docker image automatically (see "How it ships" below).

### How to use it

1. Open the web UI → **Dashboard → Plugins → Abhash Themes**.
2. Tick **Enable theme injection**.
3. Either:
   - pick a **Curated theme** from the dropdown, or
   - paste a **Custom CSS URL** (a raw stylesheet link, e.g. a GitHub
     `raw.githubusercontent.com` or `cdn.jsdelivr.net` URL), and/or
   - paste **Custom CSS** inline.
4. Click **Save**, then reload the web client (Ctrl/Cmd-Shift-R for a hard
   reload). The theme is applied.

Updating later is the same flow: change the selection, Save, reload. Because the
plugin fetches the stylesheet server-side on demand (with a short cache), you can
point it at a theme that updates upstream and just reload to pick up changes.

### Curated themes

The dropdown ships a few popular community CSS themes (e.g. CTalvio's
*Monochromic / Kaleidochromic / Novachromic*) served from a public CDN. These
are **convenience starting points**, not maintained by this fork — if one breaks
or you prefer another, paste any raw CSS URL into the Custom CSS URL field
instead. See `plugins/Jellyfin.Plugin.AbhashThemes/CuratedThemes.cs`.

### Custom JavaScript (advanced, off by default)

There is an optional **Allow custom JavaScript** toggle. It is **disabled by
default** on purpose: enabled, it executes the JavaScript you provide in **every
client browser, including before login**. Only enable it with code you fully
trust and control. CSS-only theming is the safe default.

### How it reaches the web client

The web client is served as static files and is overwritten on every upstream
sync, so editing the web source directly would not persist. Instead, during the
Docker **web build**, `scripts/patch-jellyfin-web.sh` injects a single line into
`index.html`:

```html
<script defer src="/AbhashThemes/inject.js"></script>
```

That endpoint is served by the plugin's API controller
(`AbhashThemesController`). It returns a tiny script that injects a
`<style id="abhash-theme">` element built from your configured CSS (and the
optional JS). If the plugin is disabled or absent, the endpoint returns a
harmless no-op, so the page is never broken.

> **BaseUrl note:** the injected path is absolute (`/AbhashThemes/inject.js`). If
> you configure a non-root `BaseUrl` in Networking, adjust accordingly.

### How it ships and auto-installs

- The plugin is compiled in the Docker `build` stage and staged into the image
  at `/app/bundled-plugins/AbhashThemes_<version>/` (just the plugin DLL +
  `meta.json` — the shared `MediaBrowser.*` assemblies are resolved from the
  host at load time).
- On container start, `scripts/docker-entrypoint.sh` copies the staged plugin
  into `${JELLYFIN_DATA_DIR}/plugins` (i.e. `/config/plugins`) if it isn't
  already there, then launches Jellyfin. Your saved settings live outside the
  plugin folder (keyed by plugin GUID), so re-seeding never wipes them.

### Building / iterating locally

```bash
# Build just the plugin (requires the .NET 10 SDK):
dotnet publish plugins/Jellyfin.Plugin.AbhashThemes/Jellyfin.Plugin.AbhashThemes.csproj -c Release

# Or build the whole image (compiles server + plugin + web together):
docker build --target runtime -t jellyfin-abhash:test .
```

To drop a locally built plugin into an existing install, copy
`Jellyfin.Plugin.AbhashThemes.dll` and `meta.json` into a folder named
`AbhashThemes_<version>` under `/config/plugins`, then restart.
