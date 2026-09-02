--!strict
--[[
    Unrest / Server / Systems / DanceSystem

    Named emotes, one at a time per player, played on the server so every other player sees
    them.

    Two things are worth reading closely here.

    THE PLAYER IS NEVER IN THE PAYLOAD. `Dance.Play` carries one thing, the emote's name. Who
    is dancing comes from `CommandSource.Player`, which the gateway read off the remote
    callback's first argument. There is no `payload.Target`, and there is nowhere to put one,
    so "play an emote on someone else's character" is not a request this framework can express
    -- not a request it validates carefully, one it cannot represent.

    THE DEPENDENCY IS THE OTHER HALF. `Dependencies = { "AvatarContext" }` means Core has
    initialised AvatarContext before this system's `Init` runs, so everything about "where is
    this player's Animator" lives there and this file has no character-loading code at all.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = require(ReplicatedStorage.Game)
local GameTypes = require(ReplicatedStorage.Game.Types)
local Maid = require(ReplicatedStorage.Unrest.Util.Maid)
local Signal = require(ReplicatedStorage.Unrest.Util.Signal)
local Types = require(ReplicatedStorage.Unrest.Types)

type Playing = {
    Name: string,
    Track: AnimationTrack,
}

local DEFAULT_DANCES: { [string]: string } = {
    Wave = "rbxassetid://507770239",
    Point = "rbxassetid://507770453",
    Cheer = "rbxassetid://507770677",
    Dance = "rbxassetid://507771019",
}

local DanceSystem = {
    Name = "DanceSystem",
    Dependencies = { "AvatarContext" },

    DanceChanged = (Signal.new("DanceSystem.DanceChanged") :: any) :: Types.Signal<Player, string?>,

    _dances = {} :: { [string]: string },
    _order = {} :: { string },
    _animations = {} :: { [string]: Animation },
    _playing = {} :: { [Player]: Playing },
    _avatar = nil :: GameTypes.AvatarContext?,
    _bridge = nil :: Types.Bridge?,
    _maid = Maid.new(),
}

function DanceSystem:List(): { string }
    return table.clone(self._order)
end

--- Registers or replaces an emote. Ids are resolved to Animation instances lazily.
function DanceSystem:AddDance(name: string, animationId: string): ()
    if typeof(name) ~= "string" or #name == 0 then
        error(`[Unrest.DanceSystem] :AddDance expects a non-empty name, got {typeof(name)}.`, 0)
    end
    if typeof(animationId) ~= "string" or string.match(animationId, "^rbxassetid://%d+$") == nil then
        error(
            `[Unrest.DanceSystem] :AddDance("{name}", ...) expects an animation id of the form `
                .. `"rbxassetid://123456", got {typeof(animationId)}.`,
            0
        )
    end

    if self._dances[name] == nil then
        table.insert(self._order, name)
    end
    self._dances[name] = animationId

    local cached = self._animations[name]
    if cached ~= nil then
        self._maid:Remove(`Animation:{name}`)
        self._animations[name] = nil
    end
end

function DanceSystem:_animationFor(name: string): Animation?
    local cached = self._animations[name]
    if cached ~= nil then
        return cached
    end

    local animationId = self._dances[name]
    if animationId == nil then
        return nil
    end

    local animation = Instance.new("Animation")
    animation.Name = name
    animation.AnimationId = animationId

    self._animations[name] = animation
    self._maid:Add(animation, `Animation:{name}`)
    return animation
end

function DanceSystem:GetCurrent(player: Player?): string?
    if player == nil then
        return nil
    end

    local playing = self._playing[player]
    return if playing ~= nil then playing.Name else nil
end

--- A `Player` channel: one player's emote is addressed to that player, never broadcast.
function DanceSystem:_publish(player: Player): ()
    local bridge = self._bridge
    if bridge == nil then
        return
    end
    bridge:Publish(Game.Channels.Dance, self:GetCurrent(player), player)
end

function DanceSystem:Stop(player: Player?): ()
    if player == nil then
        return
    end

    local playing = self._playing[player]
    if playing == nil then
        return
    end

    self._playing[player] = nil
    playing.Track:Stop(0.15)
    playing.Track:Destroy()

    self.DanceChanged:Fire(player, nil)
    self:_publish(player)
end

--[[
    Plays a registered emote on `player`'s own character. Returns false with a warning when the
    dance is unknown or the player has no Animator right now (mid-respawn, or a character that
    has not loaded) -- a missing body is an ordinary runtime state, not a bug and not an attack.
]]
function DanceSystem:Play(name: string, player: Player?): boolean
    local avatar = self._avatar
    if avatar == nil or player == nil then
        return false
    end

    local animation = self:_animationFor(name)
    if animation == nil then
        -- Logged, not returned: the caller learns `false` and cannot enumerate the emote table
        -- by watching which names fail differently.
        local known = if #self._order == 0 then "<none>" else table.concat(self._order, ", ")
        warn(`[Unrest.DanceSystem] no dance named "{name}". Known dances: {known}.`)
        return false
    end

    local animator = avatar:GetAnimator(player)
    if animator == nil then
        warn(`[Unrest.DanceSystem] {player.Name} has no Animator right now; "{name}" was skipped.`)
        return false
    end

    self:Stop(player)

    local track = animator:LoadAnimation(animation)
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true
    track:Play(0.15)

    self._playing[player] = { Name = name, Track = track }
    self.DanceChanged:Fire(player, name)
    self:_publish(player)

    return true
end

function DanceSystem:Init(unrest: Types.Unrest): ()
    local bridge = unrest.Bridge
    self._bridge = bridge
    self._avatar = unrest:Get("AvatarContext") :: GameTypes.AvatarContext

    for name, animationId in DEFAULT_DANCES do
        self:AddDance(name, animationId)
    end
    table.sort(self._order)

    --[[
        `source.Player` is the caller, straight from the transport. On a local server dispatch
        it is nil and `Play` returns false, which is the correct answer to "dance, on behalf of
        nobody".
    ]]
    self._maid:Add(bridge:Handle(Game.Commands.DancePlay, function(source: Types.CommandSource, payload: any)
        return self:Play(payload :: string, source.Player)
    end))

    self._maid:Add(bridge:Handle(Game.Commands.DanceStop, function(source: Types.CommandSource): ()
        self:Stop(source.Player)
    end))
end

function DanceSystem:Start(): ()
    local avatar = self._avatar
    if avatar == nil then
        return
    end

    -- A new body cannot keep dancing with the old body's track.
    self._maid:Add(avatar.CharacterRemoving:Connect(function(player: Player)
        local playing = self._playing[player]
        if playing ~= nil then
            self._playing[player] = nil
            playing.Track:Destroy()
            self.DanceChanged:Fire(player, nil)
            self:_publish(player)
        end
    end))
end

function DanceSystem:Destroy(): ()
    for player in self._playing do
        self:Stop(player)
    end
    table.clear(self._playing)
    table.clear(self._animations)
    self._maid:Destroy()
end

return DanceSystem
