````
                     ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
  _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
/==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
|==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
|==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
|==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
|==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
|==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
`-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`
````

[Discord](https://discord.gg/MZYTABSSfb)

# UnrestCoreSystem — engineering conventions

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
  — it replaced the framework's largest source of allocation. **There must only ever be one
  copy of it in a place**: scope handles are indices into module-level storage, so a second
  copy mints handles that address somebody else's scopes, with no error to show for it.
  `src/shared/Util/Scope.luau` is the only file that decides where Scythe is, and it *searches*
  rather than naming a path, because the framework ships three ways and Scythe lands somewhere
  different in each — beside the package folder (Wally), at `ReplicatedStorage.Packages.Scythe`
  (source checkout), or vendored as `Unrest.Scythe` (Creator Store model, which has no package
  manager behind it). Requiring Scythe anywhere else, by any path, reintroduces the second copy.
  Adding a second dependency needs a reason of the same size.
- **Three project files, three audiences.** `default.project.json` is what you develop against;
  `model.project.json` is the framework alone plus the vendored Scythe, and is what the
  Creator Store model is built from; `plugin/default.project.json` is the Studio plugin. `src/shared/wally.toml`
  is the publishable manifest — the root one is `private` and exists only for `wally install`.
- **`vendor/Scythe.luau` is a verbatim MPL-2.0 copy and must stay verbatim.** It is excluded
  from stylua and selene (`.styluaignore`, `selene.toml`) for that reason, not by oversight.
  See `NOTICE.md`; when the Wally pin moves, re-copy it.
- **The version is written twice** — `Constants.Version` and `src/shared/wally.toml`. There is
  no way to make Luau read a manifest, so this one is kept in step by hand. Move both; CI
  fails the build if they disagree, and the release workflow additionally requires the git tag
  to match.
- **CI is `.github/workflows/ci.yml`** and runs exactly the three checks above plus the two
  invariants no tool can see: the version pair, and that `model.project.json` picks up nothing
  from `src/game-*` or `plugin/`. The setup shared with the release workflow lives in
  `.github/actions/setup`; do not inline a second copy of it.
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
  table before it connects anything, so a raise means nothing was wired. `Adapters.bindChecked`
  skips that pre-flight and is ONLY for a caller that has just run `Adapters.rejects` itself and
  been told nil — `Query` does, twice, because it needs the rejection string to choose which
  thread to raise on. Reaching for it anywhere else reintroduces the half-wired element.
  Consequently `Query` binds an element *before* recording it, and `QueryHandle:Bind` proposes the merge against a
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
  There is exactly **one element `Elements` does not wire**, and it is worth knowing about: an
  instance that sets `UnrestWidget` is the root of a widget, and its `UnrestCommand` and
  `UnrestChannel` are routed by `Widgets` through the control mounted there instead — a
  slider's value is several instances and a gesture with an end, not one property of a Frame.
  `Selector.isWidgetRoot` is the predicate and `Elements`, `Widgets` and `Tooling/Lint` all
  ask it rather than re-deriving it. The far side of the Bridge still cannot tell: it is the
  same `Publish` and the same `Dispatch`, on a name the designer typed.
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
- **`src/shared/Tooling/` is edit-mode code and runtime code never calls it.** `Lint` and
  `Vocab` are pure: they read `Constants`, `Selector`, `Presets`, `Widgets/Schemas` and an
  `Adapters` registry they build themselves, they return values instead of printing, and they
  edit nothing that a caller has not asked them to. They must **never** require
  `Widgets/init.luau` or `Elements/init.luau` — both reach for a running client at file scope,
  and the reader that matters here is a Studio plugin in a place where nothing has started.
  The arrow points one way: `Tooling` may require the runtime's pure layers, and no runtime
  file may require `Tooling`. The future `plugin/` follows the same rule one level up — its
  own Rojo project, built to a `.rbxm` and installed into Studio, and it is **never** mounted
  in `default.project.json`.
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

The precedence itself is one function: **`Selector.attributeIn(resolution, name)`** returns the
value and an `AttributeSource`, applying own > preset > nearest ancestor (that last layer only
for `Constants.Inheritable`; `UnrestPreset` skips the preset layer). Everything else is a
wrapper on it, so what the framework reports about an element and what a query matches on
cannot come apart.

A **`Selector.Resolution`** is the inputs that answer is derived from, gathered once:
`Selector.resolution(instance)` walks the ancestor chain a single time, records the nearest
provider of every inheritable name, and resolves the preset. Hold one only for the length of a
resolution — it is a snapshot of a tree that is about to change.

  * `Elements.resolve` gathers one and asks `attributeIn` for each of the nine keys, then hands
    it back so `Selector.groupIn` can fill `element.Group` out of the same snapshot.
  * `Selector.attributeOf(instance, name)` / `Selector.groupOf(instance)` / `Selector.presetFor`
    are the convenience doors: they gather a `Resolution`, ask once, and drop it. Right for one
    attribute, **wrong for nine** — a caller resolving a whole element must gather its own.

It builds on two helpers in the same module: `Selector.inheritedProviders(instance, names)`
(nearest ancestor per name) and the preset lookup folded into `Selector.resolution` (the preset
name, its bundle and where the name was typed — own beating inherited).

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
