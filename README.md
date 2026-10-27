# uz_AutoShot

**All-in-one screenshot studio for FiveM. Captures clothing, props, vehicles, world objects, and appearance overlays with transparent backgrounds.**

Iterates every drawable and texture automatically, runs chroma key removal server-side, and serves the results in an in-game browser. No external tools needed.

<img src="uz-autoshot-preview.png" width="800" alt="uz_AutoShot Preview"/>

<p>
  <img width="12%" alt="clothing-1"  src="https://github.com/user-attachments/assets/3ceed7d8-b7f9-4240-902e-e71f8cf36518" />
  <img width="12%" alt="clothing-2"  src="https://github.com/user-attachments/assets/ae90d820-745c-492f-8ad2-5f0eaa502ab3" />
  <img width="12%" alt="clothing-4"  src="https://github.com/user-attachments/assets/dc655ac8-8444-47c1-bce2-a612a8eccad5" />
  <img width="12%" alt="clothing-5"  src="https://github.com/user-attachments/assets/07b93377-2532-4e8b-9dab-e32d3da5c346" />
  <img width="12%" alt="clothing-7"  src="https://github.com/user-attachments/assets/1e90fa62-f64e-4586-8b6d-83dce678f1fa" />
  <img width="12%" alt="clothing-8"  src="https://github.com/user-attachments/assets/5434cb8a-0d73-4100-a73e-8eda7626fcd9" />
  <img width="12%" alt="clothing-9"  src="https://github.com/user-attachments/assets/4593f92e-b9c9-4e4f-99de-fa97a2364718" />
  <img width="12%" alt="clothing-10" src="https://github.com/user-attachments/assets/bf1d2cb3-7faa-434e-91fe-c6b3e2713ebf" />
  <img width="12%" alt="clothing-11" src="https://github.com/user-attachments/assets/5672bc1e-84bf-4f6c-b167-0383cc483608" />
  <img width="12%" alt="clothing-13" src="https://github.com/user-attachments/assets/b28dba8a-8d25-4ce2-a0f3-26bc9d45f71c" />
  <img width="12%" alt="vehicle-2"   src="https://github.com/user-attachments/assets/d708b593-f96b-44a5-8933-eb0a35600a79" />
  <img width="12%" alt="vehicle-3"   src="https://github.com/user-attachments/assets/69725c7e-9cfa-4450-b631-5441f46a4af8" />
  <img width="12%" alt="vehicle-6"   src="https://github.com/user-attachments/assets/3689ea2c-4a76-47d3-8903-9bd3daf06442" />
  <img width="12%" alt="vehicle-4"   src="https://github.com/user-attachments/assets/f381a224-27f7-4a5f-a41f-392bf016cf12" />
  <img width="12%" alt="vehicle-5"   src="https://github.com/user-attachments/assets/e16a5fb1-2c10-42d1-a097-af57d411cd99" />
  <img width="12%" alt="vehicle-7"   src="https://github.com/user-attachments/assets/d0920b85-eff4-4f19-89c4-5a9781d0e3c1" />
  <img width="12%" alt="clothing 14" src="https://github.com/user-attachments/assets/a09d2b60-30e3-4b4d-9571-3ec5309e8a4e" />
  <img width="12%" alt="object"      src="https://github.com/user-attachments/assets/6149adf2-121d-4764-906a-2cba2ad4900a" />
  <img width="12%" alt="vehicle-1"   src="https://github.com/user-attachments/assets/63596701-158c-468a-8d26-edf9ccb1fea1" />
</p>

---

## Features

- **Clothing components**: 11 ped slots (hair, mask, arms, pants, bags, shoes, accessories, undershirt, body armor, decals, tops) iterated by drawable and texture.
- **Prop slots**: hats, glasses, ears, watches, bracelets. Watch and bracelet slots play a wrist-raise animation during capture.
- **Head overlays**: 12 categories including facial hair, eyebrows, makeup, blemishes, ageing, blush, complexion, lipstick, moles, chest hair.
- **Vehicle capture**: auto-detects every loaded vehicle model and groups by class. Built-in primary / secondary color picker before each batch.
- **Object capture**: configurable list of world props in `Customize.lua`. Edit the table or use a one-off command.
- **Orbit camera**: rotate, roll, zoom, height, FOV. Save framing per category mid-session, copy current values to clipboard in Lua format.
- **Male and female peds**: switch the studio ped between `mp_m_freemode_01` and `mp_f_freemode_01` from the preview header, or capture both genders in one run.
- **Appearance restore**: your ped's look (hair color, head blend, overlays, tattoos) is restored after the studio closes. Uses `illenium-appearance` / `fivem-appearance` when running, native fallback otherwise.
- **Server-side chroma key**: magenta or green background removal in Node with despill and 5x5 alpha feather for smooth edges.
- **Wardrobe browser**: `/wardrobe` opens a thumbnail grid with category sidebar, drawable-id search, and click-to-apply preview on your ped.
- **Re-capture broken thumbnails**: select bad shots in the wardrobe, re-shoot only those without re-running the entire batch.
- **Pause and resume**: long capture sessions can be paused mid-batch (default Space) and resumed without losing progress.
- **Quick capture commands**: `/shotcar <model>` and `/shotprop <model>` skip the UI for one-off captures.
- **Cross-resource integration**: server exports return `cfx-nui` photo URLs that any other resource's NUI can render with `<img src="...">`. No HTTP, no port forwarding, no base64.
- **Configurable head chroma mask**: stack multiple spheres on `SKEL_Head` to wipe the head out for accessory and torso shots without clipping the clothing.

---

## How it works

Type `/shotmaker`, pick what you want to capture, frame the orbit camera, hit Start. Your ped teleports into a hidden studio room, the script iterates every drawable and texture, snaps each frame, and uploads it to the server through a FiveM latent event. The server runs a chroma key pass to remove the background, resizes the result, and writes it to `shots/`. `/wardrobe` browses the output, lets you re-apply items to your ped, and re-captures broken shots. Photos are served straight out of the resource folder over the `cfx-nui` protocol, so other scripts (vehicleshop, clothing menu, ID card, MDT) can `<img src="...">` them directly.

---

## Requirements

- [screenshot-basic](https://github.com/citizenfx/screenshot-basic) *(included on most servers)*
  or [screencapture](https://github.com/itschip/screencapture) *(recommended replacement)*
- FiveM server artifacts with `yarn` support (built-in since 4892+)
- Optional: [illenium-appearance](https://github.com/iLLeniumStudios/illenium-appearance) or fivem-appearance, for a full appearance restore (tattoos included) when the studio closes

---

## Install

1. Drop the folder into `resources/`. The folder must be named exactly `uz_AutoShot` (case-sensitive on Linux). The resource will refuse to start with any other name.
2. Add to `server.cfg` in this order:

   ```
   ensure screenshot-basic
   ensure uz_AutoShot
   ```

3. Start the server. Node dependencies install on first start through the bundled `yarn` runtime. The UI is pre-built in `resources/build/`, no npm step needed.
4. Open `Customize.lua` if you want to change the command names, ACE gating, or chroma color. The defaults are fine for most setups.

---

## Commands

| Command | What it does |
|---------|--------------|
| `/shotmaker` | Open the capture studio. Pick categories, frame the camera, hit Start. |
| `/wardrobe` | Browse captured thumbnails. Apply items to your ped, re-shoot broken ones. |
| `/shotcar <model>` | Capture a single vehicle by spawn name. Skips the full UI. |
| `/shotprop <model>` | Capture a single world object by model name. |

Both `/shotmaker` and `/wardrobe` use the names from `Customize.Command` and `Customize.MenuCommand`, change them there if you want different command names.

### ACE permissions

Set `Customize.AceRestricted = true` in `Customize.lua` to gate the commands. Then in `server.cfg`:

```cfg
add_ace identifier.license:YOUR_LICENSE command.shotmaker allow
add_ace identifier.license:YOUR_LICENSE command.wardrobe allow
add_ace identifier.license:YOUR_LICENSE command.shotcar allow
add_ace identifier.license:YOUR_LICENSE command.shotprop allow
```

Or grant the whole admin group:

```cfg
add_ace group.admin command allow
add_principal identifier.license:YOUR_LICENSE group.admin
```

When `AceRestricted = true`, the server also rejects any capture event from a player that lacks `command.shotmaker`. This is wired through `server/config_bridge.lua`, which exposes `Customize.AceRestricted` to `server.js` via convars at startup.

---

## Camera controls

The orbit camera is active during the preview step before each capture session and during single-shot captures (`/shotcar`, `/shotprop`).

| Key | Action |
|-----|--------|
| Left mouse drag | Rotate around the subject |
| Right mouse drag | Roll the camera |
| Scroll wheel | Zoom in / out |
| W / S (or arrow up/down) | Adjust camera height |
| Q / E | Adjust field of view |
| R | Reset to the category's default angle |
| C | Copy the current camera values to your clipboard in Lua format, ready to paste into `Customize.CameraPresets` |

To save the framing for a category mid-session, click the camera icon on its row in the preview UI. On a row that is not active, the first click only selects the category and moves the camera there; click again to save. Saved angles persist for the session: when the batch reaches a category you saved, that framing is reused automatically. Categories you did not save use their default preset angle, not the last framing you looked at.

Ped angles are saved per gender. If a category has no saved angle for the current gender, the angle saved for the other gender is used.

### Male / female ped

The **Male / Female** toggle in the preview header swaps the studio ped model. Photos go to `shots/male/` or `shots/female/` accordingly. Turn on **Capture both genders** in the footer to shoot the selected ped categories for the current gender first, then the other gender, in one run. Vehicles and objects are captured once.

---

## Configuration

All settings live in [`Customize.lua`](Customize.lua). Common knobs:

| Setting | Default | Description |
|---------|---------|-------------|
| `Customize.Command` | `'shotmaker'` | Capture command name |
| `Customize.MenuCommand` | `'wardrobe'` | Browser command name |
| `Customize.AceRestricted` | `false` | Require ACE permission for commands and capture events |
| `Customize.ScreenshotFormat` | `'png'` | Output format: `'png'`, `'webp'`, or `'jpg'` |
| `Customize.TransparentBg` | `true` | Chroma key removal (PNG only) |
| `Customize.ScreenshotWidth` | `512` | Output image width |
| `Customize.ScreenshotHeight` | `512` | Output image height |
| `Customize.CaptureAllTextures` | `false` | Capture all texture variants (not just default) |
| `Customize.ChromaKeyColor` | `'magenta'` | Background color: `'green'` or `'magenta'` |
| `Customize.BatchSize` | `10` | Captures per batch before cooldown |
| `Customize.LatentRate` | `8000000` | Bytes/sec throttle per capture upload (the full-screen frame) |
| `Customize.MaxPendingUploads` | `2` | Uploads in flight before the capture loop waits for the server |

Camera presets, studio lighting, green screen dimensions, the head chroma mask (`Customize.HeadMask`), clothing/prop/overlay categories, and the object list are also configurable in the same file. Full reference at [uz-scripts.com/docs/free/uz-autoshot](https://uz-scripts.com/docs/free/uz-autoshot).

---

## Lua exports

The URL exports return `cfx-nui` paths that any NUI in any resource can render directly via `<img src="...">`. No HTTP request, no base64, no port forwarding.

```lua
exports['uz_AutoShot']:getPhotoURL('male', 'component', 11, 5, 0)
-- 'https://cfx-nui-uz_AutoShot/shots/male/11/5.png'

exports['uz_AutoShot']:getPhotoURL('male', 'component', 11, 5, 2)
-- 'https://cfx-nui-uz_AutoShot/shots/male/11/5_2.png'

exports['uz_AutoShot']:getPhotoURL('male', 'prop', 0, 12, 0)
-- 'https://cfx-nui-uz_AutoShot/shots/male/prop_0/12.png'

exports['uz_AutoShot']:getPhotoURL('male', 'overlay', 1, 3, 0)
-- 'https://cfx-nui-uz_AutoShot/shots/male/overlay_1/3.png'

exports['uz_AutoShot']:getVehiclePhotoURL('adder')
-- 'https://cfx-nui-uz_AutoShot/shots/vehicles/adder.png'

exports['uz_AutoShot']:getObjectPhotoURL('prop_bench_01a')
-- 'https://cfx-nui-uz_AutoShot/shots/objects/prop_bench_01a.png'

exports['uz_AutoShot']:getShotsBaseURL()
-- 'https://cfx-nui-uz_AutoShot/shots'

exports['uz_AutoShot']:getPhotoFormat()
-- 'png'  (extension on disk: always 'png' while TransparentBg is on, else Customize.ScreenshotFormat)
```

`getPhotoURL(gender, itemType, id, drawable, texture)` arguments:

- `gender`: `'male'` or `'female'`
- `itemType`: `'component'`, `'prop'`, or `'overlay'`
- `id`: component id (1-11, see `Customize.Categories`), prop id (0, 1, 2, 6, 7), or overlay index (0-11)
- `drawable`: drawable id
- `texture`: texture id. Ignored for `'overlay'`. `0` (or `nil`) maps to `<drawable>.<ext>`, anything above to `<drawable>_<texture>.<ext>`, matching the files on disk (see Output folder). Textures above 0 only exist if you captured with `Customize.CaptureAllTextures = true`.

All exports return strings synchronously. No async, no callbacks.

---

## Output folder

Photos live in `resources/uz_AutoShot/shots/`. Texture 0 is always `<drawable>.<ext>`. Other textures are only captured with `Customize.CaptureAllTextures = true` and are named `<drawable>_<texture>.<ext>`.

Overlays never use a texture suffix.

```
shots/
├── male/
│   ├── 2/                 # Hair (componentId 2)
│   │   ├── 0.png          # default: <drawable>.png
│   │   └── 1.png
│   ├── 11/                # Tops (componentId 11)
│   │   ├── 5.png          # default
│   │   └── 5_2.png        # only when CaptureAllTextures = true
│   ├── prop_0/            # Hats (propId 0)
│   │   └── 0.png
│   └── overlay_1/         # Facial Hair (overlayIndex 1)
│       ├── 0.png
│       └── 1.png
├── female/
│   └── ...
├── vehicles/
│   ├── adder.png
│   └── ...
└── objects/
    ├── prop_bench_01a.png
    └── ...
```

After a fresh capture, restart the resource before any other script can `<img src>` the new file. See the first row of Troubleshooting.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| **Wardrobe and other UIs don't see brand-new captures.** | Restart the resource (`restart uz_AutoShot` or `refresh; ensure uz_AutoShot`). FiveM indexes the `cfx-nui` `files {}` block at resource start, so new PNGs only become servable after the next start. Existing photos keep working without restart. This is the single most common gotcha, do this first. |
| Thumbnails come out fully black or blank. | `screenshot-basic` must start before `uz_AutoShot` in `server.cfg`. Watch the server console for `[uz_AutoShot] Saved: ...` lines while capturing. For vehicles, an F8 line `Vehicle <model> was deleted before capture` means another resource (vehicle cleanup, anticheat) is removing client-side vehicles. |
| `uz_AutoShot: pngjs missing on server` or `Server side not responding` when opening the studio, or F8 shows `Upload #N not confirmed by server` and `shots/` stays empty. | The server script is not running. Most often `pngjs` is missing: a `.yarn.installed` file without a `node_modules` folder (for example after copying the resource without it) makes yarn skip the install. Delete `.yarn.installed` and restart the server, or run `npm install` in the resource folder. Otherwise, check the server console for a `server.js` error on startup. |
| F8 shows `Capture skipped (...): screenshot-basic did not respond within 10s`. | `screenshot-basic` is missing, stopped, or outdated. Update it and make sure it starts before `uz_AutoShot`. |
| Magenta or green halo around the subject. | Switch `Customize.ChromaKeyColor`. Magenta tends to cut cleaner on skin tones, green is friendlier with red/orange clothing. |
| Head clips into hats, hoods, or armor. | Tune `Customize.HeadMask`. Make the existing sphere smaller, or stack a second sphere for the neck. The commented neck entry in `Customize.lua` is a starting point. |
| Resource refuses to start, console shows a name error. | Folder must be named exactly `uz_AutoShot`, case-sensitive. |
| Wardrobe is empty. | Run `/shotmaker` to generate photos first, then restart the resource (see the first row). |
| Lag, rising ping, or `Timed out after 60 seconds` while capturing on a remote server. | Each capture uploads the full-screen frame; `ScreenshotWidth`/`ScreenshotHeight` only set the size the server resizes to, so lowering them does not shrink the upload. Lower your game resolution while capturing, and set `Customize.LatentRate` at or below your real upload speed (e.g. `2000000` for ~16 Mbit/s). `Customize.MaxPendingUploads` keeps the backlog bounded. |
| Kicked with `Reliable network event size overflow: uz_autoshot:server:processCapture`. | v2.1.0+ sends captures as latent events, which never hit that limit. Seeing it means an outdated or modified `client.lua`, or another resource wrapping `TriggerLatentServerEvent`. Reinstall from the latest release. |
| Single capture failing for a model. | Spawn name typo. Use `/shotcar adder` or `/shotprop prop_bench_01a` with the exact model spawn name. |

---

## Layout

```
uz_AutoShot/
├── Customize.lua            # All config
├── fxmanifest.lua
├── client/client.lua        # Capture engine, orbit camera, NUI callbacks, exports
├── server/
│   ├── server.js            # Chroma removal, resize, file write
│   ├── config_bridge.lua    # Surfaces Customize fields to server.js as convars
│   └── version.lua          # Folder-name guard + version check
├── resources/build/         # Pre-built UI (React + Vite)
└── shots/                   # Generated thumbnails (git-ignored)
```

---

## More by UZ Scripts

uz_AutoShot is part of a larger catalog. The rest of our scripts are at [uz-scripts.com/scripts](https://uz-scripts.com/scripts).

Stuck on something or have an idea? Drop into the Discord: [discord.uz-scripts.com](https://discord.uz-scripts.com). Full docs and changelogs live at [uz-scripts.com/docs/free/uz-autoshot](https://uz-scripts.com/docs/free/uz-autoshot).

## License

Apache License 2.0. See [LICENSE](LICENSE).
