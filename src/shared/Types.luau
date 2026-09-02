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

--------------------------------------------------------------------------------
-- Re-exports
--------------------------------------------------------------------------------

export type RuntimeContext = Primitives.RuntimeContext
export type Cleanup = Primitives.Cleanup
export type Connection = Primitives.Connection
export type Destroyable = Primitives.Destroyable
export type Disconnectable = Primitives.Disconnectable
export type MaidTask = Primitives.MaidTask
export type Maid = Primitives.Maid
export type Signal<T...> = Primitives.Signal<T...>

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
