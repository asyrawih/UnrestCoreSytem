--!strict
--[[
    Unrest / Bridge

    The controller column of the whiteboard, and the client/server line. One object, because
    they are the same seam seen from two angles:

      * Core publishes state        -> `Bridge:Publish(channel, value, target?)`
      * UI follows state            -> `Bridge:Subscribe(channel, handler)` / `:Peek(channel)`
      * UI sends intent             -> `Bridge:Dispatch(command, payload)` / `:Invoke(...)`
      * A system handles intent     -> `Bridge:Handle(command, handler)`

    Channels are RETAINED: a late subscriber immediately receives the last published value, so
    a button that mounts after the music started still renders the right track. That is what
    makes the Bridge safe to use from UI with arbitrary mount order.

    WHAT MAKES IT A NETWORK BOUNDARY

    A caller writes the same line on either side:

        Bridge:Dispatch("Music.Play", "Lobby")

    and the command's contract decides what that means. `Music.Play` has `Realm = "Server"`,
    so on the server it runs locally and on the client it is forwarded over the gateway. The
    caller never chooses; there is no `:DispatchToServer`. This is the whole reason the
    security model can be enforced in one place: if the caller cannot pick the transport, the
    caller cannot route around the gate.

    ROUTING, exhaustively:

        contract.Realm == Context            run locally (validated first, see below)
        Client, Realm == "Server"            forward through the client gateway
        Server, Realm == "Client"            REFUSED, WrongRealm

    That last row is a design decision, not an omission. The server never asks a client to do
    anything: it cannot verify that the client did it, so a "command" pointed that way would be
    a suggestion dressed as a mechanism. Server -> client traffic is state on a channel, and
    the client decides what to render.

    THE GATEWAYS, and why the two halves are attached differently:

      * The client half (`Net/Client.luau`) lives in ReplicatedStorage, so the Bridge simply
        builds it in the constructor.
      * The server half lives in ServerScriptService, which ReplicatedStorage cannot reach --
        deliberately, so the policy is not replicated to the machines it polices. The server
        bootstrap constructs it and attaches it through `BridgeSeam.AttachGateway`.
]]

local Contracts = require(script.Parent.Net.Contracts)
local Maid = require(script.Parent.Util.Maid)
local NetClient = require(script.Parent.Net.Client)
local NetTypes = require(script.Parent.Net.Types)
local Signal = require(script.Parent.Util.Signal)
local Types = require(script.Parent.Types)
local Validate = require(script.Parent.Net.Validate)

type Channel = {
    Value: any,
    HasValue: boolean,
    Signal: Types.Signal<any>,
}

local Bridge = {}

function Bridge.new(context: Types.RuntimeContext): Types.Bridge
    if context ~= "Server" and context ~= "Client" then
        error(`[Unrest.Bridge] .new expects "Server" or "Client", got {tostring(context)}.`, 0)
    end

    local channels: { [string]: Channel } = {}
    local handlers: { [string]: { Types.CommandHandler } } = {}
    local lifetime = Maid.new()
    local gateway: NetTypes.NetGateway? = nil
    local destroyed = false

    local rejected: Types.Signal<Types.Rejection> = Signal.new("Bridge.Rejected")

    local bridge = {
        Context = context,
        Contracts = Contracts,
        Rejected = rejected,
    }

    local function assertAlive(method: string): ()
        if destroyed then
            error(`[Unrest.Bridge] :{method} called after the Bridge was destroyed.`, 0)
        end
    end

    local function assertName(value: any, method: string, label: string): string
        if typeof(value) ~= "string" or #value == 0 then
            error(`[Unrest.Bridge] :{method} expects a non-empty {label} name, got {typeof(value)}.`, 0)
        end
        return value :: string
    end

    --[[
        Every refusal on this side of the wire. `Detail` is developer-facing and stays local:
        on the server it is logged, and the only thing that ever travels back to a caller is
        the coarse `Reason`.
    ]]
    local function reject(command: string, reason: Types.RejectionReason, detail: string): Types.InvokeResult
        rejected:Fire({
            Command = command,
            Reason = reason,
            Detail = detail,
            Player = nil,
        })
        return { Ok = false, Value = nil, Reason = reason }
    end

    --- A Bridge-level refusal is always a bug in the calling code -- an undeclared command, a
    --- realm mix-up, an Invoke on a command with no response. Those deserve a warning.
    local function rejectLoudly(command: string, reason: Types.RejectionReason, detail: string): Types.InvokeResult
        warn(`[Unrest.Bridge] "{command}" refused ({reason}): {detail}`)
        return reject(command, reason, detail)
    end

    local function channelFor(name: string): Channel
        local channel = channels[name]
        if channel == nil then
            local created: Channel = {
                Value = nil,
                HasValue = false,
                Signal = Signal.new(`Bridge.Channel[{name}]`),
            }
            channels[name] = created
            lifetime:Add(created.Signal)
            return created
        end
        return channel
    end

    local function visibilityOf(name: string): Types.ChannelVisibility
        local contract = Contracts:GetChannel(name)
        -- Deny by default, one last time: an undeclared channel is `Server`, so a channel
        -- someone forgot to declare cannot leak by omission.
        return if contract ~= nil then contract.Visibility else "Server"
    end

    --- Retains and fans out locally. Split out because a replicated value arriving from the
    --- server takes this path and must NOT take the replication path again.
    local function retain(name: string, value: any): ()
        local entry = channelFor(name)
        entry.Value = value
        entry.HasValue = true
        entry.Signal:Fire(value)
    end

    --[[
        Runs the handlers for a command. Deliberately gate-free: this is the seam the server
        gateway calls *after* it has done the contract check, the rate check, the schema check
        and the authorization check. Nothing that took input from a client may call it directly.
    ]]
    local function execute(command: string, source: Types.CommandSource, payload: any): Types.InvokeResult
        local registered = handlers[command]
        if registered == nil or #registered == 0 then
            return reject(command, "NoHandler", `no handler is registered for "{command}" on the {context}.`)
        end

        local value: any = nil
        local failure: string? = nil

        -- Snapshot: a handler is allowed to add or drop another handler mid-dispatch.
        for _, handler in table.clone(registered) do
            --[[
                Handler isolation. One misbehaving system must not stall the gateway for every
                other player, so each handler runs under `xpcall` and the traceback is captured
                here, on the server, where it is useful. The caller gets a generic failure.
            ]]
            local ok, result = xpcall(handler, function(err: any): string
                return debug.traceback(tostring(err), 2)
            end, source, payload)

            if ok then
                -- First non-nil return wins; later handlers are observers.
                if value == nil then
                    value = result
                end
            elseif failure == nil then
                failure = tostring(result)
            end
        end

        if failure ~= nil then
            warn(`[Unrest.Bridge] handler for "{command}" errored:\n{failure}`)
            return reject(command, "HandlerError", failure)
        end

        return { Ok = true, Value = value, Reason = nil }
    end

    --------------------------------------------------------------------------------
    -- Channels
    --------------------------------------------------------------------------------

    function bridge:Publish(channel: string, value: any, target: Player?): ()
        assertAlive("Publish")
        local name = assertName(channel, "Publish", "channel")

        if context ~= "Server" then
            -- A client publishes only to itself. Client state never replicates: the server is
            -- the sole author of anything another player could see.
            retain(name, value)
            return
        end

        local visibility = visibilityOf(name)

        if visibility == "Player" then
            --[[
                A per-player channel has no single "current value", so it is not retained
                server-side -- retaining it would let one player's state be read as everyone's
                by the next thing that calls `Peek`. It is addressed and sent, and the
                receiving client retains its own copy.
            ]]
            if target == nil then
                error(
                    `[Unrest.Bridge] :Publish("{name}") is a Player channel and needs a target player. `
                        .. "Publishing it to everyone is exactly the mistake the contract exists to prevent.",
                    0
                )
            end
        else
            retain(name, value)
        end

        if visibility == "Server" then
            return
        end

        --[[
            The schema is the last thing between a value and the wire. A channel with no
            `Value` spec is still checked against the plain-data whitelist, so an Instance --
            a character Model, say -- cannot replicate even by accident.
        ]]
        local contract = Contracts:GetChannel(name)
        local valid, detail = Validate.Value(if contract ~= nil then contract.Value else nil, value)
        if not valid then
            warn(`[Unrest.Bridge] refused to replicate "{name}": {detail}`)
            -- Fail closed: the value stays local, the wire stays clean.
            reject(name, "BadPayload", detail or "channel value failed validation")
            return
        end

        local active = gateway
        if active == nil then
            return
        end
        local publish = active.Publish
        if publish == nil then
            return
        end
        publish(active, name, value, target)
    end

    function bridge:Subscribe(channel: string, handler: (value: any) -> ()): Types.Connection
        assertAlive("Subscribe")
        local name = assertName(channel, "Subscribe", "channel")
        if type(handler) ~= "function" then
            error(`[Unrest.Bridge] :Subscribe("{name}") expects a function, got {typeof(handler)}.`, 0)
        end

        local entry = channelFor(name)
        local connection = entry.Signal:Connect(handler)
        if entry.HasValue then
            local value = entry.Value
            task.spawn(function()
                if connection.Connected then
                    handler(value)
                end
            end)
        end

        return connection
    end

    function bridge:Peek(channel: string): any
        local name = assertName(channel, "Peek", "channel")
        local entry = channels[name]
        return if entry ~= nil then entry.Value else nil
    end

    --------------------------------------------------------------------------------
    -- Commands
    --------------------------------------------------------------------------------

    function bridge:Dispatch(command: string, payload: any): ()
        assertAlive("Dispatch")
        local name = assertName(command, "Dispatch", "command")

        local contract = Contracts:GetCommand(name)
        if contract == nil then
            rejectLoudly(name, "UnknownCommand", "no contract declares this command")
            return
        end

        if contract.Realm == context then
            --[[
                Local dispatch. It skips the gateway, so the gateway's schema check would never
                run -- and "no handler ever sees an unvalidated payload" is a guarantee worth
                keeping absolute, including against server code with a typo in it.
            ]]
            local valid, detail = Validate.Payload(contract.Payload, payload)
            if not valid then
                rejectLoudly(name, "BadPayload", detail or "payload failed validation")
                return
            end
            execute(name, { Player = nil, Context = context, Remote = false }, payload)
            return
        end

        if context == "Server" then
            rejectLoudly(
                name,
                "WrongRealm",
                "the server does not send commands to clients; replicate state on a channel instead"
            )
            return
        end

        local active = gateway
        local send = if active ~= nil then active.Send else nil
        if active == nil or send == nil then
            rejectLoudly(name, "NoHandler", "the client gateway is not running")
            return
        end

        send(active, name, payload, false)
    end

    function bridge:Invoke(command: string, payload: any): Types.InvokeResult
        assertAlive("Invoke")
        local name = assertName(command, "Invoke", "command")

        local contract = Contracts:GetCommand(name)
        if contract == nil then
            return rejectLoudly(name, "UnknownCommand", "no contract declares this command")
        end
        if contract.Response ~= true then
            return rejectLoudly(name, "ResponseNotAllowed", "the contract does not declare Response = true")
        end

        if contract.Realm == context then
            local valid, detail = Validate.Payload(contract.Payload, payload)
            if not valid then
                return rejectLoudly(name, "BadPayload", detail or "payload failed validation")
            end
            return execute(name, { Player = nil, Context = context, Remote = false }, payload)
        end

        if context == "Server" then
            return rejectLoudly(name, "WrongRealm", "the server never invokes a client")
        end

        local active = gateway
        local send = if active ~= nil then active.Send else nil
        if active == nil or send == nil then
            return rejectLoudly(name, "NoHandler", "the client gateway is not running")
        end

        return send(active, name, payload, true)
    end

    function bridge:Handle(command: string, handler: Types.CommandHandler): Types.Connection
        assertAlive("Handle")
        local name = assertName(command, "Handle", "command")
        if type(handler) ~= "function" then
            error(`[Unrest.Bridge] :Handle("{name}") expects a function, got {typeof(handler)}.`, 0)
        end

        -- Throws with the list of declared commands: a handler for a command no contract
        -- mentions could never be reached, and silently accepting it would hide that.
        local contract = Contracts:ExpectCommand(name)
        if contract.Realm ~= context then
            error(
                `[Unrest.Bridge] :Handle("{name}") was called on the {context}, but its contract puts the handler `
                    .. `on the {contract.Realm}. Move the registration, or change the contract's Realm.`,
                0
            )
        end

        local registered = handlers[name]
        if registered == nil then
            registered = {}
            handlers[name] = registered
        end
        table.insert(registered, handler)

        local connection = { Connected = true }
        local function disconnect(): ()
            if not connection.Connected then
                return
            end
            connection.Connected = false
            local list = handlers[name]
            if list == nil then
                return
            end
            local index = table.find(list, handler)
            if index ~= nil then
                table.remove(list, index)
            end
        end
        connection.Disconnect = disconnect

        return (connection :: any) :: Types.Connection
    end

    --------------------------------------------------------------------------------
    -- The network seam: `NetTypes.BridgeSeam`, not on `Types.Bridge` and not for user code
    --------------------------------------------------------------------------------

    function bridge:AttachGateway(installed: NetTypes.NetGateway?): ()
        gateway = installed
    end

    function bridge:Execute(command: string, source: Types.CommandSource, payload: any): Types.InvokeResult
        assertAlive("Execute")
        return execute(command, source, payload)
    end

    function bridge:Receive(channel: string, value: any): ()
        if destroyed then
            return
        end
        -- Applied locally and never re-published: replicated state cannot bounce back.
        retain(channel, value)
    end

    function bridge:Snapshot(): { [string]: any }
        local snapshot: { [string]: any } = {}
        for name, entry in channels do
            if entry.HasValue then
                snapshot[name] = entry.Value
            end
        end
        return snapshot
    end

    --------------------------------------------------------------------------------

    function bridge:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true

        gateway = nil
        table.clear(channels)
        table.clear(handlers)
        lifetime:Destroy()
        rejected:Destroy()
    end

    --[[
        The client wires itself. `Unrest`'s composition root builds the Bridge with nothing but
        a context, so if the client half were attached from outside, every client bootstrap
        would have to remember to do it -- and forgetting would fail open, as a Dispatch that
        quietly does nothing. Building it here means the client is networked by construction.
    ]]
    if context == "Client" then
        local seam = (bridge :: any) :: NetTypes.BridgeSeam
        local client = NetClient.new(seam)

        lifetime:Add(client)
        lifetime:Add(client.Refused:Connect(function(rejection: Types.Rejection)
            -- One signal for "this request was refused", wherever the refusal happened.
            rejected:Fire(rejection)
        end))

        seam:AttachGateway((client :: any) :: NetTypes.NetGateway)
        client:Start()
    end

    return (bridge :: any) :: Types.Bridge
end

return Bridge
