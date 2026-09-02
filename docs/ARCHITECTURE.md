# UnrestCoreSystem — Architecture

> Model · View · Controller for Roblox, with a jQuery-shaped selector engine in the middle.

```
        Core System                Bridge                    Dynamic UI
     ┌──────────────────┐   ┌──────────────────┐        ┌──────────────────┐
     │  MusicSystem     │   │                  │        │                  │
     │  AvatarContext   │──▶│   Publish/Peek   │───────▶│   ( DxChips X )  │◀── 🖱
     │  DanceSystem     │◀──│   Dispatch       │        │                  │
     │  PluginExtended  │   │   Query ─────────┼──┐     └──────────────────┘
     └──────────────────┘   └──────────────────┘  │              ▲
        Model                  Controller         │              │
                                                  └──────────────┘
     Unrest              Typed Check Lua              CollectionService
     Core                Lua Resolver                 (live tag binding)
     Bridge
```

The three columns of the whiteboard map one-to-one onto the source tree:

| Board column | Layer | Source |
| --- | --- | --- |
| Core System | Model — state and rules | `src/shared/Core/` |
| Bridge | Controller — the only seam | `src/shared/Bridge/` |
| Dynamic UI | View — Instances and components | `src/shared/UI/` |

---

## 1. Layer contract

The rule is one sentence: **Core never touches an Instance, UI never touches a system, and
everything crosses at the Bridge.**

| Module | May require | May **not** require |
| --- | --- | --- |
| `Types`, `Constants` | nothing | anything (they are leaves, by design) |
| `Bridge/*` | `Types`, `Constants`, sibling Bridge modules | `Core/*`, `UI/*` |
| `Core/*` | `Types`, `Constants`, `Bridge/Signal`, `Bridge/Maid`, `Bridge/Resolver` | `UI/*`, another system's module file |
| `UI/*` | `Types`, `Constants`, `Bridge/Signal`, `Bridge/Maid`, `Bridge/Resolver` | `Core/*` |
| `init.luau` (root) | everything | — it is the composition root |
| `src/server`, `src/client` | `ReplicatedStorage.Unrest` only | any internal module directly |

Two consequences worth stating explicitly:

- **A system reaches another system through `unrest:Get(name)`, never through `require`.**
  That is what makes the dependency graph declarative (`Dependencies = { "AvatarContext" }`)
  and what lets a plugin substitute a system the framework has never heard of.
- **A component is handed the Bridge and nothing else.** `Component.Create(props, bridge)`
  has no third parameter, so "the UI accidentally called into Core" is not a mistake that
  can be made — it is a signature that does not exist.

`Signal`, `Maid` and `Resolver` live under `Bridge/` because the Bridge owns them, but they
are dependency-free primitives that any layer may use. Nothing in the framework depends on
an external package; `Packages/` is empty on purpose.

The Bridge is **process-local**. It does not replicate. A networked feature belongs behind a
system that owns its own RemoteEvents, not behind the Bridge.

---

## 2. `Unrest:Query` — the selector engine

### 2.1 Descriptor

```luau
Unrest:Query(descriptor: Descriptor, handlers: Handlers?) -> QueryHandle
```

| Field | Type | Meaning |
| --- | --- | --- |
| `Tag` | `string?` | CollectionService tag. Drives **live** binding via `GetInstanceAddedSignal` / `GetInstanceRemovedSignal`. |
| `Selector` | `string?` | ClassName tested with `:IsA()` — the board's `is:A("Button")`. Accepts abstract classes (`"GuiButton"`, `"GuiObject"`). |
| `Name` | `string?` | Exact `Instance.Name`. Re-evaluated live when an element is renamed. |
| `Ancestor` | `Instance?` | Search root. **Required when there is no `Tag`.** |
| `Recursive` | `boolean?` | Search descendants of `Ancestor` rather than only its children. Defaults to `true`. |

Rules enforced by the Resolver at call time:

- at least one of `Tag` / `Selector` / `Name` must be present;
- a descriptor without a `Tag` must supply an `Ancestor` (a tagless, rootless query would
  have to walk the whole DataModel);
- `Tag` and `Selector` must be non-empty.

`Tag` and `Ancestor` compose: `{ Tag = "Unrest", Ancestor = playerGui }` matches tagged
elements *inside* that screen only.

### 2.2 Handlers

| Key | Signature | Bound to |
| --- | --- | --- |
| `Active` | `(element: Instance) -> ()` | `GuiButton.Activated`, `ClickDetector.MouseClick`, `ProximityPrompt.Triggered` |
| `Hover` | `(element: Instance) -> ()` | `GuiObject.MouseEnter`, `ClickDetector.MouseHoverEnter` |
| `Unhover` | `(element: Instance) -> ()` | `GuiObject.MouseLeave`, `ClickDetector.MouseHoverLeave` |
| `Added` | `(element: Instance) -> ()` | fired when an instance **starts** matching the descriptor |
| `Removed` | `(element: Instance) -> ()` | fired when an instance **stops** matching (untagged, renamed, destroyed, or the query itself was destroyed) |

Any other key is an error, and so is a key of the wrong type. Nothing is silently ignored.

### 2.3 The handle

| Method | Returns | Notes |
| --- | --- | --- |
| `:Elements()` | `{ Instance }` | snapshot copy — safe to mutate |
| `:Count()` | `number` | |
| `:Each(visitor)` | `QueryHandle` | chainable; iterates a snapshot |
| `:Bind(handlers)` | `QueryHandle` | merges handlers in and **rebuilds** every element's connections, so replacing `Active` never leaves the old one attached |
| `:Destroy()` | `()` | releases every connection and fires `Removed` for each current element |

Plus two signals for programmatic use: `handle.ElementAdded` and `handle.ElementRemoved`,
both `Signal<Instance>`.

### 2.4 Live binding — why this is not a scan

The arrow into `CollectionService` on the whiteboard is the whole point. A query keeps two
sets:

- **watched** — every candidate the source can produce. Each watched instance carries a small
  maid holding a `Destroying` connection and, when the descriptor filters on `Name`, a
  `GetPropertyChangedSignal("Name")` connection.
- **bound** — the subset that currently matches, each with a maid holding the handler
  connections.

So an instance may join and leave the result set any number of times over its life. Creating
a query *before* the UI exists is the normal case, and `src/client/init.client.luau`
deliberately does exactly that.

### 2.5 The Resolver ("Typed Check Lua Resolver")

Luau's type checker only protects callers that are themselves typed. Descriptors and handler
tables are the public boundary, so every one is *also* checked at runtime. Errors name the
offending key, state what was expected, show what arrived, and suggest a fix — including a
Levenshtein "did you mean" for near-miss key names:

```
[Unrest.Resolver] unknown Query descriptor field "Selecter". Did you mean "Selector"?
Valid fields: Ancestor, Name, Recursive, Selector, Tag.

[Unrest.Resolver] Query handler field "Active" expects a function (Activated / MouseClick /
Triggered, e.g. Active = function(element) end) but got string ("toggle").

[Unrest.Query] handler "Active" cannot bind to game.Players.You.PlayerGui.Menu.Panel: a Frame
is not a GuiButton, ClickDetector or ProximityPrompt. Narrow the query {Tag = "Unrest",
is:A("Frame")} with Selector = "TextButton" (or drop the Active handler).
```

The same resolver validates system definitions (`Resolver.System`, which permits unknown
keys because a system carries its own state) and component definitions
(`Resolver.Component`).

---

## 3. System lifecycle

```
Register  ──▶  topological sort by Dependencies  ──▶  Init(unrest) for all
                                                 ──▶  Start()      for all
                                                 ──▶  Destroy()    in reverse, on Stop
```

| Hook | Signature | Contract |
| --- | --- | --- |
| `Name` | `string` | the registry key; must be unique |
| `Dependencies` | `{ string }?` | system names; drives the ordering |
| `Init` | `(self, unrest) -> ()` | grab references, subscribe to Bridge commands. **Do not** call another system's behaviour yet. |
| `Start` | `(self) -> ()` | begin work; every system has been initialised |
| `Destroy` | `(self) -> ()` | release everything |

Two passes matter: after the `Init` pass every system exists and holds its references, so a
`Start` may freely use any other system. The teardown hook is named `Destroy`, not `Stop`,
precisely so it never collides with a domain verb — `MusicSystem:Stop()` stops the music.

**Registering after `:Start()` is legal** and is how `PluginExtended` works: the new system
is initialised and started immediately, and its dependencies must already be running. A
dependency cycle, or a dependency that was never registered, throws with the offending chain
printed.

---

## 4. Adding a Core system

1. Create `src/shared/Core/Systems/MySystem.luau`:

```luau
--!strict
local Types = require(script.Parent.Parent.Parent.Types)
local Maid = require(script.Parent.Parent.Parent.Bridge.Maid)

local MySystem = {
    Name = "MySystem",
    Dependencies = { "AvatarContext" },
    _bridge = nil :: Types.Bridge?,
    _maid = Maid.new(),
}

function MySystem:DoTheThing(): () end

function MySystem:Init(unrest: Types.Unrest): ()
    self._bridge = unrest.Bridge
    self._maid:Add(unrest.Bridge:OnCommand("MySystem.Go", function(payload: any)
        self:DoTheThing()
    end))
end

function MySystem:Start(): ()
    local bridge = self._bridge
    if bridge then
        bridge:Publish("MySystem.State", "ready")
    end
end

function MySystem:Destroy(): ()
    self._maid:Destroy()
end

return MySystem
```

2. Export its shape from `src/shared/Types.luau` so consumers get autocomplete:

```luau
export type MySystem = System & {
    DoTheThing: (self: MySystem) -> (),
}
```

3. Register it in `src/shared/init.luau` next to the other built-ins
   (`core:Register(MySystem)`), or — if it is not part of the framework — register it at
   runtime through `PluginExtended`.

Three details the built-ins all follow and the type checker enforces:

- declare `Dependencies` even when empty (`Dependencies = {} :: { string }`), otherwise the
  table does not structurally match `Types.System`;
- declare every state field in the initial table literal with an explicit type
  (`_sound = nil :: Sound?`) so `self` is typed inside every method;
- define a method **before** the method that calls it — `self`'s type grows as the file goes.

### Plugins

```luau
local plugins = unrest:Get("PluginExtended") :: Types.PluginExtended

plugins:Register({
    Name = "GreeterSystem",
    Dependencies = { "AvatarContext" },
    Init = function(self: any, framework: Types.Unrest) end,
    Start = function(self: any) end,
})

plugins:LoadFromFolder(ServerScriptService.MyPlugins) -- requires every ModuleScript child
```

`LoadFromFolder` reports a broken plugin by full name and skips it: one bad module must not
take the game down.

---

## 5. Adding a UI component

A component signs a two-field contract: `Name`, and `Create(props, bridge) -> ComponentHandle`.
`src/shared/UI/Components/DxChipsX.luau` is the reference implementation — copy its shape.

```luau
--!strict
local Types = require(script.Parent.Parent.Parent.Types)
local Maid = require(script.Parent.Parent.Parent.Bridge.Maid)
local Signal = require(script.Parent.Parent.Parent.Bridge.Signal)

local MyThing = { Name = "MyThing" }

function MyThing.Create(props: Types.Props, bridge: Types.Bridge): Types.ComponentHandle
    local maid = Maid.new()
    local destroyedSignal: Types.Signal<Types.ComponentHandle> = Signal.new("MyThing.Destroyed")
    maid:Add(destroyedSignal)

    local root = Instance.new("Frame")
    maid:Add(root)

    local handle = { Name = "MyThing", Instance = root, Props = props, Destroyed = destroyedSignal }
    local typed = (handle :: any) :: Types.ComponentHandle

    function handle:Update(patch: Types.Props): Types.ComponentHandle
        return typed
    end

    function handle:Destroy(): ()
        destroyedSignal:Fire(typed)
        maid:Destroy()
    end

    return typed
end

return MyThing
```

Then `ui:Register(MyThing)` in `src/shared/init.luau`, and mount it with
`Unrest:Mount("MyThing", props, parent)`.

House rules:

- **one maid owns everything** — Instances and connections alike — so `:Destroy()` is one line;
- **`:Update` is an idempotent repaint**, not a diff. Merge props, then paint from scratch;
- **interaction leaves through the Bridge** (`bridge:Dispatch(...)`); the optional
  `OnActivated`-style prop callbacks are a convenience on top, never the only path;
- **tag the root only.** `DxChipsX` tags its root `TextButton` but *not* its dismiss button,
  so `{ Tag = "Unrest", Selector = "TextButton" }` returns exactly one element per chip;
- add typed props to `Types.luau` (see `ChipProps`) so callers get autocomplete.

---

## 6. Bridge reference

| Direction | Method | Semantics |
| --- | --- | --- |
| Core → UI | `Bridge:Publish(channel, value)` | **retained**: the value is remembered |
| Core → UI | `Bridge:Subscribe(channel, handler)` | a late subscriber immediately receives the retained value, then every update |
| Core → UI | `Bridge:Peek(channel)` | synchronous read, or `nil` |
| UI → Core | `Bridge:Dispatch(command, payload)` | fire-and-forget intent; no return value |
| UI → Core | `Bridge:OnCommand(command, handler)` | |
| either | `Bridge:Query(descriptor, handlers)` | live selector engine |

Retention is what makes mount order irrelevant: a chip that mounts after the music started
still renders the right track, without polling and without a race.

Channel and command names live in `src/shared/Constants.luau` so a typo is a nil index
rather than a silent no-op:

| Constant | Value |
| --- | --- |
| `Channels.NowPlaying` | `"Music.NowPlaying"` |
| `Channels.MusicVolume` | `"Music.Volume"` |
| `Channels.Character` | `"Avatar.Character"` |
| `Channels.Dance` | `"Dance.Current"` |
| `Channels.Plugins` | `"Plugin.Registered"` |
| `Commands.MusicPlay` / `MusicStop` | `"Music.Play"` / `"Music.Stop"` |
| `Commands.DancePlay` / `DanceStop` | `"Dance.Play"` / `"Dance.Stop"` |
| `Commands.ChipActivated` / `ChipRemoved` | `"Chip.Activated"` / `"Chip.Removed"` |

---

## 7. Canonical usage

The whiteboard sketch, cleaned up into valid Luau:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Unrest.Types)
local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

--  Unrest:Query({ Tag = Unrest, Selector = Button, Name = "ToggleMenu" }, Active=, hover)
--  is:A("Button")
local menu = unrest:Query({
    Tag = "Unrest",
    Selector = "TextButton", -- is:A("TextButton")
    Name = "ToggleMenu",
}, {
    Active = function(element: Instance)
        unrest.Bridge:Dispatch("Music.Play", "Lobby")
    end,

    Hover = function(element: Instance)
        print(`hovering {element.Name}`)
    end,
})

-- Mounted after the query, and matched anyway: the binding is live.
local chip = unrest:Mount("DxChipsX", {
    Name = "ToggleMenu",
    Text = "Toggle Menu",
    Selected = true,
} :: Types.ChipProps, screenGui)

print(menu:Count()) --> 1

-- Systems are reached by name and cast to their exported type.
local music = unrest:Get("MusicSystem") :: Types.MusicSystem
music:SetVolume(0.4)
```

### Public API surface

```luau
Unrest.Version : string                                   -- "0.1.0"
Unrest.Context : "Server" | "Client"
Unrest.Tag     : string                                   -- "Unrest"
Unrest.Core    : Core
Unrest.Bridge  : Bridge
Unrest.UI      : UI

Unrest:Start()                                            -> Unrest
Unrest:Stop()                                             -> ()
Unrest:IsStarted()                                        -> boolean
Unrest:Register(definition: System)                       -> System
Unrest:Get(name: string)                                  -> System
Unrest:Query(descriptor: Descriptor, handlers: Handlers?) -> QueryHandle
Unrest:Mount(component: string, props: Props, parent: Instance) -> ComponentHandle
```

---

## 8. File map

```
src/shared/init.luau                        the Unrest singleton (composition root)
src/shared/Types.luau                       every public type; zero requires
src/shared/Constants.luau                   tag, version, channel and command names

src/shared/Core/init.luau                   system registry: register, topo-sort, lifecycle
src/shared/Core/Systems/MusicSystem.luau    named tracks, one Sound, Bridge-driven
src/shared/Core/Systems/AvatarContext.luau  who is here, and what body they wear
src/shared/Core/Systems/DanceSystem.luau    named emotes; depends on AvatarContext
src/shared/Core/Systems/PluginExtended.luau runtime registration of third-party systems

src/shared/Bridge/init.luau                 retained channels, commands, query ownership
src/shared/Bridge/Query.luau                live selector engine + CollectionService binding
src/shared/Bridge/Selector.luau             descriptor compilation and the match predicate
src/shared/Bridge/Resolver.luau             runtime schema validation + "did you mean"
src/shared/Bridge/Signal.luau               dependency-free signal
src/shared/Bridge/Maid.luau                 ordered, keyed cleanup

src/shared/UI/init.luau                     component registry + mounter
src/shared/UI/Components/DxChipsX.luau      the purple chip; reference component

src/client/init.client.luau                 client bootstrap + the worked example
src/server/init.server.luau                 server bootstrap + a runtime-registered plugin
```

---

## 9. Design decisions where the board was ambiguous

| Board said | Decision |
| --- | --- |
| `Selector = Button` | `Button` is not a Roblox class. `Selector` is any ClassName passed to `:IsA()`, so `"TextButton"`, `"ImageButton"` and the abstract `"GuiButton"` all work. |
| `Active=, hover` | Handlers became `Active`, `Hover`, `Unhover`, `Added`, `Removed` — the smallest set that covers pointer interaction plus set membership. Every other key is an error. |
| Arrow into `CollectionService` | Read as *live* binding, not a one-shot scan: added/removed tag signals, plus rename tracking when the descriptor filters on `Name`. |
| `Dance & System` (drawn twice) | Treated as one `DanceSystem`; the duplicate is read as "and more like it", which `PluginExtended` provides. |
| `Plugin Extended` | A system whose job is registering *other* systems at runtime, using the identical `Types.System` contract. |
| `DxChips X` + cursor | A concrete, interactive component (a dismissible chip) built as the reference implementation of the component contract. |
| `Unrest / Core / Bridge` stacked | Read as the module path `ReplicatedStorage.Unrest` → `Core` → `Bridge`, i.e. the layer stack, which is exactly the folder layout. |
| A single Bridge arrow, Core→UI | Made bidirectional but asymmetric: state flows out (retained `Publish`), intent flows back (`Dispatch`). One arrow would have forced UI to call Core directly. |
| — | The system teardown hook is `Destroy`, not `Stop`, so it never collides with domain verbs like `MusicSystem:Stop()`. |
| — | The Bridge is process-local; nothing here replicates. Networking belongs inside a system that owns its RemoteEvents. |
