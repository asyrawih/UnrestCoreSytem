# UnrestCoreSystem — project memory

Roblox Luau framework. It **builds no UI**: it adopts UI built by hand in Studio, opted in
with the CollectionService tag `Unrest`.

## Verify before reporting (all three must be clean across `src`)

```
rojo sourcemap default.project.json --output sourcemap.json
luau-lsp analyze --definitions=/tmp/globalTypes.d.luau --sourcemap=sourcemap.json $(find src -name '*.luau')
selene src && stylua --check src
```

`/tmp/globalTypes.d.luau` comes from
`https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.PluginSecurity.d.luau`.

## Constraints

- `--!strict` everywhere, zero third-party dependencies.
- No `wait()` / `spawn()` / `delay()` — use `task.*`.
- stylua: 4 spaces, width 120, `call_parentheses = "Always"`, `sort_requires` on (requires
  sorted alphabetically by variable name).
- selene: `global_usage` and `unscoped_variables` are **deny**.

## Conventions that are load-bearing

- **Code raises; attributes warn.** Code binding a handler its element cannot support is a
  bug and throws. The same mistake made in an attribute is *data*, typed by somebody not
  watching the output window — warn, name the element and the fix, and keep the screen up.
- Every connection an element owns hangs off a `Util/Maid`, so release is one line and
  cannot half-happen.
- Framework vocabulary lives once in `src/shared/Constants.luau` — the tag, the attribute
  names, the remote names, the limits. **Game names do not live there.** Channel and command
  names belong to the game, in `src/game/`, and the framework must never spell one.
- An attribute grants **no privilege**. `UnrestCommand` goes through the same
  `Bridge:Dispatch` as hand-written Luau, and the command contract decides what a client may
  ask for. Contracts are a registry the game fills through `Contracts:Declare`, so an empty
  registry means nothing is callable rather than everything.
- Layer map: `Core` (never touches an Instance) -> `Bridge` -> `Elements` (never touches a
  system). `Net` is the same Bridge across the client/server line.
- **A tag outlives its instance.** `Destroy()` takes an instance out of
  `CollectionService:GetTagged` but leaves the tag on it, so `HasTag` answers `true` forever
  after. `Selector.isManaged` therefore asks `IsDescendantOf(game)` first: managed means
  *tagged and in the DataModel*, which is the same line `GetTagged` and the tag-added /
  tag-removed signals draw. Anything that reads the tag directly has to remember this.

## Attribute resolution (`src/shared/Elements/init.luau`)

`element.Attributes` is a merge of three layers, weakest first — **most specific wins**:

1. nearest ancestor's inheritable attribute (weakest)
2. the `UnrestPreset` bundle from `src/shared/Presets.luau`
3. the element's own attribute (strongest)

A preset is a default, never an override. `element.Sources[name]` records which layer won.

**Inherit context, never intent.** Only the names in `Constants.Inheritable`
(`UnrestGroup`, `UnrestCooldown`, `UnrestPreset`) are inheritable. `UnrestRole`,
`UnrestCommand`, `UnrestPayload`, `UnrestChannel`, `UnrestBind` and `UnrestFormat` are
per-element intent — inheriting a command would silently arm every descendant of a panel.

The ancestor walk stops at the first `LayerCollector` (inclusive) and never reads a service
or the DataModel.

The precedence itself is one function: **`Selector.attributeOf(instance, name)`** returns the
value and an `AttributeSource`, applying own > preset > nearest ancestor (that last layer only
for `Constants.Inheritable`; `UnrestPreset` skips the preset layer). `Elements.resolve` asks it
for every key of `element.Attributes`, and `Selector.groupOf` asks it for `UnrestGroup` — so
what the framework reports about an element and what a query matches on cannot come apart.
It builds on two helpers in the same module: `Selector.inheritedProviders(instance, names)`
(nearest ancestor per name) and `Selector.presetFor(instance)` (the preset name, its bundle and
where the name was typed — own beating inherited).

`Descriptor.Group` matching therefore sees inherited groups, including a group a preset on a
ScreenGui supplies: `UnrestGroup` written once up there is enough for
`Unrest:Query({ Group = ... })` to select everything under it. `Selector.ancestorChain` is the
single definition of the walk — `Selector.inheritedProviders` reads with it, `Elements` watches
the chain it returns, and `Query` watches it too, so none of them can disagree about which
ancestors count.

Liveness on the chain is `Selector.ancestorTriggers(compiled)`: the inheritable subset of
`Selector.triggers`, derived rather than restated. A `Group` filter therefore watches both
`UnrestGroup` and `UnrestPreset` on every ancestor, because either can change the answer.
`Selector.watchesAncestors` is answered from the same list.

`Selector.roleOf` deliberately does **not** walk: a role is identity, and inheriting one would
give every descendant of a panel the same name.

## UI never enters the Rojo tree — hard rule

**Build UI through the Roblox Studio MCP connection, live in the place file. Never write it
into Rojo.** No `.rbxmx`/`.model.json`/`.meta.json` for a ScreenGui, no `StarterGui` mount in
`default.project.json`, no `Instance.new("Frame")` in `src/`, no "just this once" exception.

This is the framework's own thesis, not a preference: Unrest **builds no UI**. It adopts UI
made by hand in Studio and opted in with the `Unrest` tag. The moment a ScreenGui is
committed as source, the framework is generating the thing it exists not to generate, and the
tag stops being the whole opt-in.

Where things are allowed to live:

| | |
| --- | --- |
| `default.project.json` mounts | `src/shared`, `src/server`, `src/client`, `Packages` — **and nothing else** |
| UI instances | only in the place file, created in Studio or via the Studio MCP |
| `studio/*.luau` | one-off command-bar seed scripts. **Not** a Rojo mount — never add one |
| `.gitignore` | already ignores `*.rbxl` / `*.rbxlx` / `*.rbxm` / `*.rbxmx`; keep it that way |

If a task seems to need UI in the repo, the answer is a tag and some `Unrest*` attributes on
an instance the designer already built — not a new mount point.

## Docs

`docs/ARCHITECTURE.md`, `docs/UI-BINDING.md`, `docs/REMOTE-SECURITY.md` are part of the
deliverable — keep them in step with the code.
