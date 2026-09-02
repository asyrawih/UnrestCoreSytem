--!strict
--[[
    Unrest / Core / Systems / AvatarContext

    Answers "who is here and what body are they wearing right now?" so that no other system
    has to write character-loading boilerplate again.

    Context aware: on the client `player` defaults to `Players.LocalPlayer`, on the server it
    is required. Reading a character is always a question, never a wait -- `GetCharacter`
    returns nil rather than yielding, and `CharacterAdded` is there for code that wants to
    react instead of poll.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Parent.Types)
local Maid = require(script.Parent.Parent.Parent.Bridge.Maid)
local Signal = require(script.Parent.Parent.Parent.Bridge.Signal)

local AvatarContext = {
    Name = "AvatarContext",

    CharacterAdded = (Signal.new("AvatarContext.CharacterAdded") :: any) :: Types.Signal<Player, Model>,
    CharacterRemoving = (Signal.new("AvatarContext.CharacterRemoving") :: any) :: Types.Signal<Player, Model>,

    _characters = {} :: { [Player]: Model },
    _bridge = nil :: Types.Bridge?,
    _isClient = RunService:IsClient(),
    _maid = Maid.new(),
}

--[[
    Fills in the implied player. Returning nil (rather than throwing) keeps callers on the
    server honest: they must pass a player, and they get a clear nil instead of LocalPlayer.
]]
function AvatarContext:Resolve(player: Player?): Player?
    if player ~= nil then
        return player
    end
    if self._isClient then
        return Players.LocalPlayer
    end
    return nil
end

function AvatarContext:GetCharacter(player: Player?): Model?
    local target = self:Resolve(player)
    if target == nil then
        return nil
    end

    -- The cache is authoritative, but fall back to the live property in case a character
    -- was assigned before this system started.
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

function AvatarContext:_publish(): ()
    local bridge = self._bridge
    if bridge == nil or not self._isClient then
        return
    end
    bridge:Publish(Constants.Channels.Character, self:GetCharacter(nil))
end

function AvatarContext:_bindCharacter(player: Player, character: Model): ()
    self._characters[player] = character
    self.CharacterAdded:Fire(player, character)
    self:_publish()
end

function AvatarContext:_unbindCharacter(player: Player): ()
    local character = self._characters[player]
    if character == nil then
        return
    end

    self._characters[player] = nil
    self.CharacterRemoving:Fire(player, character)
    self:_publish()
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
        self._maid:Remove(`Player:{player.UserId}`)
    end))

    for _, player in Players:GetPlayers() do
        self:_trackPlayer(player)
    end

    self:_publish()
end

function AvatarContext:Destroy(): ()
    table.clear(self._characters)
    self._maid:Destroy()
end

return AvatarContext
