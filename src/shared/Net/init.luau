--!strict
--[[
    Unrest / Net

    Shared transport plumbing: the remote objects themselves, and the shape of what travels
    over them. Both realms require this module. Neither realm's *policy* lives here -- the
    client's advisory guard is in `Net/Client.luau`, and the real gate is in the server realm,
    where a client cannot read it.

    THE THREE REMOTES, and there are never more:

        UnrestDispatch   RemoteEvent      client -> server, fire and forget
        UnrestInvoke     RemoteFunction   client -> server, request/response
        UnrestPublish    RemoteEvent      server -> client, channel replication

    One choke point per direction, not a remote per feature. Every request a client can make
    arrives at `UnrestDispatch` or `UnrestInvoke`, so there is exactly one function in the
    codebase that decides whether a request lives. Adding a feature adds a row to the contract
    table; it does not add a door.

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
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Constants)
local NetTypes = require(script.Types)

export type Remotes = NetTypes.Remotes

--- Longest command name the transport will even look at, before any contract lookup. A
--- string is cheap to send and expensive to hash; this bounds that before we care why.
local MAX_COMMAND_LENGTH = 128

local Net = {}

Net.MaxCommandLength = MAX_COMMAND_LENGTH

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
    already did. The server bootstrap calls this *after* every handler is registered, so the
    remotes only become reachable once there is somewhere for a request to land.
]]
function Net.Create(): Remotes
    if not RunService:IsServer() then
        error("[Unrest.Net] Net.Create() is server-only; the client waits for the remotes with Net.Await().", 0)
    end

    local folder = ensureFolder()
    return {
        Dispatch = ensureEvent(folder, Constants.Remotes.Dispatch),
        Invoke = ensureFunction(folder, Constants.Remotes.Invoke),
        Publish = ensureEvent(folder, Constants.Remotes.Publish),
    }
end

--- Non-yielding lookup. Returns nil while the server has not published the gateway yet.
function Net.Peek(): Remotes?
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
function Net.Await(timeout: number?): Remotes?
    local ready = Net.Peek()
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

--[[
    The first thing done to anything arriving off the wire: is this even a command *name*?
    Returns nil for a value that is not a bounded, non-empty string, so every caller below
    can assume it is holding one.
]]
function Net.ReadCommand(value: any): string?
    if typeof(value) ~= "string" then
        return nil
    end
    local text = value :: string
    if #text == 0 or #text > MAX_COMMAND_LENGTH then
        return nil
    end
    return text
end

return Net
