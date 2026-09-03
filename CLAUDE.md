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

- `--!strict` everywhere. **One** third-party dependency: `synttx/scythe`, and it is deliberate
  — it replaced the framework's largest source of allocation. Its path is written in exactly
  one file, `src/shared/Util/Scope.luau`; requiring `Packages.Scythe` anywhere else risks a
  second copy of the module, whose scope handles silently mean something different.
  Adding a second dependency needs a reason of the same size.
- No `wait()` / `spawn()` / `delay()` — use `task.*`.
- stylua: 4 spaces, width 120, `call_parentheses = "Always"`, `sort_requires` on (requires
  sorted alphabetically by variable name).
- selene: `global_usage` and `unscoped_variables` are **deny**.

## Conventions that are load-bearing

- **Code raises; attributes warn.** Code binding a handler its element cannot support is a
  bug and throws. The same mistake made in an attribute is *data*, typed by somebody not
  watching the output window — warn, name the element and the fix, and keep the screen up.
- Every connection an element owns hangs off a **cleanup scope** (`src/shared/Util/Scope.luau`,
  re-exported as `Unrest.Scope`), so release is one line and cannot half-happen. A scope is an
  integer, not an object: hold it in a plain field, pass it around freely, and hand it to
  `Scope.add` to link it as a child of a longer-lived scope.
- **Raising must not leave half a set behind.** `Adapters.bind` checks the whole handler
  table before it connects anything, so a raise means nothing was wired; `Query` therefore
  binds an element *before* recording it, and `QueryHandle:Bind` proposes the merge against a
  copy and asks every element it holds before committing. Nothing is ever counted by
  `:Count()` that is not bound. The one thing `Bind` cannot check is an element tagged later:
  that one is refused on arrival and stays out of the set, and because the refusal reaches no
  caller it is raised on its own thread rather than unwinding the cascade sweep that found it.
- Framework vocabulary lives once in `src/shared/Constants.luau` — the tag, the attribute
  names, the inheritable set. **Game names do not live there.** Channel and command names
  belong to the game, next to the code that handles them, and the framework must never spell
  one.
- An attribute is **not a second mechanism**. `UnrestCommand` goes through the same
  `Bridge:Dispatch` as hand-written Luau and reaches the same handlers, so a screen wired in
  Studio and one wired in code are indistinguishable from the far side of the Bridge.
- Layer map: `Core` (never touches an Instance) -> `Bridge` -> `Elements` (never touches a
  system). The `Bridge` is a **local bus**: `Publish`/`Subscribe`/`Peek` one way,
  `Dispatch`/`Handle` the other, retained channels, and nothing that crosses a machine.
  There is no networking layer; the framework is UI abstraction only.
- **The cascade is one rule and one ledger.** `Selector` holds the rule -- `isManaged`,
  `cascadeUnder`, `isGate`, `gatesAbove`, `isPresent` -- as pure predicates with no state.
  `Adapters/Cascade.luau` holds the *bookkeeping* that keeps those answers live: the tagged
  roots, one `DescendantAdded` each, one `UnrestIgnore` watch per gate, and the re-sweeps a
  tag or an ignore edit triggers. `Elements` and `Query` each hand it four callbacks
  (`Cover` / `Uncover` / `Tracks` / `Covered`) and nothing else -- adopting vs. watching is
  all they are still allowed to disagree about. This was two copies once, ~74% identical, and
  the bug pattern this repo keeps hitting is one question answered in two places. Do not add a
  third copy, and do not move the ledger into `Selector`: state in there would cost the module
  the thing that makes it trustworthy.
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
| `default.project.json` mounts | `src/shared` (framework), `src/game-net`, `src/game-server`, `src/game-client` (the game's own), `Packages` — **and nothing else** |
| UI instances | only in the place file, created in Studio or via the Studio MCP |
| `studio/*.luau` | one-off command-bar seed scripts. **Not** a Rojo mount — never add one |
| `.gitignore` | already ignores `*.rbxl` / `*.rbxlx` / `*.rbxm` / `*.rbxmx`; keep it that way |

If a task seems to need UI in the repo, the answer is a tag and some `Unrest*` attributes on
an instance the designer already built — not a new mount point.

## Docs

`docs/ARCHITECTURE.md` and `docs/UI-BINDING.md` are part of the deliverable — keep them in
step with the code. The networking pages went with the networking layer.
