--!strict
--[[
    Unrest / Core / Systems / DanceSystem

    Named emotes, one at a time per player. The interesting part is the dependency: it
    declares `Dependencies = { "AvatarContext" }`, so Core guarantees AvatarContext exists
    (and has been initialised) before this system's `Init` runs, and this system's `Start`
    runs after AvatarContext's.

    Everything about "where is this player's Animator" is AvatarContext's problem, which is
    why this file has no character-loading code at all.
]]

local Constants = require(script.Parent.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Parent.Types)
local Maid = require(script.Parent.Parent.Parent.Bridge.Maid)
local Signal = require(script.Parent.Parent.Parent.Bridge.Signal)

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
    _avatar = nil :: Types.AvatarContext?,
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
    local avatar = self._avatar
    if avatar == nil then
        return nil
    end

    local target = avatar:Resolve(player)
    if target == nil then
        return nil
    end

    local playing = self._playing[target]
    return if playing ~= nil then playing.Name else nil
end

function DanceSystem:Stop(player: Player?): ()
    local avatar = self._avatar
    if avatar == nil then
        return
    end

    local target = avatar:Resolve(player)
    if target == nil then
        return
    end

    local playing = self._playing[target]
    if playing == nil then
        return
    end

    self._playing[target] = nil
    playing.Track:Stop(0.15)
    playing.Track:Destroy()

    self.DanceChanged:Fire(target, nil)

    local bridge = self._bridge
    if bridge ~= nil then
        bridge:Publish(Constants.Channels.Dance, nil)
    end
end

--[[
    Plays a registered emote. Returns false with a warning when the dance is unknown or the
    player currently has no Animator (mid-respawn, or a server-side call for a player whose
    character has not loaded) -- a missing body is an ordinary runtime state, not a bug.
]]
function DanceSystem:Play(name: string, player: Player?): boolean
    local avatar = self._avatar
    if avatar == nil then
        return false
    end

    local target = avatar:Resolve(player)
    if target == nil then
        warn("[Unrest.DanceSystem] :Play needs an explicit player on the server.")
        return false
    end

    local animation = self:_animationFor(name)
    if animation == nil then
        local known = if #self._order == 0 then "<none>" else table.concat(self._order, ", ")
        warn(`[Unrest.DanceSystem] no dance named "{name}". Known dances: {known}.`)
        return false
    end

    local animator = avatar:GetAnimator(target)
    if animator == nil then
        warn(`[Unrest.DanceSystem] {target.Name} has no Animator right now; "{name}" was skipped.`)
        return false
    end

    self:Stop(target)

    local track = animator:LoadAnimation(animation)
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = true
    track:Play(0.15)

    self._playing[target] = { Name = name, Track = track }
    self.DanceChanged:Fire(target, name)

    local bridge = self._bridge
    if bridge ~= nil then
        bridge:Publish(Constants.Channels.Dance, name)
    end

    return true
end

function DanceSystem:Init(unrest: Types.Unrest): ()
    self._bridge = unrest.Bridge
    self._avatar = unrest:Get("AvatarContext") :: Types.AvatarContext

    for name, animationId in DEFAULT_DANCES do
        self:AddDance(name, animationId)
    end
    table.sort(self._order)

    self._maid:Add(unrest.Bridge:OnCommand(Constants.Commands.DancePlay, function(payload: any)
        if typeof(payload) == "string" then
            self:Play(payload, nil)
        end
    end))
    self._maid:Add(unrest.Bridge:OnCommand(Constants.Commands.DanceStop, function()
        self:Stop(nil)
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
        end
    end))

    local bridge = self._bridge
    if bridge ~= nil then
        bridge:Publish(Constants.Channels.Dance, self:GetCurrent(nil))
    end
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
