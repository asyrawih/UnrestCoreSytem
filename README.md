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

| Disk          | DataModel                                             |
| ------------- | ----------------------------------------------------- |
| `src/shared`  | `ReplicatedStorage.Unrest`                            |
| `Packages`    | `ReplicatedStorage.Packages` (optional path)          |
| `src/server`  | `ServerScriptService.UnrestServer`                    |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.UnrestClient`     |

`Packages` uses Rojo's optional-path form (`"$path": { "optional": "Packages" }`),
so `rojo build` and `rojo sourcemap` still succeed on a fresh clone where
`wally install` has not been run yet.

## Build

```sh
rojo build -o UnrestCoreSystem.rbxl        # place file
rojo build -o UnrestCoreSystem.rbxm        # model file
```

Build artifacts are gitignored.

## Serve (live sync into Studio)

```sh
rojo serve
```

Then connect with the Rojo plugin in Studio (default port 34872).

## Dependencies

Declared in `wally.toml`; currently none.

```sh
wally install     # writes ./Packages and wally.lock
```

`wally.lock` is tracked; `Packages/`, `DevPackages/` and `ServerPackages/` are not.

Note: `wally install` rewrites `Packages/_Index` wholesale, which makes a running
`rojo sourcemap --watch` panic. The Neovim wrapper described below restarts Rojo
automatically when that happens.

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
luau-lsp: `@Unrest` -> `src/shared`, `@Server` -> `src/server`,
`@Client` -> `src/client`, `@Packages` -> `Packages`. These aliases are resolved
by luau-lsp / `luau-lsp analyze` for editor navigation and type checking only —
Roblox's runtime `require` still takes an `Instance`, not a string.

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
