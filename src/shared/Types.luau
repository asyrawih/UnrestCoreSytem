--!strict
--[[
                     ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
  _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
/==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
|==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
|==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
|==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
|==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
|==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
`-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`

    https://discord.gg/MZYTABSSfb
]]

--[[
    Unrest / Types

    The public type surface, in one place. It re-exports the adoption types so user code only
    ever requires this module.

        local Types = require(ReplicatedStorage.Unrest.Types)
        local descriptor: Types.Descriptor = { Tag = "Unrest", Selector = "TextButton" }

    Layer map:

        Core (Model)  ->  Bridge (Controller)  ->  Elements (adopted Studio UI)

    Core never touches an Instance. Adopted UI never touches a system. Everything crosses at
    the Bridge, which is a local bus and nothing more.

    NO GAME SHAPES LIVE HERE. `System` is the extension point and `Core:Register` is the
    door; a game exports the type of each system it writes from that system's own module,
    the same way it names its own commands. The framework is not supposed to know what a
    game's systems are called, so it does not carry their types.
]]

local AdapterTypes = require(script.Parent.Adapters.Types)
local Primitives = require(script.Parent.Primitives)
local Schemas = require(script.Parent.Widgets.Schemas)
-- Required for its type alone; selene cannot see a type-position use, hence the allow.
-- selene: allow(unused_variable)
local ScopeModule = require(script.Parent.Util.Scope)

--------------------------------------------------------------------------------
-- Re-exports
--------------------------------------------------------------------------------

export type RuntimeContext = Primitives.RuntimeContext
export type Cleanup = Primitives.Cleanup
export type Connection = Primitives.Connection
export type Destroyable = Primitives.Destroyable
export type Disconnectable = Primitives.Disconnectable
export type Signal<T...> = Primitives.Signal<T...>
export type Scope = Primitives.Scope
--[[
    Scythe's own surface, taken from the module rather than restated here. Retyping a library
    by hand is how the two drift: the copy is right the day it is written and silently wrong
    the first time the library gains an argument.
]]
export type ScopeLibrary = typeof(ScopeModule)

export type ElementHandler = AdapterTypes.ElementHandler
export type Handlers = AdapterTypes.Handlers
export type EventBinder = AdapterTypes.EventBinder
export type Adapter = AdapterTypes.Adapter
export type ResolvedAdapter = AdapterTypes.ResolvedAdapter
export type AdapterRegistry = AdapterTypes.AdapterRegistry
export type AttributeOrigin = AdapterTypes.AttributeOrigin
export type AttributeSource = AdapterTypes.AttributeSource
export type ManagedElement = AdapterTypes.ManagedElement
export type ElementManager = AdapterTypes.ElementManager
export type Descriptor<Role = string, Group = string> = AdapterTypes.Descriptor<Role, Group>
export type CompiledSelector = AdapterTypes.CompiledSelector
export type QueryHandle = AdapterTypes.QueryHandle

--------------------------------------------------------------------------------
-- Core: systems and registry
--------------------------------------------------------------------------------

--[[
    Lifecycle contract:
      1. every system's `Init(unrest)` runs, in dependency order;
      2. every system's `Start()` runs, in the same order;
      3. `Destroy()` runs in reverse order on shutdown.

    The teardown hook is `Destroy`, not `Stop`, so it never collides with a domain verb: a
    system's own `:Stop()` can mean whatever that system does, while `:Destroy()` always
    means the framework is retiring it.

    A system table must declare `Dependencies` even when empty (`{} :: { string }`) for the
    strict checker to match it structurally.
]]
export type System = {
    Name: string,
    Dependencies: { string }?,
    Init: ((self: any, unrest: Unrest) -> ())?,
    Start: ((self: any) -> ())?,
    Destroy: ((self: any) -> ())?,
}

export type Core = {
    SystemAdded: Signal<System>,
    Register: (self: Core, definition: System) -> System,
    Get: (self: Core, name: string) -> System?,
    --- Like `Get` but throws a message listing the registered systems.
    Expect: (self: Core, name: string) -> System,
    Has: (self: Core, name: string) -> boolean,
    --- Registered system names, in dependency order.
    List: (self: Core) -> { string },
    Start: (self: Core, unrest: Unrest) -> (),
    Stop: (self: Core) -> (),
    IsStarted: (self: Core) -> boolean,
}

--------------------------------------------------------------------------------
-- Bridge: the controller
--------------------------------------------------------------------------------

--- Receives whatever `Bridge:Dispatch` was given, and nothing else. There is no source
--- argument because every dispatch is local: the caller is on this side of the call stack.
export type CommandHandler = (payload: any) -> ()

--[[
    The only path between the code that owns state and adopted UI.

      * state -> UI : `Publish` / `Subscribe`, retained, so a late subscriber still gets the
                      current value and mount order stops mattering.
      * UI -> state : `Dispatch`, fire and forget, answered by whatever called `Handle`.

    A local bus. Nothing here crosses a machine boundary, and a command with no handler is a
    silent no-op rather than an error.
]]
export type Bridge = {
    Context: RuntimeContext,

    --- Publishes retained state: the value is kept and handed to every later subscriber.
    Publish: (self: Bridge, channel: string, value: any) -> (),
    Subscribe: (self: Bridge, channel: string, handler: (value: any) -> ()) -> Connection,
    --- Last published value on `channel`, or nil.
    Peek: (self: Bridge, channel: string) -> any,

    --- Sends an intent to every registered handler. Never yields.
    Dispatch: (self: Bridge, command: string, payload: any) -> (),
    --- Registers a handler for a command. Several may listen to the same name.
    Handle: (self: Bridge, command: string, handler: CommandHandler) -> Connection,

    Destroy: (self: Bridge) -> (),
}

--------------------------------------------------------------------------------
-- Widgets: several parts that only mean something together
--------------------------------------------------------------------------------

--- The instances of one widget, keyed by role. Optional roles may be absent.
export type WidgetParts = { [string]: Instance? }

--- What a widget is made of: see `Widgets/Schemas.luau`. Re-exported so game code needs one require.
export type WidgetSchema = Schemas.WidgetSchema
export type SchemaCheck = Schemas.SchemaCheck

--[[
    What `Unrest.Widgets:Each` needs to know.

    `Required` is the contract: a group is a widget only once every role listed here has been
    adopted, and it stops being one the moment any of them leaves. `Optional` roles are
    collected into the same table but never hold the call back -- one that arrives late simply
    appears in `parts`, which a handler holding the reference will see.

    `OnReady` is handed a cleanup scope. Put every connection the widget makes on it and the
    framework will undo them when the widget comes apart; a widget that is rebuilt then gets a
    fresh scope rather than a second set of live handlers on top of the first.

    `Role` is string by default, so `WidgetSpec` written without arguments means what it always
    meant. Game code holding a generated `Vocab` may narrow it -- `WidgetSpec<Vocab.Role>` --
    and have the checker reject a role name that no screen spells.
]]
export type WidgetSpec<Role = string> = {
    --- May be left empty when `Widget` names a registered schema; the schema's roles are used.
    Required: { Role }?,
    Optional: { Role }?,
    --[[
        When set, only groups whose root carries `UnrestWidget` equal to this name are
        accepted, and `Required` / `Optional` default to the schema registered under it.
        The root of a group is the nearest ancestor supplying its `UnrestGroup`, or the
        element itself when it sets its own.
    ]]
    Widget: string?,
    OnReady: (group: string, parts: WidgetParts, scope: Scope) -> (),
}

--- Stops one `Each`. Wired widgets are torn down; the shared query stays for the others.
export type WidgetHandle = {
    Destroy: (self: WidgetHandle) -> (),
    --- The parts of a group this recipe currently has wired, or nil when it is not complete.
    Get: (self: WidgetHandle, group: string) -> WidgetParts?,
    --- Groups this recipe currently has wired, sorted.
    Groups: (self: WidgetHandle) -> { string },
}

--- Which way a `Drag` measures. `Invert` makes the far end zero: a vertical slider almost
--- always wants `Axis = "Y", Invert = true` so the bottom is 0.
export type DragOptions = {
    Axis: ("X" | "Y")?,
    Invert: boolean?,
}

--- One group as `Widgets:Report()` sees it, whether or not it is wired.
export type WidgetGroupReport = {
    Group: string,
    --- The nearest provider of the group's `UnrestGroup`; nil when every part sets its own.
    Root: Instance?,
    --- `UnrestWidget` on the root, when there is one.
    Widget: string?,
    --- The recipe this entry belongs to: its `Widget` name, or "Each #N" for a plain one.
    Recipe: string,
    --- `UnrestChannel` resolved on the root: where a committed gesture is published, and
    --- where an idle control follows. Nil when the root declares none.
    Channel: string?,
    --- `UnrestCommand` resolved on the root: what a committed gesture dispatches.
    Command: string?,
    Present: { string },
    Missing: { string },
    Duplicates: { { Role: string, Kept: Instance, Ignored: Instance } },
    Live: boolean,
}

export type WidgetReport = {
    Groups: { WidgetGroupReport },
    --- Elements playing a role a recipe wants that could not join any group, and why.
    Orphans: { { Instance: Instance, Role: string, Reason: string } },
}

--------------------------------------------------------------------------------
-- Controls: the widgets the framework drives itself
--------------------------------------------------------------------------------

--[[
    One mounted control, from the outside.

    `Get` and `Set` are its value. `Set` paints and calls nothing back, because a value that
    came from the game is not something the player did; `Changed` is the other direction and
    fires for user gestures only. Neither of them ever fires at mount, which is what lets a
    rebuilt screen come back showing the value it had without announcing it as new.

    `Changed` and `Committed` are the two moments of one gesture, and a control that has both
    fires them in that order. `Changed` is "the player is moving this"; `Committed` is "the
    player has finished". Only the second is worth sending anywhere that costs something, and
    it is the moment the declarative wiring in `Widgets` publishes and dispatches on.
]]
export type ControlHandle = {
    Get: (self: ControlHandle) -> any,
    --- Paints without calling `OnChange` or firing `Changed`; for state that came from outside.
    Set: (self: ControlHandle, value: any) -> (),
    --- User gestures only, never an echo of `Set`.
    Changed: Signal<any>,
    --[[
        Fires once when a gesture settles, at the value settled on: a drag released, a switch
        pressed. Absent on a control with no gesture to settle -- a progress bar has neither.
        A control that leaves it nil is treated as settling the moment it changes.
    ]]
    Committed: Signal<any>?,
}

--[[
    A control the framework knows how to drive: a name, the schema that name means, and how to
    put one group of it on screen.

    `Mount` is handed the widget library rather than the whole singleton, and that is the
    point rather than an economy. A control paints and reports a gesture; the surest way to
    keep the framework from ever spelling a game's channel name is not to give it the bus.
    Everything a control legitimately needs -- `Drag`, `Drag2D` -- is on the library.

    It is called once per group per assembly, on a scope that dies with the widget, and must
    call `config` back for a gesture the player made and for nothing else.
]]
export type Control<Config> = {
    Name: string,
    Schema: WidgetSchema,
    Mount: (
        widgets: WidgetLibrary,
        group: string,
        parts: WidgetParts,
        scope: Scope,
        config: Config?
    ) -> ControlHandle,
}

--[[
    A control as the library holds one: `Control<Config>` with the config type erased, since
    `Use` is handed a table keyed by group and cannot know what is in it either.

    Written out rather than spelled `Control<any>`, and that is a Luau constraint rather than a
    preference. `Control<Config>` names `WidgetLibrary` and `WidgetLibrary` names this, so the
    two are mutually recursive -- and a recursive type may not be instantiated with a different
    parameter on the way round. Keep the two shapes in step by hand; they are five lines.
]]
export type AnyControl = {
    Name: string,
    Schema: WidgetSchema,
    Mount: (
        widgets: WidgetLibrary,
        group: string,
        parts: WidgetParts,
        scope: Scope,
        config: any
    ) -> ControlHandle,
}

--[[
    What `Widgets:Use` hands back. It is not a `WidgetHandle`: `Get` answers with the control
    driving a group rather than with the group's parts, and `Destroy` unmounts nothing.
]]
export type ControlUseHandle = {
    --- Drops the config this call supplied. The control stays mounted -- what a group plays
    --- is decided by `UnrestWidget` on its root, never by whether anybody asked for it.
    Destroy: (self: ControlUseHandle) -> (),
    --- The control driving `group` right now, or nil when nothing is.
    Get: (self: ControlUseHandle, group: string) -> ControlHandle?,
    --- Groups this control is currently driving, sorted.
    Groups: (self: ControlUseHandle) -> { string },
}

export type WidgetLibrary = {
    --- Calls `OnReady(group, parts, scope)` once per `UnrestGroup` whose required roles are all present.
    Each: (self: WidgetLibrary, spec: WidgetSpec) -> WidgetHandle,
    --[[
        Turns pressing `handle` into a stream of 0..1 positions along `track`, ending when the
        pointer is released anywhere on screen rather than only over the handle.

        `onMove` fires throughout the gesture; `onCommit` fires once, at the value the player
        settled on. Keep them apart when the two cost different amounts -- a volume slider
        wants every move because the player is listening, while a seek that reloads wants only
        the last one.

        Everything is parked on `scope`. The returned scope covers just the gesture in flight,
        for a caller that needs to cancel a drag without dismantling the widget.
    ]]
    Drag: (
        self: WidgetLibrary,
        scope: Scope,
        handle: Instance,
        track: Instance,
        onMove: (fraction: number) -> (),
        onCommit: ((fraction: number) -> ())?,
        options: DragOptions?
    ) -> Scope,
    --- `Drag` on both axes at once. Positions are `Vector2` fractions, 0..1 on each axis.
    Drag2D: (
        self: WidgetLibrary,
        scope: Scope,
        handle: Instance,
        track: Instance,
        onMove: (position: Vector2) -> (),
        onCommit: ((position: Vector2) -> ())?
    ) -> Scope,
    --[[
        Adds a control the library drives itself. Every group whose root carries
        `UnrestWidget` equal to `control.Name` and whose required roles are present is mounted
        on it, **whether or not anybody calls `Use`**: what a group plays is said in Studio.
        Registering a name twice replaces it, the same way `Schemas.Register` does.
    ]]
    --- Mounts the registered controls onto every declared root. `Unrest:Start` calls it on the client.
    Start: (self: WidgetLibrary) -> (),
    Register: (self: WidgetLibrary, control: AnyControl) -> (),
    --[[
        Supplies a registered control's config, keyed by `UnrestGroup`, and hands back a
        handle onto the controls it is driving. Calling it again replaces the config; groups
        already mounted are re-mounted onto it at the value they were left at.
    ]]
    Use: (self: WidgetLibrary, name: string, config: { [string]: any }?) -> ControlUseHandle,
    --[[
        Every group every recipe knows about, wired or not, and why the unwired ones are
        not. A report, not a warning: nothing here prints. The answer to "my widget never
        connected" without the four manual checks.
    ]]
    Report: (self: WidgetLibrary) -> WidgetReport,
    --- One sentence about one group, for the Output window and for tooling.
    Explain: (self: WidgetLibrary, group: string) -> string,
    Destroy: (self: WidgetLibrary) -> (),
}

--------------------------------------------------------------------------------
-- The singleton
--------------------------------------------------------------------------------

export type Unrest = {
    Version: string,
    Context: RuntimeContext,
    --- The CollectionService tag that opts a Studio-built instance into the framework.
    Tag: string,

    Core: Core,
    Bridge: Bridge,
    --- Per-ClassName knowledge about Roblox UI. Register your own for custom classes.
    Adapters: AdapterRegistry,
    --- Adopted Studio UI. Client-only; on the server it exists but adopts nothing.
    Elements: ElementManager,
    --[[
        Multi-part controls: sliders, toggles, anything whose parts only mean something
        together. Client-only, and the layer to reach for before writing a query by hand.
    ]]
    Widgets: WidgetLibrary,
    --[[
        The framework's cleanup library, re-exported so game code and framework code share one
        copy. Scopes are integer handles into module storage, so two copies of the module would
        mint handles that mean different things; requiring it from here can only ever be the
        same copy the framework uses.
    ]]
    Scope: ScopeLibrary,

    Start: (self: Unrest) -> Unrest,
    Stop: (self: Unrest) -> (),
    IsStarted: (self: Unrest) -> boolean,

    Register: (self: Unrest, definition: System) -> System,
    --- Throws if the system is not registered. Cast the result to its exported type.
    Get: (self: Unrest, name: string) -> System,

    --- Shorthand for `Unrest.Elements:Query`.
    Query: (self: Unrest, descriptor: Descriptor, handlers: Handlers?) -> QueryHandle,
    --- Shorthand for `Unrest.Bridge:Dispatch`.
    Dispatch: (self: Unrest, command: string, payload: any) -> (),
}

-- Type-only module: the returned table is intentionally empty.
return table.freeze({})
