--!strict
--[[
    Unrest / Net / Transport

    The seam between the framework's policy and however bytes actually move.

    A transport carries requests and published values. It decides nothing. It never runs a
    handler, never reads a contract, and never learns whether a client was allowed to ask for
    what it just delivered. It hands the gateway a raw request and the gateway answers.

    That direction is the whole security property. Reversed, a transport becomes a place where
    the gate can be walked around, and every new transport is a new way in. As written, the
    worst a transport can do is deliver rubbish, which the gateway refuses exactly as it
    refuses rubbish from anywhere else.

    Ten methods, five per side, and deliberately nothing else. Validation, rate limiting,
    authorisation, the abuse counter and channel retention all stay in the framework.

    The default transport is Roblox remotes. A game may supply its own -- a ByteNet adapter,
    say -- by handing a provider to the composition root. The framework has no dependency on
    any networking library and must never gain one.
]]

local NetTypes = require(script.Parent.Types)

type InvokeResult = NetTypes.InvokeResult
type RejectionReason = NetTypes.RejectionReason

--[[
    What the gateway registers with the server transport.

    `player` comes from the transport's own knowledge of who sent the message, never from the
    payload. A transport that cannot say who sent something must not deliver it at all.
]]
export type RequestHandler = (player: Player, command: string, payload: any, wantsResponse: boolean) -> InvokeResult

--- What the client half registers to receive replicated channel values.
export type PublishHandler = (channel: string, value: any) -> ()

--[[
    How a transport reports something it dropped before the gateway ever saw it -- a buffer
    that would not deserialise, a message shaped wrongly for the wire.

    A transport is allowed to drop; it is not allowed to decide what that means. The report
    exists so a dropped message still reaches the abuse counter, rather than being invisible
    to the one part of the system that is counting.
]]
export type RefusalReporter = (player: Player?, command: string?, reason: RejectionReason, detail: string) -> ()

export type ServerTransport = {
    Start: (self: ServerTransport) -> (),
    --- Registers the gateway. Called once, before `Start`.
    OnRequest: (self: ServerTransport, handler: RequestHandler) -> (),
    --- Registers where the transport reports its own drops. Optional for the transport to use.
    OnRefusal: (self: ServerTransport, report: RefusalReporter) -> (),
    PublishTo: (self: ServerTransport, player: Player, channel: string, value: any) -> (),
    PublishAll: (self: ServerTransport, channel: string, value: any) -> (),
    Destroy: (self: ServerTransport) -> (),
}

export type ClientTransport = {
    Start: (self: ClientTransport) -> (),
    --- Fire and forget. Never yields.
    Send: (self: ClientTransport, command: string, payload: any) -> (),
    --[[
        Request and response. Yields.

        How the round trip is built is the transport's business: remotes have one natively,
        a packet library needs two packets and a correlation id. The framework only supplies
        the deadline, `Constants.Limits.InvokeTimeout`, and treats a missing answer as a
        timeout rather than a refusal, because it cannot tell the difference and must not
        guess.
    ]]
    Request: (self: ClientTransport, command: string, payload: any) -> InvokeResult,
    OnPublish: (self: ClientTransport, handler: PublishHandler) -> (),
    Destroy: (self: ClientTransport) -> (),
}

--[[
    What a game hands the composition root. Only the half matching the current context is
    ever built, so a client never constructs the server half and vice versa.
]]
export type TransportProvider = {
    Name: string,
    Server: (() -> ServerTransport)?,
    Client: (() -> ClientTransport)?,
}

-- Type-only module.
return table.freeze({})
