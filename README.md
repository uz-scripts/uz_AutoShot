# uz_AutoShot | Clothing Thumbnail Generator for FiveM

Automatic clothing thumbnail generator & browser for FiveM. Captures every drawable/texture variation with transparent backgrounds via green screen chroma key, then lets players browse them in a sleek in-game clothing menu.

<img src="uz-autoshot-preview.png" width="800" alt="uz_AutoShot Preview"/>

## How It Works

1. **`/shotmaker`** — Opens a capture studio: your ped teleports to an underground void with green screen walls and studio lighting. Select categories, adjust the orbit camera, then hit start.
2. **Automatic capture** — The script iterates through every drawable variation, applies it to the ped, waits for textures to stream, and takes a screenshot. Server-side chroma key removes the green background.
3. **`/wardrobe`** — Opens a visual clothing browser. Thumbnails are served via a local HTTP API — other scripts (clothing menus, shops) can consume the same photos with zero file duplication.

## Features

- **Automatic Capture** — Iterates every drawable and texture variation — camera framing adjusts automatically per clothing category
- **Custom Camera Angles** — Orbit, zoom, and save per-category angles — saved angles are reused automatically on every future capture
- **Green Screen Studio** — Underground void with configurable chroma key walls and studio lighting
- **Transparent Backgrounds** — Server-side green screen removal via pngjs (pure JS)
- **Clothing Browser** — Dual-panel HUD with categories and virtualized thumbnail grid
- **Re-capture Mode** — Select broken thumbnails and re-capture only those
- **Pause / Resume** — Pause long capture sessions and resume where you left off
- **HTTP API** — REST API with manifest, per-category filtering, and direct image serving
- **Lua Exports** — Client-side exports for other scripts to consume photos without file duplication
- **Zero Native Dependencies** — Only `pngjs` (pure JS) — no sharp, canvas, or native compilation

## Dependencies

- [screenshot-basic](https://github.com/citizenfx/screenshot-basic) *(most servers have this already)*

## Installation

1. Drop `uz_AutoShot` into your server's `resources` folder.
2. Add to `server.cfg`:
   ```
   ensure screenshot-basic
   ensure uz_AutoShot
   ```
3. Dependencies auto-install on first start via FiveM's built-in yarn.
4. The UI is pre-built — no build step needed for deployment.

## Commands

| Command | Description |
|---------|-------------|
| `/shotmaker` | Open capture preview — select categories, adjust camera, then start |
| `/wardrobe` | Open clothing browser — browse thumbnails, apply items, re-capture |

Both commands are configurable in `Customize.lua`.

## Configuration

All settings are in `Customize.lua`:

| Setting | Default | Description |
|---------|---------|-------------|
| `Customize.Command` | `'shotmaker'` | Capture command name |
| `Customize.MenuCommand` | `'wardrobe'` | Browser command name |
| `Customize.ScreenshotFormat` | `'png'` | Output format (`png` / `webp` / `jpg`) |
| `Customize.TransparentBg` | `true` | Enable green screen removal (PNG only) |
| `Customize.ScreenshotWidth` | `512` | Output image width (server-side resize, PNG only) |
| `Customize.ScreenshotHeight` | `512` | Output image height (server-side resize, PNG only) |
| `Customize.CaptureAllTextures` | `false` | Capture all texture variants (not just default) |
| `Customize.BatchSize` | `10` | Captures before each batch pause |

Camera presets, green screen dimensions, studio lighting, and categories are all fully configurable.

## API & Exports

### HTTP API (port 3959)

| Endpoint | Description |
|----------|-------------|
| `GET /api/manifest` | All photos |
| `GET /api/manifest/:gender/:type/:id` | Filter by category |
| `GET /api/exists?gender=&type=&id=&drawable=&texture=` | Check if photo exists |
| `GET /api/stats` | Count summary |
| `GET /shots/...` | Direct image serving |

### Lua Exports

```lua
exports['uz_AutoShot']:getPhotoURL('male', 'component', 11, 5, 0)
exports['uz_AutoShot']:getManifestURL('male', 'component', 11)
exports['uz_AutoShot']:getShotsBaseURL()
exports['uz_AutoShot']:getPhotoFormat()
exports['uz_AutoShot']:getServerPort()
```

### NUI / React Integration

Fetch directly from JavaScript — no Lua proxy needed:

```js
const res = await fetch('http://127.0.0.1:3959/api/manifest/male/component/11')
const { items } = await res.json()
```

Full API reference and integration examples: [uz-scripts.com/docs/uz-autoshot](https://uz-scripts.com/docs/free/uz-autoshot)

## File Structure

```
uz_AutoShot/
├── client/client.lua        # Capture engine & NUI callbacks
├── server/version.lua       # Auto version check
├── server/server.js         # HTTP server, chroma key, file I/O
├── Customize.lua        # All configuration
├── resources/build/         # Pre-built NUI
├── shots/                   # Generated thumbnails (git-ignored)
└── fxmanifest.lua
```

## Our Other Work

UZ Scripts specializes in high-performance, developer-friendly scripts for the FiveM ecosystem. Explore our full collection here: [uz-scripts.com/scripts](https://uz-scripts.com/scripts)

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
