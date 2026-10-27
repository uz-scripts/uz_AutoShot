# Contributing to uz_AutoShot

Thanks for taking the time. Bug reports, fixes, docs improvements and new capture categories are all welcome.

For questions and setup help, use [Discord](https://discord.uz-scripts.com) instead of the issue tracker. Issues are for bugs and concrete feature requests.

## Reporting a bug

Use the [bug report form](https://github.com/uz-scripts/uz_AutoShot/issues/new?template=bug_report.yml). The things that make a bug fixable:

- uz_AutoShot version (`version` in `fxmanifest.lua`) and server artifact build
- Whether the server runs on your own PC or on a remote host. Upload problems often only show up remotely
- Your screenshot resource (`screenshot-basic` or `screencapture`), and your appearance resource for tattoo or appearance restore bugs
- Every `[uz_AutoShot]` line from the server console and F8
- For a bad image: the file from `shots/` and a screenshot of the preview framing

## Development setup

1. A local FiveM server with `screenshot-basic` (or `screencapture`, which provides it) and `yarn`.
2. Clone into your resources folder under the exact name `uz_AutoShot`:
   ```
   git clone https://github.com/uz-scripts/uz_AutoShot.git uz_AutoShot
   ```
3. Add `ensure uz_AutoShot` to `server.cfg` after `screenshot-basic`, then start the server. The Node dependency (`pngjs`) installs through yarn on first start. If the console says `pngjs is not installed`, delete `.yarn.installed` in the resource folder and restart, or run `npm install` there.
4. After a Lua change, run `restart uz_AutoShot` in the server console, then test with `/shotmaker` or `/wardrobe`.

### Working on the UI

The NUI lives in `resources/src` (React, Vite, Tailwind). FiveM loads the built copy in `resources/build`, which is committed so servers need no build step.

```
cd resources
npm install
npm run build
```

Commit `resources/build` together with the source change. `npm run dev` serves the UI in a browser at `http://localhost:3000`. There is no game there, so NUI callbacks do nothing; drive the UI by posting the same messages `client.lua` sends, for example `window.postMessage({ type: 'openMenu', ... })` from the browser console.

## Project layout

| Path | What lives there |
|---|---|
| `fxmanifest.lua`, `Customize.lua` | Manifest and every user-facing setting |
| `client/client.lua` | Studio, orbit camera, capture loops (clothing, props, overlays, tattoos, vehicles, objects), wardrobe, NUI callbacks, exports |
| `server/server.js` | Capture uploads: chroma key, resize, file write (Node, pngjs) |
| `server/config_bridge.lua` | Passes `Customize` fields to `server.js` as convars |
| `server/version.lua` | Folder name guard and the update notice in the server console |
| `resources/src/` | NUI source |
| `resources/build/` | Built NUI, committed |

## Code style

- Lua 5.4, 4 spaces, `local` everything. `client/client.lua` is split into sections under `-- ═══` banners; put new code in the matching section. State that several sections share is declared at the top of the file.
- `resources/src` uses 2 spaces, `server/server.js` 4. `.editorconfig` sets this for you.
- Short comments that explain why, not what. English only.
- Keep `Customize.lua` backwards compatible. A new setting needs a default that keeps the current behaviour, a fallback when it is missing (`Customize.X or default`), and a line in the README.
- Anything a client sends to the server is untrusted. Validate types, sizes and file names in `server.js`, and keep the ACE check in front of it.
- No new dependencies unless there is no reasonable way around it.

## Testing

There is no automated test suite yet, so test in game before opening a pull request:

- [ ] `/shotmaker`: a clothing, a prop and an overlay category capture with the background removed
- [ ] A multi-category run: every category faces the way it did in the preview
- [ ] The Male / Female toggle and **Capture both genders**
- [ ] Tattoos: at least **Torso (Back)** and one arm zone
- [ ] `/shotcar adder` and `/shotprop prop_bench_01a`
- [ ] `/wardrobe`: thumbnails load, clicking an item applies it, re-capture overwrites the file
- [ ] Closing the studio or the wardrobe restores your character, hair color and tattoos included
- [ ] If you touched uploads or `server.js`: a long run on a remote server, not only on localhost

## Pull requests

1. Fork, then branch from `main` (`fix/mask-angle`, `feat/hat-category`).
2. One change per pull request. A refactor and a fix in the same PR are hard to review.
3. Write commit messages as [Conventional Commits](https://www.conventionalcommits.org/) with a short imperative subject: `fix(capture): keep the head mask on for bags`.
4. Fill in the pull request template, including what you tested.
5. Update the README and the comments in `Customize.lua` when behaviour or settings change.
6. Do not commit `shots/`, `node_modules/` or your server's config changes. Do not bump the version in `fxmanifest.lua`; that happens at release.

A maintainer will review as soon as possible. Small, focused PRs get merged fastest.

## License

uz_AutoShot is licensed under [Apache 2.0](LICENSE). By opening a pull request you agree that your contribution is licensed under the same terms (section 5 of the license).
