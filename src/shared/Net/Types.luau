--!strict
--[[
    Unrest / Net / Types

    Types for the client/server boundary.

    The whole security posture of the framework is one idea: a command is not reachable
    from a client unless its contract says so, and the server decides that by reading the
    contract, never by reading the message. Nothing a client sends can widen its own
    permissions, because the permission was never in the message.

    Contracts live in ReplicatedStorage on purpose. They are public knowledge -- a list of
    door names and which ones have a handle on the outside. The locks are on the server.

    The framework declares no commands and no channels of its own. These types are the
    vocabulary; the names are the game's, registered through `Contracts:Declare`.

    Owned by the net layer. Additive changes are fine; do not rename what is here.
]]

local Primitives = require(script.Parent.Parent.Primitives)

type Signal<T...> = Primitives.Signal<T...>
type RuntimeContext = Primitives.RuntimeContext

--------------------------------------------------------------------------------
-- Argument schemas
--------------------------------------------------------------------------------

--- What a payload value is allowed to be. Deliberately narrow: no Instance, no function,
--- no userdata beyond the listed value types, because none of those can be trusted or
--- cheaply bounded when they arrive from a client.
export type ArgumentKind =
    "string"
    | "number"
    | "integer"
    | "boolean"
    | "nil"
    | "table"
    | "Vector3"
    | "Color3"
    | "EnumItem"

export type ArgumentSpec = {
    Kind: ArgumentKind,
    --- Accepts nil in addition to `Kind`.
    Optional: boolean?,
    --- Strings: maximum length, capped again by `Constants.Limits.MaxStringLength`.
    MaxLength: number?,
    --- Strings: must match this Lua pattern in full.
    Pattern: string?,
    --- Numbers: inclusive bounds. Non-finite numbers are always rejected.
    Min: number?,
    Max: number?,
    --- Any kind: the value must be one of these.
    OneOf: { any }?,
    --- Tables: schema applied to every entry.
    Of: ArgumentSpec?,
    --- Tables: schema applied per named field.
    Fields: { [string]: ArgumentSpec }?,
}

--------------------------------------------------------------------------------
-- Command contracts
--------------------------------------------------------------------------------

export type RateLimitSpec = {
    --- Calls allowed per player, per `Window` seconds.
    Count: number,
    Window: number,
}

--- Who called, decided by the transport and never by the payload.
export type CommandSource = {
    --- The caller. Non-nil only for a request that actually crossed the network, where
    --- Roblox itself supplies the player; nil for a local dispatch.
    Player: Player?,
    --- Where the dispatch originated.
    Context: RuntimeContext,
    --- True when this arrived over a remote. Handlers that mutate authoritative state
    --- should branch on this, not on the payload.
    Remote: boolean,
}

export type CommandHandler = (source: CommandSource, payload: any) -> any

export type CommandContract = {
    Name: string,
    --- Where the handler runs. A "Server" command dispatched on a client is forwarded;
    --- a "Client" command never leaves the client.
    Realm: RuntimeContext,
    --[[
        Whether a client may ask for this command at all. Absent or false means the command
        is unreachable from any client: the client-side guard refuses to send it, and the
        server refuses it again on arrival. Deny by default is the point -- and a registry
        nobody has declared into denies everything, which is why an empty one is safe.
    ]]
    AllowClient: boolean?,
    --- Schema for the payload. A command with no `Payload` accepts only nil.
    Payload: ArgumentSpec?,
    --- Per-player budget. Falls back to `Constants.Limits.Default*` when absent.
    RateLimit: RateLimitSpec?,
    --[[
        Last gate before the handler, and the only one that can see game state. Runs on the
        server after schema and rate checks pass. Return false plus a reason to refuse --
        the reason is logged server-side and never sent to the client, so a probing client
        learns nothing about why it failed.
    ]]
    Authorize: ((player: Player, payload: any) -> (boolean, string?))?,
    --- Whether `Bridge:Invoke` may be used, i.e. the caller gets a value back.
    Response: boolean?,
    --- One line on what the command does, surfaced in error messages and docs.
    Description: string?,
    --[[
        THE TRANSPORT'S FIELD, AND THE FRAMEWORK NEVER READS IT.

        Whatever the installed transport needs to put this command on its wire -- a ByteNet
        packet, a codec, an id -- declared on the same line as the policy that governs it, so
        a mismatch between the two is visible while reading rather than at runtime. The
        framework carries it verbatim: `Declare` does not validate it, no gate consults it,
        and the default remotes transport ignores it entirely.

        It is `any` on purpose. Typing it would be the framework having an opinion about a
        library it must never depend on.
    ]]
    Wire: any?,
}

--------------------------------------------------------------------------------
-- Channel contracts
--------------------------------------------------------------------------------

--[[
    How far a published value is allowed to travel.
      * Server  -- never leaves the server. The default, so a new channel cannot leak.
      * Player  -- replicated to one named player only.
      * Public  -- replicated to every client.
]]
export type ChannelVisibility = "Server" | "Player" | "Public"

export type ChannelContract = {
    Name: string,
    Visibility: ChannelVisibility,
    --- Schema the published value must satisfy before it is allowed to replicate.
    Value: ArgumentSpec?,
    Description: string?,
    --- The transport's, exactly as on a command contract: carried, never read.
    Wire: any?,
}

--[[
    A channel as a game writes it: `Visibility` may be omitted, and omitting it means
    `Server`. The declaration type exists so the safe default is the *shortest* thing to
    type; `Contracts:DeclareChannel` applies it and hands back a full `ChannelContract`.
]]
export type ChannelDeclaration = {
    Name: string,
    Visibility: ChannelVisibility?,
    Value: ArgumentSpec?,
    Description: string?,
    Wire: any?,
}

--[[
    The registry, not a table of contracts. The framework declares nothing; a game declares
    its whole command and channel surface through `Declare` and `DeclareChannel` before it
    starts the framework, and both realms read the result through the accessors below.

    `Commands` and `Channels` are the live registries. They grow as declarations land, so
    they are the right thing to iterate for tooling and the wrong thing to hold a reference
    into and assume complete.
]]
export type Contracts = {
    Commands: { [string]: CommandContract },
    Channels: { [string]: ChannelContract },
    --[[
        Registers a command and returns the frozen contract. Throws on a malformed contract,
        on `AllowClient`/`Authorize` outside the server realm, and on a name already
        declared -- a command has exactly one contract, and quietly merging two is how a
        `Realm` goes missing.
    ]]
    Declare: (self: Contracts, contract: CommandContract) -> CommandContract,
    --- Registers a channel, applying the `Server` default for a missing `Visibility`.
    DeclareChannel: (self: Contracts, declaration: ChannelDeclaration) -> ChannelContract,
    --- Declared command names, sorted. What error messages list.
    List: (self: Contracts) -> { string },
    --- Contract for `name`, or nil when the command was never declared.
    GetCommand: (self: Contracts, name: string) -> CommandContract?,
    --- Like `GetCommand` but throws with the list of declared commands.
    ExpectCommand: (self: Contracts, name: string) -> CommandContract,
    GetChannel: (self: Contracts, name: string) -> ChannelContract?,
    --- Whether a client may request `name`. The single question both sides ask.
    IsClientCallable: (self: Contracts, name: string) -> boolean,
}

--------------------------------------------------------------------------------
-- Transport
--------------------------------------------------------------------------------

export type RejectionReason =
    "UnknownCommand"
    | "NotClientCallable"
    | "WrongRealm"
    | "BadPayload"
    | "RateLimited"
    | "Unauthorized"
    | "HandlerError"
    | "NoHandler"
    | "Timeout"
    --- `Invoke` was used on a command whose contract does not declare `Response = true`.
    | "ResponseNotAllowed"

export type Rejection = {
    Command: string,
    Reason: RejectionReason,
    --- Developer-facing detail. Logged on the server; never replicated to a client.
    Detail: string,
    Player: Player?,
}

--- What `Bridge:Invoke` hands back.
export type InvokeResult = {
    Ok: boolean,
    Value: any,
    --- Coarse reason on failure. Intentionally not the server's `Detail`.
    Reason: RejectionReason?,
}

--------------------------------------------------------------------------------
-- The wire, and the seam the Bridge offers its realm's gateway
--------------------------------------------------------------------------------

--[[
    The three replicated objects, and all of them. One choke point per direction beats a
    remote per feature: there is exactly one place where a request is checked, so a new
    feature adds a contract rather than an attack surface.

      * `Dispatch` and `Invoke` are client -> server ONLY.
      * `Publish` is server -> client ONLY.

    There is deliberately no server -> client *function*. `RemoteFunction:InvokeClient` hands
    a thread of the server's to a machine the server does not control, with no timeout to
    set on it; a client that simply never returns stalls that thread forever.
]]
export type Remotes = {
    Dispatch: RemoteEvent,
    Invoke: RemoteFunction,
    Publish: RemoteEvent,
}

--[[
    What a realm's gateway offers the Bridge. Both fields are optional because neither realm
    has both halves, and saying so in the type is better than a method that exists in order
    to refuse:

      * the client gateway can `Send` (it is the only side that may ask) and cannot `Publish`
        (a client is never the author of state another player can see);
      * the server gateway can `Publish` and cannot `Send` (the server never asks a client
        to do anything -- compliance could not be verified, so it is not a mechanism).
]]
export type NetGateway = {
    Send: ((self: NetGateway, command: string, payload: any, wantsResponse: boolean) -> InvokeResult)?,
    Publish: ((self: NetGateway, channel: string, value: any, target: Player?) -> ())?,
}

--[[
    The Bridge's network-facing seam. The Bridge implements this *in addition to*
    `Types.Bridge`; a gateway casts to it to reach the parts user code has no business
    calling. Keeping them off `Types.Bridge` is the point: `Execute` skips every gate, so it
    must not be reachable from anything that took input from a client.
]]
export type BridgeSeam = {
    Context: RuntimeContext,
    Contracts: Contracts,
    Rejected: Signal<Rejection>,
    --- Installs (or, with nil, removes) the realm's gateway.
    AttachGateway: (self: BridgeSeam, gateway: NetGateway?) -> (),
    --[[
        Runs the registered handlers for a command. NO validation, NO rate limiting, NO
        authorization -- every one of those is the caller's job and the server gateway does
        all of them first. Handlers run under `xpcall`; the traceback stays on this side.
    ]]
    Execute: (self: BridgeSeam, command: string, source: CommandSource, payload: any) -> InvokeResult,
    --- Applies a replicated channel value locally, without re-publishing it.
    Receive: (self: BridgeSeam, channel: string, value: any) -> (),
    --- Retained channel values, so a joining player can be caught up on `Public` channels.
    Snapshot: (self: BridgeSeam) -> { [string]: any },
}

--- Server half of the gateway. Validates, rate limits, authorizes, then calls the handler.
export type NetServer = {
    --- Fires for every refused request. Wire this to your analytics or moderation.
    Rejected: Signal<Rejection>,
    --- Fires when one player crosses `Constants.Limits.AbuseThreshold` rejections.
    AbuseDetected: Signal<Player, number>,
    Start: (self: NetServer) -> (),
    --- Replicates a published value according to its channel contract.
    Publish: (self: NetServer, channel: string, value: any, target: Player?) -> (),
    Destroy: (self: NetServer) -> (),
}

--- Client half. Guards locally, then sends.
export type NetClient = {
    --- Fires when the local guard refuses to send. A programming error, surfaced loudly.
    Refused: Signal<Rejection>,
    Start: (self: NetClient) -> (),
    Dispatch: (self: NetClient, command: string, payload: any) -> (),
    Invoke: (self: NetClient, command: string, payload: any) -> InvokeResult,
    Destroy: (self: NetClient) -> (),
}

return table.freeze({})
