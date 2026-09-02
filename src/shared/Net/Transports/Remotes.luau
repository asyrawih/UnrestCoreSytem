--!strict
--[[
    Unrest / Net / Transports / Remotes

    The default transport: three Roblox remotes, and nothing else moves.

    This file is the only place in the framework that knows what a RemoteEvent is. Everything
    it does used to live in `Net/init.luau` and in the lower half of `Net/Client.luau`; it was
    lifted out unchanged, so a game that installs no transport of its own gets byte-for-byte
    the traffic it got before.

    THE THREE REMOTES, and there are never more:

        UnrestDispatch   RemoteEvent      client -> server, fire and forget
        UnrestInvoke     RemoteFunction   client -> server, request/response
        UnrestPublish    RemoteEvent      server -> client, channel replication

    One choke point per direction, not a remote per feature. Every request a client can make
    arrives at `UnrestDispatch` or `UnrestInvoke`, so there is exactly one function in the
    codebase that decides whether a request lives -- and it is not in this file. Adding a
    feature adds a row to the contract table; it does not add a door.

    `UnrestInvoke` is client -> server only. The server never calls `:InvokeClient`: that hands
    a server thread to a machine the server does not control, with no timeout to set on it, and
    a client that never returns stalls it forever. Server -> client is one-way `FireClient` on
    `UnrestPublish`.

    THE ENVELOPE is positional and deliberately tiny:

        Dispatch:FireServer(command: string, payload: any)
        Invoke:InvokeServer(command: string, payload: any) -> InvokeResult
        Publish:FireClient(player, channel: string, value: any)

    No sender field. No session token. No `IsAdmin`. Identity is whatever Roblox puts in the
    first argument of the server-side callback, and nothing else is ever consulted. A message
    cannot carry a permission because the envelope has nowhere to put one.

    WHAT THIS FILE DOES NOT DO, and no transport ever may:

      * it does not run a handler -- it hands the gateway a raw request and returns whatever
        the gateway answers;
      * it does not read a contract -- not `AllowClient`, not `RateLimit`, not `Payload`. It
        forwards the command name exactly as it arrived, including when what arrived is not a
        string at all, because deciding that a message is malformed is the gateway's job and
        the gateway counts it against the sender;
      * it does not know what a rejection means. It has nothing to drop, since Roblox already
        decoded the arguments, so it never calls the refusal reporter. A transport that could
        fail to decode would report through `OnRefusal` and let the gateway decide.

    `Wire` never reaches this file either. A packet-library transport reads the `Wire` field a
    game put on its own contract; remotes have no schema to look up, so this one ignores it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Parent.Parent.Constants)
local NetTypes = require(script.Parent.Parent.Types)
local Transport = require(script.Parent.Parent.Transport)

type InvokeResult = NetTypes.InvokeResult
type Remotes = NetTypes.Remotes

--[[
    Dispatches made before the server's remotes have replicated are queued, because a UI that
    is already on screen should not silently lose the first click. The queue is bounded: a
    client dispatching into a gateway that never appears must not grow a list forever, so the
    oldest entry is dropped rather than the newest refused.
]]
local MAX_PENDING = 32

--------------------------------------------------------------------------------
-- The remote objects
--------------------------------------------------------------------------------

local function ensureFolder(): Instance
    local existing = ReplicatedStorage:FindFirstChild(Constants.Remotes.Folder)
    if existing ~= nil then
        return existing
    end

    local folder = Instance.new("Folder")
    folder.Name = Constants.Remotes.Folder
    folder.Parent = ReplicatedStorage
    return folder
end

--- Reuses an existing remote of the right class, and replaces anything else squatting on the
--- name. A studio-placed leftover of the wrong ClassName must not silently disable the gate.
local function ensureEvent(parent: Instance, name: string): RemoteEvent
    local existing = parent:FindFirstChild(name)
    if existing ~= nil then
        if existing:IsA("RemoteEvent") then
            return existing
        end
        existing:Destroy()
    end

    local created = Instance.new("RemoteEvent")
    created.Name = name
    created.Parent = parent
    return created
end

local function ensureFunction(parent: Instance, name: string): RemoteFunction
    local existing = parent:FindFirstChild(name)
    if existing ~= nil then
        if existing:IsA("RemoteFunction") then
            return existing
        end
        existing:Destroy()
    end

    local created = Instance.new("RemoteFunction")
    created.Name = name
    created.Parent = parent
    return created
end

--[[
    Server only. Creates the folder and the three remotes, or adopts them if a previous boot
    already did. The server gateway starts this transport *after* every handler is registered,
    so the remotes only become reachable once there is somewhere for a request to land.
]]
local function create(): Remotes
    if not RunService:IsServer() then
        error("[Unrest.Net.Remotes] the server half is server-only; the client half waits instead.", 0)
    end

    local folder = ensureFolder()
    return {
        Dispatch = ensureEvent(folder, Constants.Remotes.Dispatch),
        Invoke = ensureFunction(folder, Constants.Remotes.Invoke),
        Publish = ensureEvent(folder, Constants.Remotes.Publish),
    }
end

--- Non-yielding lookup. Returns nil while the server has not published the gateway yet.
local function peek(): Remotes?
    local folder = ReplicatedStorage:FindFirstChild(Constants.Remotes.Folder)
    if folder == nil then
        return nil
    end

    local dispatch = folder:FindFirstChild(Constants.Remotes.Dispatch)
    local invoke = folder:FindFirstChild(Constants.Remotes.Invoke)
    local publish = folder:FindFirstChild(Constants.Remotes.Publish)
    if
        dispatch == nil
        or not dispatch:IsA("RemoteEvent")
        or invoke == nil
        or not invoke:IsA("RemoteFunction")
        or publish == nil
        or not publish:IsA("RemoteEvent")
    then
        return nil
    end

    return { Dispatch = dispatch, Invoke = invoke, Publish = publish }
end

--- Yields until the gateway replicates, or `timeout` seconds pass. Never called on a path
--- that promised not to yield.
local function await(timeout: number?): Remotes?
    local ready = peek()
    if ready ~= nil then
        return ready
    end

    local budget = timeout or 30
    local deadline = os.clock() + budget

    local folder = ReplicatedStorage:WaitForChild(Constants.Remotes.Folder, budget)
    if folder == nil then
        return nil
    end

    local dispatch = folder:WaitForChild(Constants.Remotes.Dispatch, math.max(deadline - os.clock(), 0.001))
    local invoke = folder:WaitForChild(Constants.Remotes.Invoke, math.max(deadline - os.clock(), 0.001))
    local publish = folder:WaitForChild(Constants.Remotes.Publish, math.max(deadline - os.clock(), 0.001))
    if
        dispatch == nil
        or not dispatch:IsA("RemoteEvent")
        or invoke == nil
        or not invoke:IsA("RemoteFunction")
        or publish == nil
        or not publish:IsA("RemoteEvent")
    then
        return nil
    end

    return { Dispatch = dispatch, Invoke = invoke, Publish = publish }
end

--------------------------------------------------------------------------------
-- Server half
--------------------------------------------------------------------------------

local function newServer(): Transport.ServerTransport
    local connections: { RBXScriptConnection } = {}
    local remotes: Remotes? = nil
    local request: Transport.RequestHandler? = nil
    local destroyed = false

    local server = {}

    function server:OnRequest(handler: Transport.RequestHandler): ()
        request = handler
    end

    --[[
        Accepted and never used. Roblox decodes the arguments before this transport sees them,
        so there is no message it can fail to read and therefore nothing it could drop. A
        transport with a codec of its own reports here instead of deciding for itself, so that
        a message it could not read still reaches the abuse counter.
    ]]
    function server:OnRefusal(_report: Transport.RefusalReporter): () end

    function server:Start(): ()
        local handler = request
        if handler == nil then
            error("[Unrest.Net.Remotes] :Start() before :OnRequest(); nothing would answer a request.", 0)
        end

        local created = create()
        remotes = created

        table.insert(
            connections,
            created.Dispatch.OnServerEvent:Connect(function(player: Player, command: any, payload: any)
                --[[
                    `command` is forwarded exactly as it arrived, cast and unexamined. A client
                    may send a number, a table, or nothing at all; refusing it here would mean
                    the gateway never saw it and the sender was never counted for it.
                ]]
                handler(player, command :: any, payload, false)
            end)
        )

        --[[
            Client -> server only. `created.Invoke.OnServerInvoke` is assigned; `InvokeClient`
            is never called anywhere in this framework, because a client that never returns
            would hang the server thread that called it, with no timeout available to break it.
        ]]
        created.Invoke.OnServerInvoke = function(player: Player, command: any, payload: any): InvokeResult
            return handler(player, command :: any, payload, true)
        end
    end

    function server:PublishTo(player: Player, channel: string, value: any): ()
        local ready = remotes
        if ready == nil or destroyed then
            return
        end
        ready.Publish:FireClient(player, channel, value)
    end

    function server:PublishAll(channel: string, value: any): ()
        local ready = remotes
        if ready == nil or destroyed then
            return
        end
        ready.Publish:FireAllClients(channel, value)
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

        local ready = remotes
        if ready ~= nil then
            ready.Invoke.OnServerInvoke = nil :: any
        end
        remotes = nil
        request = nil
    end

    return (server :: any) :: Transport.ServerTransport
end

--------------------------------------------------------------------------------
-- Client half
--------------------------------------------------------------------------------

local function newClient(): Transport.ClientTransport
    local connections: { RBXScriptConnection } = {}
    local pending: { { Command: string, Payload: any } } = {}
    local remotes: Remotes? = nil
    local publish: Transport.PublishHandler? = nil
    local started = false
    local destroyed = false

    local client = {}

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

    local function adopt(found: Remotes): ()
        remotes = found

        table.insert(
            connections,
            found.Publish.OnClientEvent:Connect(function(channel: any, value: any)
                --[[
                    Server -> client channel replication, and the only traffic that flows this
                    way. A channel name that is not a string is not this envelope, so it is
                    dropped here rather than handed on; nothing is decided about it, because
                    there is no sender to blame on a message the server sent.
                ]]
                if typeof(channel) ~= "string" then
                    return
                end
                local handler = publish
                if handler ~= nil then
                    handler(channel :: string, value)
                end
            end)
        )

        flush()
    end

    --- Yields only when the gateway has not replicated yet, and only for callers that are
    --- allowed to yield.
    local function resolve(): Remotes?
        local existing = remotes
        if existing ~= nil then
            return existing
        end

        local found = await(Constants.Limits.InvokeTimeout)
        if found == nil then
            return nil
        end
        if remotes == nil then
            adopt(found)
        end
        return found
    end

    function client:OnPublish(handler: Transport.PublishHandler): ()
        publish = handler
    end

    --- Never yields: the Bridge builds the client half at require time, and blocking there
    --- would deadlock every script that requires Unrest before the remotes have replicated.
    function client:Start(): ()
        if started or destroyed then
            return
        end
        started = true

        local immediate = peek()
        if immediate ~= nil then
            adopt(immediate)
            return
        end

        task.spawn(function()
            local found = await()
            if destroyed or remotes ~= nil then
                return
            end
            if found == nil then
                warn(
                    `[Unrest.Net.Remotes] no gateway appeared under ReplicatedStorage.{Constants.Remotes.Folder}. `
                        .. "Is the server bootstrap running?"
                )
                return
            end
            adopt(found)
        end)
    end

    function client:Send(command: string, payload: any): ()
        if destroyed then
            return
        end

        local ready = remotes
        if ready == nil then
            if #pending >= MAX_PENDING then
                table.remove(pending, 1)
            end
            table.insert(pending, { Command = command, Payload = payload })
            return
        end

        -- The envelope: a name and a value. Nothing else fits, which is why nothing else can
        -- be forged into it.
        ready.Dispatch:FireServer(command, payload)
    end

    function client:Request(command: string, payload: any): InvokeResult
        if destroyed then
            return { Ok = false, Value = nil, Reason = "NoHandler" }
        end

        -- Request is allowed to yield, so unlike Send it can wait for the gateway rather than
        -- queue behind it.
        local ready = resolve()
        if ready == nil then
            -- The framework cannot tell "never arrived" from "took too long", and is told not
            -- to guess: an answer that did not come is a timeout.
            return { Ok = false, Value = nil, Reason = "Timeout" }
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
                return invoke:InvokeServer(command, payload)
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
            Reason = if typeof(envelope.Reason) == "string" then envelope.Reason :: NetTypes.RejectionReason else nil,
        }
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
        publish = nil
    end

    return (client :: any) :: Transport.ClientTransport
end

--------------------------------------------------------------------------------

--[[
    The provider the composition root falls back to. A game replaces it wholesale with
    `Unrest:UseTransport(...)`; there is no per-command mixing, so whichever provider is
    installed carries every command and every channel.
]]
local Remotes: Transport.TransportProvider = {
    Name = "Remotes",
    Server = newServer,
    Client = newClient,
}

return table.freeze(Remotes)
