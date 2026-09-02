--!strict
--[[
    Game / Transport

    The ByteNet transport, as a `TransportProvider` the composition root can install:

        local Unrest = require(ReplicatedStorage.Unrest)
        Unrest:UseTransport(require(ReplicatedStorage.Game.Transport))

    It is user-owned on purpose. The framework must never require ByteNet, and after this file
    lands it still does not: everything below is written against
    `Unrest.Net.Transport`'s ten methods and `Game.Packets`' three envelopes, and the framework
    only ever sees the interface.

    WHAT THIS FILE IS NOT ALLOWED TO DO, restated because it is the whole security property:
    it does not run handlers, does not read contracts, does not know whether a client may ask
    for what it just carried. It hands the gateway `(player, command, payload, wantsResponse)`
    and returns whatever the gateway decides. `player` comes from ByteNet's own knowledge of
    which RemoteEvent connection delivered the buffer -- there is no field for one in the
    envelope, and if there were, this file would still ignore it.

    It is allowed to DROP. A buffer that will not deserialise never reaches the gateway,
    because there is nothing to hand it. Every such drop is reported through `OnRefusal` with
    the player attached, so a client feeding the server rubbish still lands in the abuse
    counter rather than disappearing into a silent branch.

    --------------------------------------------------------------------------------
    HOW `Invoke` IS BUILT
    --------------------------------------------------------------------------------

    ByteNet is one-way, so the round trip is two packets and a correlation id:

        client  Request { Id = n, Command, Payload }      n ~= 0 means "answer me"
        server  ... gateway decides ...
        server  Response { Id = n, Ok, Reason, Value }
        client  resumes the thread parked under n

    `Send` uses `Id = 0` and parks nothing. The deadline is the framework's --
    `Constants.Limits.InvokeTimeout` -- and a missing answer is a `Timeout`, never a refusal,
    because from here the two are genuinely indistinguishable and guessing would be a lie.
    Nothing is ever retried: an automatic retry on a timeout is how a struggling server gets a
    second copy of every request it is already late on.

    The package also ships `defineQuery`, which looks like the ready-made answer and is not.
    Its client half writes the request into a channel, invokes the RemoteFunction, and never
    clears the channel cursor -- so the next Heartbeat in `process/client.luau` invokes the
    server a second time with the same bytes. Every query would be delivered at least twice.
    Two packets and a number have no such problem.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local NetTypes = require(ReplicatedStorage.Unrest.Net.Types)
local Packets = require(script.Parent.Packets)
local Transport = require(ReplicatedStorage.Unrest.Net.Transport)

type ClientTransport = Transport.ClientTransport
type InvokeResult = NetTypes.InvokeResult
type PublishHandler = Transport.PublishHandler
type RefusalReporter = Transport.RefusalReporter
type RejectionReason = NetTypes.RejectionReason
type RequestHandler = Transport.RequestHandler
type ServerTransport = Transport.ServerTransport
type TransportProvider = Transport.TransportProvider

--- How much of an arriving command name goes into a refusal log. The name itself is passed to
--- the gateway whole -- truncating what the gateway judges would be deciding for it -- but a
--- client may send 64KB of it, and a log line is not the place to find that out.
local MAX_LOGGED_COMMAND = 64

local function label(command: string): string
    if #command <= MAX_LOGGED_COMMAND then
        return command
    end
    return string.sub(command, 1, MAX_LOGGED_COMMAND) .. "..."
end

--------------------------------------------------------------------------------
-- Server
--------------------------------------------------------------------------------

local function newServer(): ServerTransport
    local handler: RequestHandler? = nil
    local reporter: RefusalReporter? = nil
    local started = false
    local destroyed = false

    local server = {}

    --[[
        `player` is passed only when the client is the one who got it wrong. A response we
        could not serialise or a gateway that threw is OUR fault, and attributing it to the
        caller would let a broken handler get its own players reported for abuse.
    ]]
    local function report(player: Player?, command: string?, reason: RejectionReason, detail: string): ()
        local report_ = reporter
        if report_ ~= nil then
            report_(player, command, reason, detail)
            return
        end
        warn(`[Game.Transport] dropped a message ({reason}): {detail}`)
    end

    local function respond(id: number, named: string, player: Player, result: InvokeResult): ()
        local blob, detail = Packets.Codec.Encode(result.Value)
        if blob == nil then
            --[[
                The gateway already ran `Validate.Value` over this, so reaching here means the
                two whitelists disagree. Answer honestly rather than silently sending nil: the
                caller asked a question and did not get one.
            ]]
            report(nil, named, "HandlerError", `a response value would not serialise: {detail}`)
            Packets.Response.sendTo({
                Id = id,
                Ok = false,
                Reason = "HandlerError",
                Value = Packets.NilBlob,
            }, player)
            return
        end

        Packets.Response.sendTo({
            Id = id,
            Ok = result.Ok,
            Reason = result.Reason or "",
            Value = blob,
        }, player)
    end

    local function onRequest(data: any, player: Player?): ()
        if destroyed then
            return
        end
        if player == nil then
            -- ByteNet only omits the player on a client-side read. Reaching this on a server
            -- would mean we cannot say who sent it, and an unattributable request is not
            -- deliverable at any price.
            return
        end

        if data == Packets.Malformed then
            report(player, nil, "BadPayload", "the request envelope would not deserialise")
            return
        end

        local envelope = data :: Packets.RequestEnvelope
        local named = label(envelope.Command)

        local ok, payload, detail = Packets.Codec.Decode(envelope.Payload)
        if not ok then
            report(player, named, "BadPayload", `the payload would not deserialise: {detail}`)
            return
        end

        local gateway = handler
        if gateway == nil then
            report(player, named, "NoHandler", "no gateway is registered with this transport")
            return
        end

        --[[
            The gateway is not supposed to raise -- it runs handlers under `xpcall` itself --
            but this call is on ByteNet's reader thread, and a raise here would take the rest
            of the batch with it and leave an `Invoke` caller waiting for the full timeout.
        ]]
        local wantsResponse = envelope.Id ~= 0
        local completed, result = pcall(gateway, player, envelope.Command, payload, wantsResponse)

        if destroyed then
            return
        end

        if not completed then
            report(nil, named, "HandlerError", `the gateway raised: {tostring(result)}`)
            if wantsResponse then
                Packets.Response.sendTo({
                    Id = envelope.Id,
                    Ok = false,
                    Reason = "HandlerError",
                    Value = Packets.NilBlob,
                }, player)
            end
            return
        end

        if wantsResponse then
            respond(envelope.Id, named, player, result :: InvokeResult)
        end
    end

    local function publish(channel: string, value: any): buffer?
        local blob, detail = Packets.Codec.Encode(value)
        if blob == nil then
            report(nil, nil, "BadPayload", `the value on channel "{channel}" would not serialise: {detail}`)
            return nil
        end
        return blob
    end

    function server:Start(): ()
        if started or destroyed then
            return
        end
        started = true

        -- Registered here rather than in the constructor because `OnRequest` and `OnRefusal`
        -- land first, and ByteNet listeners can never be taken off again.
        Packets.Request.listen(onRequest)
        Packets.Start()
    end

    function server:OnRequest(incoming: RequestHandler): ()
        handler = incoming
    end

    function server:OnRefusal(incoming: RefusalReporter): ()
        reporter = incoming
    end

    function server:PublishTo(player: Player, channel: string, value: any): ()
        if destroyed or not started then
            return
        end

        local blob = publish(channel, value)
        if blob == nil then
            return
        end
        Packets.Publish.sendTo({ Channel = channel, Value = blob }, player)
    end

    function server:PublishAll(channel: string, value: any): ()
        if destroyed or not started then
            return
        end

        local blob = publish(channel, value)
        if blob == nil then
            return
        end
        Packets.Publish.sendToAll({ Channel = channel, Value = blob })
    end

    --[[
        A flag, not an unbind. ByteNet's `listen` returns no disconnect and its process loop
        cannot be stopped, so the listener above stays connected for the life of the server
        and this is what makes it inert. Building a second transport after destroying this one
        therefore leaves the first still reading; the framework never does that, and if it ever
        needs to, this is the line that has to change upstream first.
    ]]
    function server:Destroy(): ()
        destroyed = true
        handler = nil
        reporter = nil
    end

    return (server :: any) :: ServerTransport
end

--------------------------------------------------------------------------------
-- Client
--------------------------------------------------------------------------------

local function newClient(): ClientTransport
    local publishHandler: PublishHandler? = nil
    local pending: { [number]: (InvokeResult) -> () } = {}
    local nextId = 0
    local started = false
    local destroyed = false

    local client = {}

    --- Correlation ids, skipping zero because zero means "no answer wanted". A `u32` at even
    --- a thousand invokes a second wraps in seven weeks, and the `pending` check makes a
    --- collision impossible rather than merely unlikely.
    local function allocate(): number
        repeat
            nextId = (nextId + 1) % 0x100000000
        until nextId ~= 0 and pending[nextId] == nil
        return nextId
    end

    local function onResponse(data: any): ()
        if destroyed then
            return
        end
        if data == Packets.Malformed then
            warn("[Game.Transport] dropped a response envelope that would not deserialise")
            return
        end

        local envelope = data :: Packets.ResponseEnvelope
        local settle = pending[envelope.Id]
        if settle == nil then
            -- Already timed out, or never ours. Either way there is nobody to hand it to.
            return
        end

        local ok, value = Packets.Codec.Decode(envelope.Value)
        if not ok then
            settle({ Ok = false, Value = nil, Reason = "HandlerError" })
            return
        end

        settle({
            Ok = envelope.Ok,
            Value = value,
            Reason = if envelope.Reason == "" then nil else envelope.Reason :: RejectionReason,
        })
    end

    local function onPublish(data: any): ()
        if destroyed then
            return
        end
        if data == Packets.Malformed then
            warn("[Game.Transport] dropped a publish envelope that would not deserialise")
            return
        end

        local envelope = data :: Packets.PublishEnvelope
        local deliver = publishHandler
        if deliver == nil then
            return
        end

        local ok, value, detail = Packets.Codec.Decode(envelope.Value)
        if not ok then
            warn(`[Game.Transport] dropped channel "{envelope.Channel}": {detail}`)
            return
        end

        deliver(envelope.Channel, value)
    end

    --- Never yields. The Bridge builds this while `Unrest` is still being required, so
    --- waiting for the server's remotes here would deadlock every script behind it.
    function client:Start(): ()
        if started or destroyed then
            return
        end
        started = true

        Packets.Response.listen(onResponse)
        Packets.Publish.listen(onPublish)
        -- Yields on `WaitForChild`. Anything sent before it returns sits in ByteNet's channel
        -- buffer and goes out on the first Heartbeat after the gateway appears.
        task.spawn(Packets.Start)
    end

    function client:Send(command: string, payload: any): ()
        if destroyed then
            return
        end

        local blob, detail = Packets.Codec.Encode(payload)
        if blob == nil then
            -- Loud, because a payload this wire cannot carry is a payload the server would
            -- have refused as well: it is a programming error, not an attack.
            warn(`[Game.Transport] refused to send "{label(command)}": the payload is {detail}`)
            return
        end

        Packets.Request.send({ Id = 0, Command = command, Payload = blob })
    end

    function client:Request(command: string, payload: any): InvokeResult
        if destroyed then
            return { Ok = false, Value = nil, Reason = "NoHandler" }
        end

        local blob, detail = Packets.Codec.Encode(payload)
        if blob == nil then
            warn(`[Game.Transport] refused to send "{label(command)}": the payload is {detail}`)
            return { Ok = false, Value = nil, Reason = "BadPayload" }
        end

        local id = allocate()
        local thread = coroutine.running()
        local settled = false

        --[[
            First of the answer and the deadline wins; the loser finds `settled` already true
            and does nothing. The parked entry is removed by whichever wins, so a response that
            arrives after the deadline finds nobody waiting and is dropped rather than resuming
            a thread that has moved on.
        ]]
        pending[id] = function(result: InvokeResult): ()
            if settled then
                return
            end
            settled = true
            pending[id] = nil
            task.spawn(thread, result)
        end

        Packets.Request.send({ Id = id, Command = command, Payload = blob })

        task.delay(Constants.Limits.InvokeTimeout, function(): ()
            if settled then
                return
            end
            settled = true
            pending[id] = nil
            task.spawn(thread, { Ok = false, Value = nil, Reason = "Timeout" })
        end)

        local result: any = coroutine.yield()
        return result :: InvokeResult
    end

    function client:OnPublish(incoming: PublishHandler): ()
        publishHandler = incoming
    end

    --- Like the server half, a flag rather than an unbind. Threads parked on an answer are
    --- released as timeouts instead of being left to wait out a deadline for a transport that
    --- is no longer listening.
    function client:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true
        publishHandler = nil

        local parked = pending
        pending = {}
        for _, settle in parked do
            settle({ Ok = false, Value = nil, Reason = "Timeout" })
        end
    end

    return (client :: any) :: ClientTransport
end

--------------------------------------------------------------------------------

--[[
    Both halves are supplied; the composition root builds only the one its realm needs, so a
    client never constructs the server half and vice versa.

    Requiring this module has no side effect beyond loading `Packets` -- no remotes, no
    listeners, no process. Nothing happens until the framework calls `Start` on the half it
    built, which is what makes installing a transport a decision rather than an import.
]]
return table.freeze({
    Name = "ByteNet",
    Server = newServer,
    Client = newClient,
}) :: TransportProvider
