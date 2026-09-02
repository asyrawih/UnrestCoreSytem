--!strict
--[[
    Unrest / Net / Client

    The client half of the gateway.

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

    The asymmetry in where the two halves live is deliberate. This half is in ReplicatedStorage
    because the Bridge must construct it on the client. The other half is in
    ServerScriptService, where a client never receives it.
]]

local Constants = require(script.Parent.Parent.Constants)
local Contracts = require(script.Parent.Contracts)
local Net = require(script.Parent)
local NetTypes = require(script.Parent.Types)
local Primitives = require(script.Parent.Parent.Primitives)
local Signal = require(script.Parent.Parent.Util.Signal)

type InvokeResult = NetTypes.InvokeResult
type RejectionReason = NetTypes.RejectionReason
type Signal<T...> = Primitives.Signal<T...>

--[[
    Dispatches made before the server's remotes have replicated are queued, because a UI that
    is already on screen should not silently lose the first click. The queue is bounded: a
    client dispatching into a gateway that never appears must not grow a list forever, so the
    oldest entry is dropped rather than the newest refused.
]]
local MAX_PENDING = 32

local Client = {}

function Client.new(bridge: NetTypes.BridgeSeam): NetTypes.NetClient
    local refused: Signal<NetTypes.Rejection> = Signal.new("NetClient.Refused")
    local connections: { RBXScriptConnection } = {}
    local pending: { { Command: string, Payload: any } } = {}
    local remotes: Net.Remotes? = nil
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

    local function flush(): ()
        local ready = remotes
        if ready == nil then
            return
        end

        local queued = pending
        pending = {}
        for _, item in queued do
            ready.Dispatch:FireServer(item.Command, item.Payload)
        end
    end

    local function adopt(found: Net.Remotes): ()
        remotes = found

        table.insert(
            connections,
            found.Publish.OnClientEvent:Connect(function(channel: any, value: any)
                --[[
                    Server -> client channel replication, and the only traffic that flows this
                    way. It is applied to the local Bridge without being re-published, so a
                    replicated value can never bounce back across the wire.
                ]]
                if typeof(channel) ~= "string" then
                    return
                end
                bridge:Receive(channel :: string, value)
            end)
        )

        flush()
    end

    --- Yields only when the gateway has not replicated yet, and only for callers that are
    --- allowed to yield.
    local function resolveRemotes(): Net.Remotes?
        local existing = remotes
        if existing ~= nil then
            return existing
        end

        local found = Net.Await(Constants.Limits.InvokeTimeout)
        if found == nil then
            return nil
        end
        if remotes == nil then
            adopt(found)
        end
        return found
    end

    --- Never yields: the Bridge builds this at require time, and blocking there would deadlock
    --- every script that requires Unrest before the server's remotes have replicated.
    function client:Start(): ()
        if started or destroyed then
            return
        end
        started = true

        local immediate = Net.Peek()
        if immediate ~= nil then
            adopt(immediate)
            return
        end

        task.spawn(function()
            local found = Net.Await()
            if destroyed or remotes ~= nil then
                return
            end
            if found == nil then
                warn(
                    `[Unrest.Net.Client] no gateway appeared under ReplicatedStorage.{Constants.Remotes.Folder}. `
                        .. "Is the server bootstrap running?"
                )
                return
            end
            adopt(found)
        end)
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

        local ready = remotes
        if ready == nil then
            if #pending >= MAX_PENDING then
                table.remove(pending, 1)
            end
            table.insert(pending, { Command = name, Payload = payload })
            return
        end

        -- The envelope: a name and a value. Nothing else fits, which is why nothing else can
        -- be forged into it.
        ready.Dispatch:FireServer(name, payload)
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

        -- Invoke is allowed to yield, so unlike Dispatch it can wait for the gateway rather
        -- than queue behind it.
        local ready = resolveRemotes()
        if ready == nil then
            return refuse(name, "Timeout", "the remote gateway is not available")
        end

        --[[
            `RemoteFunction:InvokeServer` has no timeout of its own: if the server is wedged,
            this thread waits forever. So the call runs on a spawned thread and this one is
            resumed by whichever finishes first, the response or the deadline.
        ]]
        local thread = coroutine.running()
        local invoke = ready.Invoke
        local settled = false

        task.spawn(function()
            local ok, result = pcall(function(): any
                return invoke:InvokeServer(name, payload)
            end)
            if settled then
                return
            end
            settled = true
            task.spawn(thread, ok, result)
        end)

        task.delay(Constants.Limits.InvokeTimeout, function()
            if settled then
                return
            end
            settled = true
            -- We stop waiting. We never retry: an automatic retry on a timeout is how a
            -- struggling server gets a second copy of every request it is already late on.
            task.spawn(thread, false, "timed out")
        end)

        local ok: any, result: any = coroutine.yield()
        if not ok then
            return { Ok = false, Value = nil, Reason = "Timeout" }
        end
        if typeof(result) ~= "table" then
            return { Ok = false, Value = nil, Reason = "HandlerError" }
        end

        local envelope = result :: { Ok: any, Value: any, Reason: any }
        return {
            Ok = envelope.Ok == true,
            Value = envelope.Value,
            Reason = if typeof(envelope.Reason) == "string" then envelope.Reason :: RejectionReason else nil,
        }
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

        for _, connection in connections do
            connection:Disconnect()
        end
        table.clear(connections)
        table.clear(pending)
        remotes = nil
        refused:Destroy()
    end

    return (client :: any) :: NetTypes.NetClient
end

return Client
