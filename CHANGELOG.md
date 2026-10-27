# Changelog

Notable changes to uz_AutoShot. Versions follow [Semantic Versioning](https://semver.org/). Full notes for every version are on the [releases page](https://github.com/uz-scripts/uz_AutoShot/releases).

## [Unreleased]

- Every GitHub release gets a ready-to-install `uz_AutoShot.zip`
- Contributor docs: `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue forms and a pull request template
- `resources/build` is no longer git-ignored. It was always committed, but the rule made `git add` refuse build files

## [2.3.0] - 2026-10-27

- Tattoo capture: one category per body zone from `Customize.Tattoos` or illenium-appearance's tattoo list, each tattoo shot alone on a bare-skin ped
- Torso tattoos split into front and back from the game's tattoo shop data, with `Customize.TattooFacing` overrides
- Wardrobe Tattoos tab: browse, try on and re-capture single tattoos
- `getTattooURL(gender, collection, overlay)` export
- Re-capture progress showed `prop_N` for overlays

## [2.2.0] - 2026-10-27

- Male / female studio ped toggle and **Capture both genders**, with saved camera angles per gender
- Upload backpressure (`Customize.MaxPendingUploads`) so long runs on remote servers no longer time out
- Server readiness check before the studio opens, with a clear message when `server.js` or `pngjs` is missing
- Your full appearance is restored when the studio or wardrobe closes
- Each frame is decoded once on the server, about 2.5x faster with byte-identical output
- Fixed: back-facing or in-car shots in multi-category runs, vehicles vanishing 0.3s after spawning, `hideHead` never applying, `getPhotoURL` returning `_0` URLs that do not exist

## [2.1.0] - 2026-04-29

- Captures travel as latent events; the bundled HTTP server and its port are gone
- `Customize.HeadMask` as a list of spheres, `Customize.LatentRate`, server-side ACE check on capture and bucket events
- Fixed: unsaved captures flipping 180° from the preview, falling through the map after closing the studio
- Removed: `getManifestURL`, `getServerPort`, `Customize.BackendURL` and the `/api/*` HTTP routes

## [2.0.0] - 2026-04-04

- Vehicle capture grouped by class with a color picker, object capture, 12 appearance overlay categories
- `/shotcar` and `/shotprop` for single captures
- Tabbed UI, redesigned orbit camera with roll, height and FOV controls, saved angles per category
- Head chroma mask for body-only captures
- `getVehiclePhotoURL` and `getObjectPhotoURL` exports
- Breaking: camera preset names changed, `Customize.Categories` needs `visibleComponents`

## [1.1.2] - 2026-03-30

- Photos served through `cfx-nui` instead of a local HTTP server, no port forwarding needed
- ACE permissions for the commands (`Customize.AceRestricted`)

## [1.1.0] - 2026-03-28

- `ScreenshotWidth` / `ScreenshotHeight` are applied
- Magenta chroma key, softer edges with despill and alpha feather, sharper downscaling
- Crop overlay in the preview

## [1.0.0] - 2026-03-25

First public release.

[Unreleased]: https://github.com/uz-scripts/uz_AutoShot/compare/v2.3.0...HEAD
[2.3.0]: https://github.com/uz-scripts/uz_AutoShot/releases/tag/v2.3.0
[2.2.0]: https://github.com/uz-scripts/uz_AutoShot/releases/tag/v2.2.0
[2.1.0]: https://github.com/uz-scripts/uz_AutoShot/releases/tag/v2.1.0
[2.0.0]: https://github.com/uz-scripts/uz_AutoShot/releases/tag/v2.0.0
[1.1.2]: https://github.com/uz-scripts/uz_AutoShot/releases/tag/1.1.2
[1.1.0]: https://github.com/uz-scripts/uz_AutoShot/releases/tag/v1.1.0
[1.0.0]: https://github.com/uz-scripts/uz_AutoShot/releases/tag/v1.0.0
