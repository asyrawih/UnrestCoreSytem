--!strict
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
export type Descriptor = AdapterTypes.Descriptor
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

--[[
    What `Unrest.Widgets:Each` needs to know.

    `Required` is the contract: a group is a widget only once every role listed here has been
    adopted, and it stops being one the moment any of them leaves. `Optional` roles are
    collected into the same table but never hold the call back -- one that arrives late simply
    appears in `parts`, which a handler holding the reference will see.

    `OnReady` is handed a cleanup scope. Put every connection the widget makes on it and the
    framework will undo them when the widget comes apart; a widget that is rebuilt then gets a
    fresh scope rather than a second set of live handlers on top of the first.
]]
export type WidgetSpec = {
    Required: { string },
    Optional: { string }?,
    OnReady: (group: string, parts: WidgetParts, scope: Scope) -> (),
}

--- Stops one `Each`. Wired widgets are torn down; the shared query stays for the others.
export type WidgetHandle = {
    Destroy: (self: WidgetHandle) -> (),
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
        onCommit: ((fraction: number) -> ())?
    ) -> Scope,
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
