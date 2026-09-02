--!strict
--[[
    Unrest / Types

    The public type surface, in one place. It re-exports the adoption types and the net
    types so user code only ever requires this module.

        local Types = require(ReplicatedStorage.Unrest.Types)
        local descriptor: Types.Descriptor = { Tag = "Unrest", Selector = "TextButton" }

    Layer map:

        Core (Model)  ->  Bridge (Controller)  ->  Elements (adopted Studio UI)
                              |
                              +-- Net: the same Bridge, across the client/server line

    Core never touches an Instance. Adopted UI never touches a system. Everything crosses
    at the Bridge, and the Bridge asks the contracts what is allowed.

    NO GAME SHAPES LIVE HERE. `System` is the extension point and `Core:Register` is the
    door; a game exports the type of each system it writes from that system's own module,
    the same way it names its own commands. The framework is not supposed to know what a
    game's systems are called, so it does not carry their types.
]]

local AdapterTypes = require(script.Parent.Adapters.Types)
local NetTypes = require(script.Parent.Net.Types)
local Primitives = require(script.Parent.Primitives)
local Transport = require(script.Parent.Net.Transport)

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

export type ArgumentKind = NetTypes.ArgumentKind
export type ArgumentSpec = NetTypes.ArgumentSpec
export type RateLimitSpec = NetTypes.RateLimitSpec
export type CommandSource = NetTypes.CommandSource
export type CommandHandler = NetTypes.CommandHandler
export type CommandContract = NetTypes.CommandContract
export type ChannelVisibility = NetTypes.ChannelVisibility
export type ChannelContract = NetTypes.ChannelContract
export type ChannelDeclaration = NetTypes.ChannelDeclaration
export type Contracts = NetTypes.Contracts
export type RejectionReason = NetTypes.RejectionReason
export type Rejection = NetTypes.Rejection
export type InvokeResult = NetTypes.InvokeResult
export type NetServer = NetTypes.NetServer
export type NetClient = NetTypes.NetClient

--- The replaceable half of the net layer. A game implements these to put the framework on a
--- wire of its own; the framework implements the default over Roblox remotes.
export type ServerTransport = Transport.ServerTransport
export type ClientTransport = Transport.ClientTransport
export type TransportProvider = Transport.TransportProvider
export type RequestHandler = Transport.RequestHandler
export type PublishHandler = Transport.PublishHandler
export type RefusalReporter = Transport.RefusalReporter

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
-- Bridge: the controller, and the network boundary
--------------------------------------------------------------------------------

--[[
    The only path between Core and adopted UI, and the only path across the network.

      * Core -> UI  : `Publish` / `Subscribe`, retained, so a late subscriber still gets
                      the current value and mount order stops mattering.
      * UI   -> Core: `Dispatch` (fire and forget) and `Invoke` (request/response).
      * Handlers    : `Handle` on the owning realm.

    Whether a dispatch stays local or crosses the wire is decided by the command's
    contract, not by the caller. Client code writes the same line either way.
]]
export type Bridge = {
    Context: RuntimeContext,
    Contracts: Contracts,
    --- Fires when a request is refused, on whichever side refused it.
    Rejected: Signal<Rejection>,

    --[[
        Publishes retained state. On the server the channel's `Visibility` decides who sees
        it: `Server` stays local, `Player` needs `target`, `Public` goes to everyone.
    ]]
    Publish: (self: Bridge, channel: string, value: any, target: Player?) -> (),
    Subscribe: (self: Bridge, channel: string, handler: (value: any) -> ()) -> Connection,
    --- Last published value on `channel`, or nil.
    Peek: (self: Bridge, channel: string) -> any,

    --- Sends an intent. Local or remote per the contract. Never yields.
    Dispatch: (self: Bridge, command: string, payload: any) -> (),
    --- Sends an intent and waits for the handler's value. Yields. Contract must allow it.
    Invoke: (self: Bridge, command: string, payload: any) -> InvokeResult,
    --- Registers the handler for a command, on the realm that owns it.
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
    --[[
        Replaces the default remotes transport, for every command and every channel. Must be
        called between `require` and `:Start()`: the client half is attached at require time
        but does not build its transport until the first of `:Start()` or the first dispatch,
        and installing one after that throws rather than splitting the traffic in two.
    ]]
    UseTransport: (self: Unrest, provider: TransportProvider) -> Unrest,
    IsStarted: (self: Unrest) -> boolean,

    Register: (self: Unrest, definition: System) -> System,
    --- Throws if the system is not registered. Cast the result to its exported type.
    Get: (self: Unrest, name: string) -> System,

    --- Shorthand for `Unrest.Elements:Query`.
    Query: (self: Unrest, descriptor: Descriptor, handlers: Handlers?) -> QueryHandle,
    --- Shorthand for `Unrest.Bridge:Dispatch`.
    Dispatch: (self: Unrest, command: string, payload: any) -> (),
    --- Shorthand for `Unrest.Bridge:Invoke`.
    Invoke: (self: Unrest, command: string, payload: any) -> InvokeResult,
}

-- Type-only module: the returned table is intentionally empty.
return table.freeze({})
