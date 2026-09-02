--!strict
--[[
    Unrest / Server / Systems / AvatarContext

    Answers "who is here and what body are they wearing right now?" so no other system has to
    write character-loading boilerplate again.

    SERVER-SIDE, AND THE CHARACTER MODEL STAYS HERE. `GetCharacter` hands back a live Instance,
    which is exactly what a server system wants and exactly what must never cross the wire: a
    replicated Instance reference is a handle into the data model, and handles are not data.

    So the `Avatar.Character` channel carries the character's NAME, not the character, and it
    is a `Player`-visibility channel -- addressed to its owner rather than broadcast. The
    schema is what enforces the first half of that: a Model is an Instance, an Instance is not
    plain data, and `Net/Validate.luau` refuses it. Flipping this channel's visibility by
    accident would produce a refusal in the log, not a leak.

    A client that wants the local character does not need a mirror of this system: it already
    has `Players.LocalPlayer.Character`, replicated by Roblox, authoritative, and free.

    Reading a character is always a question, never a wait -- `GetCharacter` returns nil rather
    than yielding, and `CharacterAdded` is there for code that wants to react instead of poll.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = require(ReplicatedStorage.Game)
local Maid = require(ReplicatedStorage.Unrest.Util.Maid)
local Signal = require(ReplicatedStorage.Unrest.Util.Signal)
local Types = require(ReplicatedStorage.Unrest.Types)

local AvatarContext = {
    Name = "AvatarContext",
    Dependencies = {} :: { string },

    CharacterAdded = (Signal.new("AvatarContext.CharacterAdded") :: any) :: Types.Signal<Player, Model>,
    CharacterRemoving = (Signal.new("AvatarContext.CharacterRemoving") :: any) :: Types.Signal<Player, Model>,

    _characters = {} :: { [Player]: Model },
    _bridge = nil :: Types.Bridge?,
    _maid = Maid.new(),
}

--[[
    On the server there is no implied player, so this returns whatever it was given -- nil
    included. Returning nil rather than throwing keeps callers honest: a system that forgot to
    thread the player through gets a clear no-op instead of silently acting on somebody.

    The player a request is about always arrives as `CommandSource.Player`, which the gateway
    read off the transport. It is never a payload field.
]]
function AvatarContext:Resolve(player: Player?): Player?
    return player
end

function AvatarContext:GetCharacter(player: Player?): Model?
    local target = self:Resolve(player)
    if target == nil then
        return nil
    end

    -- The cache is authoritative, but fall back to the live property in case a character was
    -- assigned before this system started.
    return self._characters[target] or target.Character
end

function AvatarContext:GetHumanoid(player: Player?): Humanoid?
    local character = self:GetCharacter(player)
    if character == nil then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

function AvatarContext:GetAnimator(player: Player?): Animator?
    local humanoid = self:GetHumanoid(player)
    if humanoid == nil then
        return nil
    end
    return humanoid:FindFirstChildOfClass("Animator")
end

--- Addressed to one player: `Avatar.Character` is `Player`-visibility, so the Bridge requires
--- a target and refuses to broadcast it.
function AvatarContext:_publish(player: Player): ()
    local bridge = self._bridge
    if bridge == nil then
        return
    end

    local character = self._characters[player]
    bridge:Publish(Game.Channels.Character, if character ~= nil then character.Name else nil, player)
end

function AvatarContext:_bindCharacter(player: Player, character: Model): ()
    self._characters[player] = character
    self.CharacterAdded:Fire(player, character)
    self:_publish(player)
end

function AvatarContext:_unbindCharacter(player: Player): ()
    local character = self._characters[player]
    if character == nil then
        return
    end

    self._characters[player] = nil
    self.CharacterRemoving:Fire(player, character)
    self:_publish(player)
end

function AvatarContext:_trackPlayer(player: Player): ()
    local key = `Player:{player.UserId}`
    local playerMaid = Maid.new()
    self._maid:Add(playerMaid, key)

    playerMaid:Add(player.CharacterAdded:Connect(function(character: Model)
        self:_bindCharacter(player, character)
    end))
    playerMaid:Add(player.CharacterRemoving:Connect(function()
        self:_unbindCharacter(player)
    end))

    local existing = player.Character
    if existing ~= nil then
        self:_bindCharacter(player, existing)
    end
end

function AvatarContext:Init(unrest: Types.Unrest): ()
    self._bridge = unrest.Bridge
end

function AvatarContext:Start(): ()
    self._maid:Add(Players.PlayerAdded:Connect(function(player: Player)
        self:_trackPlayer(player)
    end))
    self._maid:Add(Players.PlayerRemoving:Connect(function(player: Player)
        self:_unbindCharacter(player)
        -- Per-player connections die with the player; the maid key is what makes that ordered
        -- rather than hopeful.
        self._maid:Remove(`Player:{player.UserId}`)
        self._characters[player] = nil
    end))

    for _, player in Players:GetPlayers() do
        self:_trackPlayer(player)
    end
end

function AvatarContext:Destroy(): ()
    table.clear(self._characters)
    self._maid:Destroy()
end

return AvatarContext
