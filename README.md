# UnrestCoreSystem

An MVC-style UI framework for Roblox, written in Luau.

## Prerequisites

- [Rokit](https://github.com/rojo-rbx/rokit) 1.2.0 or newer, with `~/.rokit/bin` on `PATH`.
  Every other tool is pinned in `rokit.toml` and installed by Rokit; nothing else
  needs to be installed globally.
- Roblox Studio, if you want to live-sync with `rojo serve`.

Rokit shims refuse to run a tool that is not listed in a project manifest, so
`rokit install` must be run once inside this directory before `rojo`, `wally`,
`selene`, `stylua` or `luau-lsp` will work here.

```sh
rokit install
```

Pinned versions:

| Tool     | Version | Source                     |
| -------- | ------- | -------------------------- |
| rojo     | 7.7.0   | `rojo-rbx/rojo`            |
| wally    | 0.3.2   | `upliftgames/wally`        |
| selene   | 0.31.0  | `kampfkarren/selene`       |
| stylua   | 2.5.2   | `johnnymorganz/stylua`     |
| luau-lsp | 1.69.0  | `johnnymorganz/luau-lsp`   |

## Layout

`default.project.json` maps the repository onto the Roblox DataModel:

| Disk              | DataModel                                         |
| ----------------- | ------------------------------------------------- |
| `src/shared`      | `ReplicatedStorage.Unrest`                        |
| `Packages`        | `ReplicatedStorage.Packages`                      |
| `src/game-net`    | `ReplicatedStorage.GameNet`                       |
| `src/game-server` | `ServerScriptService.Game`                        |
| `src/game-client` | `StarterPlayer.StarterPlayerScripts.Game`         |

Everything the game owns is prefixed `game-`; `src/shared` is the framework.
The split is not cosmetic — the framework's own files were twice deleted by
someone who believed they were game code.

`Packages` is a required mount: the framework requires Scythe from it, so
`wally install` has to have been run before the place will load.

`bench.project.json` is the same tree plus `ReplicatedStorage.Bench` ->
`bench/`. Benchmarks are built with it and never ship in a normal build.

## Build

```sh
rojo build -o UnrestCoreSystem.rbxl        # place file
rojo build -o UnrestCoreSystem.rbxm        # model file
rojo build bench.project.json -o bench.rbxl   # place file with the benchmarks
rojo build model.project.json -o Unrest.rbxm  # the framework alone, for the Creator Store
```

Three project files, three audiences. `default.project.json` is what you develop
against. `bench.project.json` is the same tree plus `bench/`. `model.project.json`
is the framework and nothing else — no game code, no benchmarks — with Scythe
vendored inside it, because a model has no package manager behind it.

Build artifacts are gitignored.

## Serve (live sync into Studio)

```sh
rojo serve
```

Then connect with the Rojo plugin in Studio (default port 34872).

## Dependencies

Declared in `wally.toml`. Two, and only one of them is the framework's:

| Package | Who needs it |
| --- | --- |
| `synttx/scythe` | **the framework** — cleanup scopes, required in exactly one file, `src/shared/Util/Scope.luau` |
| `elitriare/bytenet-max` | the game's own remotes in `src/game-net`. The framework never touches it. |

```sh
wally install     # writes ./Packages and wally.lock
```

`wally.lock` is tracked; `Packages/`, `DevPackages/` and `ServerPackages/` are not.

Note: `wally install` rewrites `Packages/_Index` wholesale, which makes a running
`rojo sourcemap --watch` panic. The Neovim wrapper described below restarts Rojo
automatically when that happens.

## Publishing

Two channels, and they are not equivalent.

| | Wally | Creator Store |
| --- | --- | --- |
| Audience | people already using Rojo | people working directly in Studio |
| Dependencies | resolved for you | **none** — a model is a flat tree of Instances |
| Updating | `wally install` | re-insert by hand |

### Wally

The publishable manifest is `src/shared/wally.toml`, **not** the one at the root.
Wally uploads the directory holding the manifest, so publishing from `src/shared`
ships the framework and none of the game. The root manifest is `private = true`
so it cannot be published by accident.

```sh
wally login                      # authenticates through GitHub
cd src/shared && wally publish
```

The scope (`asyrawih`) must be a GitHub account or org you own. Add `repository`
to `src/shared/wally.toml` once the code is pushed somewhere.

### Creator Store

```sh
rojo build model.project.json -o Unrest.rbxm
```

Then in Studio: insert the model, right-click it, **Save to Roblox**. Then on the
Creator Dashboard, under Development Items, open it, fill in Name and
Description, toggle on **Distribute on Creator Store** under Distribution, set a
price (USD; models cannot be priced in Robux), and save.

To publish at all your account needs to be at least two days old, free of recent
bans, and verified by an age check or government ID — phone verification is not
enough. To sell you also need to be 18+ (or 13–17 with parental consent), have
2-Step Verification on, and live in a country the payments provider supports.

Mention in the description that the model bundles Scythe under MPL-2.0; see
`NOTICE.md`.

### The one rule that spans both

**There must only ever be one copy of Scythe in a place.** Its scope handles are
indices into module-level storage, so a second copy mints handles that address
somebody else's scopes — a bug with no error message. `src/shared/Util/Scope.luau`
is the only file that decides where Scythe is, it searches rather than naming a
path, and `unrest.Scope` re-exports it so game code never has to ask again.

## CI

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:
the three checks below, the version invariant, all three project files built, and
`Unrest.rbxm` uploaded as an artefact. Tool versions come from `rokit.toml`, so CI
runs the same binaries you do.

Two things it checks that no tool can:

* **The version is written twice** — `Constants.Version` and
  `src/shared/wally.toml` — because Luau cannot read a manifest. CI fails if they
  disagree.
* **The model must contain the framework and nothing else.** A publishable
  artefact that quietly shipped the sample game would be found by whoever
  installed it, not by us.

`.github/workflows/release.yml` runs on a tag:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

It refuses to continue unless the tag, `src/shared/wally.toml` and
`Constants.Version` all agree; then it re-runs the checks (a tag can be pushed at
a commit CI never saw), builds the model, creates a GitHub release with
`Unrest.rbxm` attached, and publishes to Wally **if** a `WALLY_AUTH_TOKEN` secret
exists. Without the secret that last step is skipped rather than failed — a
GitHub release is useful on its own, and an unset secret should not look like a
broken build.

To enable the Wally half: `wally login` locally, then copy the token out of
`~/.rokit/auth.toml` into a repository secret named `WALLY_AUTH_TOKEN`.

## Lint and format

```sh
selene .                # lint
stylua --check .        # verify formatting (CI)
stylua .                # apply formatting
```

`selene.toml` uses `std = "roblox"`. selene 0.31.0 ships the Roblox standard
library inside the binary, so no `roblox.toml` / `roblox.yml` is generated and
nothing extra is committed or ignored. On older selene versions you would need to
run `selene generate-roblox-std` once and commit the result.

`stylua.toml` shares `column_width`, `line_endings` and `quote_style` with the
user's `~/.config/nvim/.stylua.toml`, but uses the Roblox conventions of 4-space
indentation and `call_parentheses = "Always"` instead of that file's
Neovim-Lua conventions. `[sort_requires]` is enabled, so `require` blocks at the
top of a module are kept alphabetically sorted.

## Type checking

`.luaurc` sets `languageMode = "strict"` and defines path aliases used by
luau-lsp: `@Unrest` -> `src/shared`, `@GameServer` -> `src/game-server`,
`@GameClient` -> `src/game-client`, `@GameNet` -> `src/game-net`,
`@Packages` -> `Packages`. These aliases are resolved by luau-lsp /
`luau-lsp analyze` for editor navigation and type checking only — Roblox's
runtime `require` still takes an `Instance`, not a string.

```sh
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json src
```

## Neovim

The user's config (`~/.config/nvim/lua/plugins/luau.lua`, built on
AstroNvim + `lopi-py/luau-lsp.nvim`) globs `*.project.json` in the working
directory to decide which sourcemap strategy to use. Because
`default.project.json` exists at the repository root, it takes the Rojo branch:
it enables sourcemap autogeneration and spawns
`~/.config/nvim/scripts/rojo_sourcemap_watch.sh sourcemap.json`, a wrapper that
runs `rojo sourcemap --watch --output sourcemap.json <project> --include-non-scripts`
and restarts it whenever Rojo dies (Rojo 7.7.0 panics when a watched path
disappears, which is exactly what `wally install` does to `Packages/_Index`).
The server is configured with `platform.type = "roblox"` and
`roblox_security_level = "PluginSecurity"`. Workspace root resolution looks for
`*.project.json` first and falls back to `sourcemap.json`, `.luaurc`,
`selene.toml`, `stylua.toml` or `.git` — all of which exist here, so the root
resolves to the repository root regardless of which file is opened.

`sourcemap.json` is gitignored: it is regenerated continuously by that watcher.
Open Neovim from this directory (not from a subdirectory) so the `*.project.json`
glob matches.
