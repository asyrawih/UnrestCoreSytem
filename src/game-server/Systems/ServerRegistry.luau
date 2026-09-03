--!strict
--[[
                     ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
  _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
/==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
|==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
|==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
|==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
|==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
|==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
`-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`

    https://discord.gg/MZYTABSSfb
]]

--[[
    ServerRegistry -- who is in every live server of this place.

    Roblox gives a server no way to see its siblings, so the servers have to tell each other.
    A MemoryStoreSortedMap is the notice board: every server writes ONE entry describing
    itself, every server reads the whole board, and nobody asks anybody anything directly.

        this server  --SetAsync(JobId)-->  [ sorted map ]  <--GetRangeAsync--  this server
                                                                                   |
                                                                    ServerList packet
                                                                                   v
                                                                              every client

    WHY A SORTED MAP AND NOT A HASH MAP. Only a sorted map can be enumerated, and enumerating
    is the entire feature -- a directory you can only read by already knowing the keys is not
    a directory. The sort key is the player count, descending, so the fullest servers arrive
    first and `PAGE` cuts off the emptiest rather than an arbitrary slice.

    WHY THE ENTRY EXPIRES. There is no "server died" event that survives a crash, so absence
    has to be the default and presence has to be renewed. `EXPIRY` is three times `REFRESH`:
    a healthy server can miss two heartbeats -- a throttled request, a hitch -- without
    blinking out of everybody else's list, and a dead one is gone within a minute. Shutting
    down cleanly does not wait for that; `BindToClose` removes the entry outright.

    WHY CLIENTS NEVER TOUCH MEMORYSTORE. They cannot -- it is server-only -- but the shape
    matters beyond that: the poll loop fills `snapshot`, and every answer to every client is
    served from it. A player holding the Refresh button down costs one buffer per press and
    reaches no quota at all. MemoryStore's budget is shared by the whole universe and burning
    it here would take down whatever else uses it.

    WHY STUDIO IS DIFFERENT. `RunService:IsStudio()` skips the notice board and reports this
    one server. Two reasons, and the second is the real one: a Studio session writes under a
    `JobId` that belongs to nobody, so every playtest would leave a phantom server in the
    live directory; and the panel is easier to build against a list that exists the moment
    you press Play. Flip `DIRECTORY_IN_STUDIO` to test the real thing.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameNet = require(ReplicatedStorage.GameNet)
local Scope = require(ReplicatedStorage.Unrest.Util.Scope)
local Types = require(ReplicatedStorage.Unrest.Types)

--- The notice board's name. Changing it starts a new, empty directory.
local DIRECTORY = "Unrest.ServerDirectory"

--- Set true to make a Studio session write to and read from the real directory.
local DIRECTORY_IN_STUDIO = false

--- Seconds an entry survives without being rewritten. Three heartbeats, deliberately.
local EXPIRY = 45

--- Seconds between heartbeats. Also how stale the list a client is holding can be.
local REFRESH = 15

--- How many servers the board is read back in. The panel scrolls; a player does not.
local PAGE = 50

--[[
    Above every real `Players.MaxPlayers`, and below the 255 a `uint8` can carry. Both
    counts are clamped to it before they reach the packet, because a value that overflows
    its field does not fail loudly -- it wraps, and a full server starts reporting two.
]]
local SEATS = 255

--- One server, exactly as the `ServerList` packet carries it.
export type Entry = {
    JobId: string,
    Players: number,
    Capacity: number,
    Users: { number },
}

local ServerRegistry = {
    Name = "ServerRegistry",
    Dependencies = {} :: { string },
}

--[[
    Nil in Studio, and nil is a state rather than a failure: every call site checks it and
    falls back to describing this server alone.
]]
local directory: MemoryStoreSortedMap? = nil

--- The last list read off the board. Every client answer is served from here.
local snapshot: { Entry } = {}

--- Connections and the heartbeat thread. Cleaned rather than destroyed, so the handle
--- survives a `Stop`/`Start` cycle of the framework.
local lifetime = Scope.scope()

--- Set by `BindToClose`, which cannot be unregistered once it exists.
local closing = false

local function clamp(count: number): number
    return math.clamp(math.floor(count), 0, SEATS)
end

--[[
    This server as the board should see it.

    `excluding` is the whole reason this takes an argument. `PlayerRemoving` fires while the
    player is still in `Players:GetPlayers()`, so a roster read from inside that handler
    counts somebody who is on their way out -- and a server that never quite empties is
    exactly how a directory ends up advertising ghosts.
]]
local function describe(excluding: Player?): Entry
    local users: { number } = {}
    for _, player in Players:GetPlayers() do
        if player ~= excluding then
            table.insert(users, player.UserId)
        end
    end

    return {
        --- Empty in some Studio contexts, and an empty key is not a key.
        JobId = if game.JobId ~= "" then game.JobId else "studio-local",
        Players = clamp(#users),
        Capacity = clamp(Players.MaxPlayers),
        Users = users,
    }
end

--[[
    Everything read back off the board was written by another server -- usually the same code,
    but during a rolling update deliberately not. So it is checked like anything else that
    crossed a boundary: a malformed entry is dropped rather than allowed to reach a packet
    field it does not fit, where it would take the whole message down with it.
]]
local function accept(value: any): Entry?
    if typeof(value) ~= "table" then
        return nil
    end

    local jobId = value.JobId
    if typeof(jobId) ~= "string" or jobId == "" then
        return nil
    end

    local users: { number } = {}
    if typeof(value.Users) == "table" then
        for _, userId in value.Users do
            --- `Users` is a `float64` on the wire, so any integer is carried exactly; what is
            --- refused here is a non-number, which would not be carried at all.
            if typeof(userId) == "number" and userId == userId and userId > 0 then
                table.insert(users, math.floor(userId))
            end
        end
    end

    return {
        JobId = jobId,
        --- The count is recomputed rather than trusted: the two came from the same writer,
        --- and if they disagree the list of ids is the one a player can actually see.
        Players = clamp(#users),
        Capacity = if typeof(value.Capacity) == "number" then clamp(value.Capacity) else 0,
        Users = users,
    }
end

--- Rewrites this server's entry, which is also what renews its expiry.
local function announce(excluding: Player?): ()
    local entry = describe(excluding)

    if directory == nil then
        snapshot = { entry }
        return
    end

    --[[
        MemoryStore throws on throttle and on network trouble, and neither is worth taking the
        server down for: the entry simply expires and this server drops off the board until a
        later heartbeat gets through.
    ]]
    local ok, err = pcall(function()
        (directory :: MemoryStoreSortedMap):SetAsync(entry.JobId, entry, EXPIRY, entry.Players)
    end)

    if not ok then
        warn(`[ServerRegistry] could not announce this server: {err}`)
    end
end

--- Reads the whole board into `snapshot`.
local function poll(): ()
    if directory == nil then
        snapshot = { describe(nil) }
        return
    end

    local ok, items = pcall(function()
        return (directory :: MemoryStoreSortedMap):GetRangeAsync(Enum.SortDirection.Descending, PAGE)
    end)

    if not ok then
        --- The previous snapshot is kept on purpose. A failed read says nothing about which
        --- servers exist, and blanking the panel over one throttled request would be a lie.
        warn(`[ServerRegistry] could not read the directory: {items}`)
        return
    end

    local fresh: { Entry } = {}
    for _, item in items :: { { key: string, value: any, sortKey: any } } do
        local entry = accept(item.value)
        if entry ~= nil then
            table.insert(fresh, entry)
        end
    end

    snapshot = fresh
end

function ServerRegistry:Snapshot(): { Entry }
    return snapshot
end

function ServerRegistry:Init(unrest: Types.Unrest): ()
    if RunService:IsStudio() and not DIRECTORY_IN_STUDIO then
        warn(
            "[ServerRegistry] Studio: reporting this server only. The live directory is left "
                .. "alone so playtests do not leave phantom servers in it -- set "
                .. "DIRECTORY_IN_STUDIO = true to opt in."
        )
    else
        directory = MemoryStoreService:GetSortedMap(DIRECTORY)
    end

    --[[
        Answers "send me the list" with whatever the last poll left behind. Reached from the
        entry point, which is the only place a packet is unwrapped and the only place `player`
        comes from Roblox rather than from a message.
    ]]
    Scope.add(
        lifetime,
        unrest.Bridge:Handle("ServerRegistry.Request", function(payload: any)
            if typeof(payload) ~= "table" then
                return
            end

            local player = payload.Player
            if typeof(player) ~= "Instance" or not player:IsA("Player") then
                return
            end

            GameNet.packets.ServerList.sendTo({ Servers = snapshot }, player)
        end)
    )
end

function ServerRegistry:Start(): ()
    --- `Destroy` leaves this set, so a framework that is stopped and started again would
    --- otherwise come back with a heartbeat that exits on its first check.
    closing = false

    --[[
        A join or a leave changes the number this server advertises, and waiting up to
        `REFRESH` seconds to say so would make every list visibly wrong. One write per join
        and one per leave is well inside MemoryStore's budget, which grows with the player
        count that is causing the writes.
    ]]
    Scope.addBulk(
        lifetime,
        Players.PlayerAdded:Connect(function()
            announce(nil)
        end),
        Players.PlayerRemoving:Connect(function(player: Player)
            announce(player)
        end),
        --[[
            Announce, then read, then tell everyone -- in that order, so a server always
            appears in the list it hands out rather than one poll behind its own existence.
        ]]
        task.spawn(function()
            while not closing do
                announce(nil)
                poll()
                GameNet.packets.ServerList.sendToAll({ Servers = snapshot })
                task.wait(REFRESH)
            end
        end)
    )

    --[[
        Leaving cleanly should not cost the other servers `EXPIRY` seconds of advertising a
        server nobody can join. `BindToClose` cannot be unregistered, hence the flag rather
        than a connection on the scope.
    ]]
    game:BindToClose(function()
        closing = true

        if directory == nil then
            return
        end

        local jobId = describe(nil).JobId
        pcall(function()
            (directory :: MemoryStoreSortedMap):RemoveAsync(jobId)
        end)
    end)
end

function ServerRegistry:Destroy(): ()
    closing = true
    --- Cleaned, not destroyed: the handle is module state and has to survive being retired.
    Scope.clean(lifetime)
end

return ServerRegistry
