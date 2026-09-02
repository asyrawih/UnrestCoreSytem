--!strict
--[[
    Unrest / Server / Net / Server

    The authoritative gateway. Everything a client can reach passes through `handle` below,
    and nothing reaches a handler by any other route.

    THIS FILE IS IN ServerScriptService, NOT ReplicatedStorage, and that is a security
    property rather than a filing convention: the policy is never replicated to the machines
    it polices. The contract *table* is replicated -- it is public knowledge, a list of door
    names -- but the code that enforces it is not.

    A REQUEST IS REFUSED IN THIS ORDER. Cheapest and most decisive first, so a flood is
    turned away before it costs anything:

        1. UnknownCommand      the envelope's first field is not a plausible command name,
                               or no contract declares it
        2. NotClientCallable   the contract does not set AllowClient = true   <-- THE CONTROL
        3. WrongRealm          the contract does not run this command on the server
        4. ResponseNotAllowed  Invoke was used on a command with no Response = true
        5. RateLimited         the player's global budget across all commands is spent
        6. RateLimited         the player's budget for this specific command is spent
        7. BadPayload          the payload does not satisfy the contract's ArgumentSpec
        8. Unauthorized        the contract's Authorize hook said no
        9. HandlerError        the handler threw; the traceback stays here
           NoHandler           nothing is registered for the command on this server

    Two things about that order are deliberate:

      * The client-callable test is second, before anything reads the payload. A command a
        client may not call is refused without its arguments ever being examined, so an
        unreachable command's schema is not an attack surface.
      * Rate limiting comes BEFORE schema validation. Walking a deeply nested table is the
        expensive part of a request, and the expense should fall on the flood's budget rather
        than on the server's frame time.

    WHAT THE CALLER LEARNS: the coarse `Reason` and nothing else. Every `Detail` -- the failing
    field, the Authorize hook's reason, a handler's traceback -- is logged here and never
    crosses the wire. A client probing for the shape of the server gets the same shrug for
    "you are dead" as for "that command does not exist for you".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Contracts = require(ReplicatedStorage.Unrest.Net.Contracts)
local Net = require(ReplicatedStorage.Unrest.Net)
local NetTypes = require(ReplicatedStorage.Unrest.Net.Types)
local Primitives = require(ReplicatedStorage.Unrest.Primitives)
local Remotes = require(ReplicatedStorage.Unrest.Net.Transports.Remotes)
local Signal = require(ReplicatedStorage.Unrest.Util.Signal)
local Transport = require(ReplicatedStorage.Unrest.Net.Transport)
local Types = require(ReplicatedStorage.Unrest.Types)
local Validate = require(ReplicatedStorage.Unrest.Net.Validate)

type InvokeResult = NetTypes.InvokeResult
type RejectionReason = NetTypes.RejectionReason
type Signal<T...> = Primitives.Signal<T...>

--[[
    The Bridge owns the network seam, so it is also where the composition root parks the
    transport a game chose: `Unrest:UseTransport(...)` writes it there and both halves read it
    back, which is why there is no second way to hand this gateway a different transport from
    the one the client is using.

    Declared locally rather than on `NetTypes.BridgeSeam` for a mechanical reason: the seam
    types live in `Net/Types`, `Net/Transport` requires `Net/Types`, and a `Net/Types` that
    named a transport type would close that require into a cycle.
]]
type TransportHost = {
    TransportProvider: (self: TransportHost) -> Transport.TransportProvider?,
}

--[[
    A token bucket, one pair of numbers per player per command.

    Chosen over a sliding window of timestamps for a reason that is itself a security property:
    a timestamp list grows with the flood that fills it, so the act of rate limiting an
    attacker would cost more the harder they attacked. This is O(1) in time and O(1) in space
    no matter what arrives.
]]
type Bucket = {
    Tokens: number,
    Updated: number,
}

type PlayerState = {
    --- Budget across every command combined.
    Global: Bucket,
    --- Per-command budgets, created on first use.
    Commands: { [string]: Bucket },
    --- Rejections seen for this player, for the abuse hook.
    Rejections: number,
}

local Server = {}

local function newBucket(count: number): Bucket
    return { Tokens = count, Updated = os.clock() }
end

local function consume(bucket: Bucket, count: number, window: number): boolean
    local now = os.clock()
    local elapsed = math.max(now - bucket.Updated, 0)
    bucket.Updated = now

    local rate = count / math.max(window, 0.001)
    bucket.Tokens = math.min(count, bucket.Tokens + elapsed * rate)

    if bucket.Tokens < 1 then
        return false
    end
    bucket.Tokens -= 1
    return true
end

function Server.new(bridge: Types.Bridge): NetTypes.NetServer
    --[[
        The Bridge's gate-free seam. `Execute` skips every check, which is precisely why it is
        reached from here and nowhere else: by the time it is called, all of them have run.
    ]]
    local seam = (bridge :: any) :: NetTypes.BridgeSeam

    local rejectedSignal: Signal<NetTypes.Rejection> = Signal.new("NetServer.Rejected")
    local abuseSignal: Signal<Player, number> = Signal.new("NetServer.AbuseDetected")

    local state: { [Player]: PlayerState } = {}
    local connections: { RBXScriptConnection } = {}
    local transport: Transport.ServerTransport? = nil
    local started = false
    local destroyed = false

    local server = {
        Rejected = rejectedSignal,
        AbuseDetected = abuseSignal,
    }

    local function stateFor(player: Player): PlayerState
        local existing = state[player]
        if existing ~= nil then
            return existing
        end

        local created: PlayerState = {
            Global = newBucket(Constants.Limits.GlobalRateCount),
            Commands = {},
            Rejections = 0,
        }
        state[player] = created
        return created
    end

    --[[
        `blameClient` separates "this request was bad" from "this server is broken". A handler
        that throws is our bug, and counting it toward the player's abuse score would let a
        crashing system get its own players reported.
    ]]
    local function refuse(
        player: Player?,
        command: string,
        reason: RejectionReason,
        detail: string,
        blameClient: boolean
    ): InvokeResult
        local who = if player ~= nil then player.Name else "<no player>"
        warn(`[Unrest.Net.Server] refused "{command}" from {who} ({reason}): {detail}`)

        rejectedSignal:Fire({
            Command = command,
            Reason = reason,
            Detail = detail,
            Player = player,
        })

        if player ~= nil and blameClient then
            local entry = stateFor(player)
            entry.Rejections += 1

            local threshold = Constants.Limits.AbuseThreshold
            if entry.Rejections >= threshold and entry.Rejections % threshold == 0 then
                --[[
                    Report, never punish. An automatic kick on a heuristic bans the player with
                    the bad connection and the one whose UI double-fired; the game knows what a
                    cheater is here and this framework does not. The signal is the seam where
                    moderation plugs in.
                ]]
                abuseSignal:Fire(player, entry.Rejections)
            end
        end

        -- Only the coarse reason goes back. `detail` stayed in the log above.
        return { Ok = false, Value = nil, Reason = reason }
    end

    local function handle(player: Player, command: any, payload: any, wantsResponse: boolean): InvokeResult
        --[[
            IDENTITY COMES FROM THE TRANSPORT.

            `player` is the first argument Roblox itself puts on a remote callback. It is the
            only identity this gateway will ever accept. Nothing below reads a player, a user
            id, or a role out of `payload` -- the envelope has no field for one, and if it did,
            this line would still ignore it.
        ]]
        local name = Net.ReadCommand(command)
        if name == nil then
            return refuse(player, "<malformed>", "UnknownCommand", `the envelope carried a {typeof(command)}`, true)
        end

        local contract = Contracts:GetCommand(name)
        if contract == nil then
            return refuse(player, name, "UnknownCommand", "no contract declares this command", true)
        end

        --[[
            THE SECURITY CONTROL.

            The client ran this same test before sending. That one is a developer convenience
            executing on a machine the player owns, and this gateway does not know, ask, or
            care whether it ran, passed, or was patched out. The answer here is computed from
            the server's own contract table and the command *name*; nothing in the message
            contributes to it, so nothing a client sends can widen what it may call.
        ]]
        if not Contracts:IsClientCallable(name) then
            return refuse(player, name, "NotClientCallable", "the contract does not set AllowClient = true", true)
        end

        if contract.Realm ~= "Server" then
            return refuse(player, name, "WrongRealm", `the contract runs this command on the {contract.Realm}`, true)
        end

        if wantsResponse and contract.Response ~= true then
            return refuse(player, name, "ResponseNotAllowed", "the contract does not declare Response = true", true)
        end

        local entry = stateFor(player)

        --[[
            The global budget first, because it is the one a shotgun hits. Per-command limits
            alone can be evaded by spreading the flood across many cheap commands, each of them
            individually under its own ceiling; this is the line that makes the sum bounded too.
        ]]
        if not consume(entry.Global, Constants.Limits.GlobalRateCount, Constants.Limits.GlobalRateWindow) then
            return refuse(player, name, "RateLimited", "over the per-player budget across all commands", true)
        end

        local limit = contract.RateLimit
        local count = if limit ~= nil then limit.Count else Constants.Limits.DefaultRateCount
        local window = if limit ~= nil then limit.Window else Constants.Limits.DefaultRateWindow

        local bucket = entry.Commands[name]
        if bucket == nil then
            bucket = newBucket(count)
            entry.Commands[name] = bucket
        end
        if not consume(bucket :: Bucket, count, window) then
            return refuse(player, name, "RateLimited", `over {count} call(s) per {window}s for this command`, true)
        end

        -- Schema. Nothing past this line -- not the Authorize hook, not the handler -- ever
        -- sees a value the contract did not describe.
        local valid, detail = Validate.Payload(contract.Payload, payload)
        if not valid then
            return refuse(player, name, "BadPayload", detail or "payload failed validation", true)
        end

        --[[
            The last gate, and the only one that can see the game rather than the message. It
            runs under pcall: an `Authorize` hook that throws must fail closed, because an
            authorization check that errors open is worse than no check at all.
        ]]
        local authorize = contract.Authorize
        if authorize ~= nil then
            local ok, allowed, reason = pcall(authorize, player, payload)
            if not ok then
                return refuse(player, name, "Unauthorized", `Authorize errored: {tostring(allowed)}`, false)
            end
            if allowed ~= true then
                -- The hook's reason is logged by `refuse` and goes no further.
                return refuse(player, name, "Unauthorized", tostring(reason or "Authorize returned false"), true)
            end
        end

        local source: NetTypes.CommandSource = {
            -- Straight from the transport, never from the payload.
            Player = player,
            Context = "Server",
            Remote = true,
        }

        local result = seam:Execute(name, source, payload)
        if not result.Ok then
            -- The Bridge already logged the traceback. The caller gets a generic failure.
            local reason: RejectionReason = result.Reason or "HandlerError"
            return refuse(player, name, reason, "the handler did not complete", false)
        end

        if not wantsResponse then
            return { Ok = true, Value = nil, Reason = nil }
        end

        --[[
            A handler's return value is about to cross the wire, so it gets the same plain-data
            whitelist as anything arriving. This is what stops a handler from casually returning
            an Instance -- a live reference into the data model -- to a caller who asked for a
            boolean.
        ]]
        local safe, valueDetail = Validate.Value(nil, result.Value)
        if not safe then
            return refuse(player, name, "HandlerError", `the handler returned {valueDetail}`, false)
        end

        return { Ok = true, Value = result.Value, Reason = nil }
    end

    --- Catches a client up on retained `Public` channels. Retained means retained: a player who
    --- joins after the music started should still be told what is playing.
    local function replayPublic(player: Player): ()
        local ready = transport
        if ready == nil then
            return
        end

        for name, value in seam:Snapshot() do
            local contract = Contracts:GetChannel(name)
            if contract ~= nil and contract.Visibility == "Public" then
                ready:PublishTo(player, name, value)
            end
        end
    end

    --[[
        Replicates a published value. The Bridge has already checked visibility and schema;
        the visibility test is repeated here because this is the last function before the wire,
        and a check that cheap belongs on the last line of defence too.
    ]]
    function server:Publish(channel: string, value: any, target: Player?): ()
        local ready = transport
        if ready == nil or destroyed then
            return
        end

        local contract = Contracts:GetChannel(channel)
        local visibility = if contract ~= nil then contract.Visibility else "Server"

        if visibility == "Server" then
            return
        end

        if visibility == "Player" then
            if target == nil then
                return
            end
            ready:PublishTo(target, channel, value)
            return
        end

        ready:PublishAll(channel, value)
    end

    function server:Start(): ()
        if started then
            error("[Unrest.Net.Server] :Start() was called twice.", 0)
        end
        started = true

        --[[
            The transport is built and started here, at the end of the server's boot, and this
            is the reason `Start` is the last line of the bootstrap: the gateway becomes
            reachable only once every handler is registered, so the very first request a client
            can physically make already has somewhere to land.

            `handle` is registered BEFORE the transport starts, so there is no instant in which
            a request could arrive with nothing to refuse it.
        ]]
        local host = (bridge :: any) :: TransportHost
        local provider = host:TransportProvider() or Remotes
        local build = provider.Server
        if build == nil then
            error(
                `[Unrest.Net.Server] the "{provider.Name}" transport provides no Server half, `
                    .. "so no request could ever reach this gateway.",
                0
            )
        end

        local built = build()
        transport = built

        seam:AttachGateway((server :: any) :: NetTypes.NetGateway)

        --[[
            THE DIRECTION OF CONTROL, and the reason the transport was split out at all.

            The transport hands `handle` a raw request -- who sent it, what they called it,
            what they sent -- and `handle` answers. It never runs a handler, never reads a
            contract, and never learns whether the request was allowed. The worst a transport
            can do is deliver rubbish, which is refused exactly as rubbish from anywhere else
            is refused, and counted against the same player.
        ]]
        built:OnRequest(handle)

        --[[
            A transport may drop a message before this gateway ever sees it -- a buffer that
            will not deserialise, an envelope shaped wrongly for its wire. It is allowed to
            drop; it is not allowed to decide what the drop means. Reporting it here puts it
            through the same refusal path, and therefore the same abuse counter, as anything
            the gate refused itself.
        ]]
        built:OnRefusal(function(player: Player?, command: string?, reason: RejectionReason, detail: string)
            refuse(player, command or "<malformed>", reason, detail, true)
        end)

        built:Start()

        table.insert(
            connections,
            Players.PlayerAdded:Connect(function(player: Player)
                replayPublic(player)
            end)
        )

        table.insert(
            connections,
            Players.PlayerRemoving:Connect(function(player: Player)
                --[[
                    Buckets and rejection counters die with the player. Without this the state
                    table grows for the life of the server, which on a busy place is a slow
                    memory leak that a join/leave loop could accelerate deliberately.
                ]]
                state[player] = nil
            end)
        )

        -- Anyone already in-game when the gateway came up gets the same catch-up.
        for _, player in Players:GetPlayers() do
            replayPublic(player)
        end
    end

    function server:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true

        for _, connection in connections do
            connection:Disconnect()
        end
        table.clear(connections)
        table.clear(state)

        local ready = transport
        if ready ~= nil then
            ready:Destroy()
        end
        transport = nil

        seam:AttachGateway(nil)
        rejectedSignal:Destroy()
        abuseSignal:Destroy()
    end

    return (server :: any) :: NetTypes.NetServer
end

return Server
