--!strict
--[[
    Unrest / Net / Client

    The client half of the gateway: a contract guard and a call into the transport, and after
    the transport was lifted out there is nothing else left in the file.

    ================================================================================
    THE CHECK IN THIS FILE IS A DEVELOPER CONVENIENCE. IT IS NOT A SECURITY CONTROL.
    ================================================================================

    Everything here runs on the player's machine, which the player owns. An exploiter deletes
    it, patches it, or never loads it and fires the RemoteEvent directly. So the refusal below
    buys exactly two things, both of them ergonomics:

      1. a loud `Refused` signal the moment a programmer dispatches a command the contract
         never opened to clients -- caught at the keyboard in Studio, not six weeks later in
         telemetry;
      2. no wasted remote traffic for a request the server was always going to throw away.

    It buys zero security. The identical test runs again in the server realm on arrival, from
    the server's own copy of the contract table, and *that* one is the control. The server
    does not know, ask, or care whether this file ran. If the two ever disagree, the server
    wins; if you ever have to delete one, delete this one.

    Swapping the transport does not weaken this, because it was never load-bearing. Swapping
    the transport cannot weaken the server gate either, because the gate reads the server's
    contract table and not the message.

    The asymmetry in where the two halves live is deliberate. This half is in ReplicatedStorage
    because the Bridge must construct it on the client. The other half is in
    ServerScriptService, where a client never receives it.

    WHEN THE TRANSPORT IS BUILT, and why not at require time. The Bridge builds this object
    while `ReplicatedStorage.Unrest` is still being required, which is before a game has had a
    chance to say which transport it wants. So construction is split: this object exists (and
    is attached as the gateway) from require, and the transport underneath it is built at the
    first of `Unrest:Start()` or the first dispatch. `UseTransport` refuses once that has
    happened, loudly, rather than leaving two transports half-installed.
]]

local Contracts = require(script.Parent.Contracts)
local Net = require(script.Parent)
local NetTypes = require(script.Parent.Types)
local Primitives = require(script.Parent.Parent.Primitives)
local Remotes = require(script.Parent.Transports.Remotes)
local Signal = require(script.Parent.Parent.Util.Signal)
local Transport = require(script.Parent.Transport)

type InvokeResult = NetTypes.InvokeResult
type RejectionReason = NetTypes.RejectionReason
type Signal<T...> = Primitives.Signal<T...>

local Client = {}

function Client.new(bridge: NetTypes.BridgeSeam, provider: Transport.TransportProvider?): NetTypes.NetClient
    local refused: Signal<NetTypes.Rejection> = Signal.new("NetClient.Refused")
    local installed: Transport.TransportProvider = provider or Remotes
    local transport: Transport.ClientTransport? = nil
    local started = false
    local destroyed = false

    local client = {
        Refused = refused,
    }

    local function refuse(command: string, reason: RejectionReason, detail: string): InvokeResult
        local rejection: NetTypes.Rejection = {
            Command = command,
            Reason = reason,
            Detail = detail,
            -- No player: on the client there is only one, and identity is never something
            -- this side asserts. The server reads it off the transport.
            Player = nil,
        }
        refused:Fire(rejection)
        -- Loud on purpose. Reaching this line is a bug in the calling code, not an attack.
        warn(`[Unrest.Net.Client] refused "{command}": {detail}`)
        return { Ok = false, Value = nil, Reason = reason }
    end

    --- Reads sensibly when the game has declared nothing yet, which is exactly the state
    --- where an "unknown command" message is most likely to be the one somebody reads.
    local function declared(): string
        local names = Contracts:List()
        if #names == 0 then
            return "none"
        end
        return table.concat(names, ", ")
    end

    --[[
        The advisory guard. It reads exactly the same contract table the server reads, asks
        exactly the same question, and its answer is worth exactly nothing to the server.
    ]]
    local function guard(command: any): (string?, RejectionReason?, string?)
        local name = Net.ReadCommand(command)
        if name == nil then
            return nil, "UnknownCommand", `a command name must be a string of 1..{Net.MaxCommandLength} characters`
        end

        local contract = Contracts:GetCommand(name)
        if contract == nil then
            return nil,
                "UnknownCommand",
                `"{name}" has no contract. Declare it with Contracts:Declare before dispatching it; `
                    .. `currently declared: {declared()}`
        end
        if contract.Realm ~= "Server" then
            return nil,
                "WrongRealm",
                `"{name}" runs on the {contract.Realm}, so it never crosses the wire; handle it locally instead`
        end
        if not Contracts:IsClientCallable(name) then
            return nil,
                "NotClientCallable",
                `the contract for "{name}" does not set AllowClient = true, so no client may ask for it. `
                    .. "This dispatch is a programming error: the server would have refused it too."
        end

        return name, nil, nil
    end

    --[[
        Builds the transport from whichever provider is installed, once. The published channel
        values it delivers are applied to the local Bridge without being re-published, so a
        replicated value can never bounce back across the wire.
    ]]
    local function ensureTransport(): Transport.ClientTransport?
        local existing = transport
        if existing ~= nil or destroyed then
            return existing
        end

        local build = installed.Client
        if build == nil then
            error(
                `[Unrest.Net.Client] the "{installed.Name}" transport provides no Client half, `
                    .. "so this client has no way to reach the server.",
                0
            )
        end

        local built = build()
        transport = built
        built:OnPublish(function(channel: string, value: any)
            bridge:Receive(channel, value)
        end)
        built:Start()
        return built
    end

    --[[
        Installs the transport a game chose. It must land before anything has been sent,
        because the alternative -- quietly building the default and then swapping it out -- is
        a window in which some traffic went one way and the rest went another.
    ]]
    function client:UseTransport(chosen: Transport.TransportProvider): ()
        if transport ~= nil then
            error(
                `[Unrest.Net.Client] the "{installed.Name}" transport is already running; `
                    .. "install a transport before Unrest:Start() and before the first dispatch.",
                0
            )
        end
        installed = chosen
    end

    --- Never yields: the Bridge builds this at require time, and blocking there would deadlock
    --- every script that requires Unrest before the server's remotes have replicated.
    function client:Start(): ()
        if started or destroyed then
            return
        end
        started = true
        ensureTransport()
    end

    function client:Dispatch(command: string, payload: any): ()
        if destroyed then
            return
        end

        local name, reason, detail = guard(command)
        if name == nil then
            refuse(tostring(command), reason :: RejectionReason, detail :: string)
            return
        end

        local ready = ensureTransport()
        if ready == nil then
            return
        end
        ready:Send(name, payload)
    end

    function client:Invoke(command: string, payload: any): InvokeResult
        if destroyed then
            return { Ok = false, Value = nil, Reason = "NoHandler" }
        end

        local name, reason, detail = guard(command)
        if name == nil then
            return refuse(tostring(command), reason :: RejectionReason, detail :: string)
        end

        local contract = Contracts:ExpectCommand(name)
        if contract.Response ~= true then
            return refuse(
                name,
                "ResponseNotAllowed",
                `"{name}" does not declare Response = true; use Dispatch, which does not wait`
            )
        end

        local ready = ensureTransport()
        if ready == nil then
            return { Ok = false, Value = nil, Reason = "Timeout" }
        end

        --[[
            How the round trip is built is the transport's business. The framework supplies
            the deadline -- `Constants.Limits.InvokeTimeout`, which the transport is handed
            through the same Constants table -- and treats an answer that never came as a
            timeout, because it cannot tell a wedged server from a slow one and must not guess.
        ]]
        return ready:Request(name, payload)
    end

    --[[
        The Bridge's gateway seam. `Publish` is absent, and that absence is the statement: a
        client is never the author of state anyone else can see.
    ]]
    function client:Send(command: string, payload: any, wantsResponse: boolean): InvokeResult
        if wantsResponse then
            return client:Invoke(command, payload)
        end
        client:Dispatch(command, payload)
        return { Ok = true, Value = nil, Reason = nil }
    end

    function client:Destroy(): ()
        if destroyed then
            return
        end
        destroyed = true

        local ready = transport
        if ready ~= nil then
            ready:Destroy()
        end
        transport = nil
        refused:Destroy()
    end

    return (client :: any) :: NetTypes.NetClient
end

return Client
