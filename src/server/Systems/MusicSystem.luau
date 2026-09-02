--!strict
--[[
    Unrest / Core / Systems / MusicSystem

    Owns the soundtrack: a named track table, the one Sound instance that plays it, and the
    volume. It publishes what is playing on a Bridge channel and accepts play/stop commands
    from the Bridge, so no UI code ever holds a reference to this table.

    (The Sound instance is the one place a Core system creates an Instance -- SoundService is
    state, not view. It is never parented into any GUI and is never handed out.)
]]

local SoundService = game:GetService("SoundService")

local Constants = require(script.Parent.Parent.Parent.Constants)
local Types = require(script.Parent.Parent.Parent.Types)
local Maid = require(script.Parent.Parent.Parent.Bridge.Maid)
local Signal = require(script.Parent.Parent.Parent.Bridge.Signal)

local DEFAULT_TRACKS: { Types.Track } = {
    { Name = "Lobby", SoundId = "rbxassetid://1837879082", Volume = 0.35, Looped = true },
    { Name = "Dancefloor", SoundId = "rbxassetid://1836774112", Volume = 0.5, Looped = true },
}

local MusicSystem = {
    Name = "MusicSystem",

    NowPlayingChanged = (Signal.new("MusicSystem.NowPlayingChanged") :: any) :: Types.Signal<string?>,

    _tracks = {} :: { [string]: Types.Track },
    _order = {} :: { string },
    _current = nil :: string?,
    _sound = nil :: Sound?,
    _volume = 0.5,
    _bridge = nil :: Types.Bridge?,
    _maid = Maid.new(),
}

local function trackNames(self: typeof(MusicSystem)): string
    if #self._order == 0 then
        return "<none>"
    end
    return table.concat(self._order, ", ")
end

--- Lazily creates (or replaces, if something destroyed it) the single playback Sound.
function MusicSystem:_ensureSound(): Sound
    local existing = self._sound
    if existing ~= nil and existing.Parent ~= nil then
        return existing
    end

    local sound = Instance.new("Sound")
    sound.Name = "UnrestMusic"
    sound.Volume = self._volume
    sound.Looped = true
    sound.Parent = SoundService

    self._sound = sound
    self._maid:Add(sound, "Sound")
    return sound
end

--- Registers or replaces a track. Replacing the playing track does not restart it.
function MusicSystem:AddTrack(track: Types.Track): ()
    if typeof(track) ~= "table" or typeof(track.Name) ~= "string" or typeof(track.SoundId) ~= "string" then
        error('[Unrest.MusicSystem] :AddTrack expects { Name = "...", SoundId = "rbxassetid://..." }.', 0)
    end

    if self._tracks[track.Name] == nil then
        table.insert(self._order, track.Name)
    end
    self._tracks[track.Name] = track
end

function MusicSystem:List(): { string }
    return table.clone(self._order)
end

function MusicSystem:GetCurrent(): string?
    return self._current
end

--- Plays a registered track. Returns false (and warns) for an unknown name.
function MusicSystem:Play(name: string): boolean
    local track = self._tracks[name]
    if track == nil then
        warn(`[Unrest.MusicSystem] no track named "{name}". Known tracks: {trackNames(self)}.`)
        return false
    end

    local sound = self:_ensureSound()
    sound.SoundId = track.SoundId
    sound.Looped = if track.Looped == nil then true else track.Looped
    sound.Volume = (track.Volume or 1) * self._volume
    sound:Play()

    self._current = name
    self.NowPlayingChanged:Fire(name)

    local bridge = self._bridge
    if bridge ~= nil then
        bridge:Publish(Constants.Channels.NowPlaying, name)
    end

    return true
end

function MusicSystem:Stop(): ()
    local sound = self._sound
    if sound ~= nil then
        sound:Stop()
    end

    if self._current == nil then
        return
    end

    self._current = nil
    self.NowPlayingChanged:Fire(nil)

    local bridge = self._bridge
    if bridge ~= nil then
        bridge:Publish(Constants.Channels.NowPlaying, nil)
    end
end

--- Master volume in [0, 1]; per-track Volume is multiplied against it.
function MusicSystem:SetVolume(volume: number): ()
    if typeof(volume) ~= "number" then
        error(`[Unrest.MusicSystem] :SetVolume expects a number, got {typeof(volume)}.`, 0)
    end

    self._volume = math.clamp(volume, 0, 1)

    local sound = self._sound
    local current = self._current
    if sound ~= nil and current ~= nil then
        local track = self._tracks[current]
        sound.Volume = (if track ~= nil then track.Volume or 1 else 1) * self._volume
    end

    local bridge = self._bridge
    if bridge ~= nil then
        bridge:Publish(Constants.Channels.MusicVolume, self._volume)
    end
end

function MusicSystem:Init(unrest: Types.Unrest): ()
    self._bridge = unrest.Bridge

    for _, track in DEFAULT_TRACKS do
        self:AddTrack(track)
    end

    self._maid:Add(unrest.Bridge:OnCommand(Constants.Commands.MusicPlay, function(payload: any)
        if typeof(payload) == "string" then
            self:Play(payload)
        end
    end))
    self._maid:Add(unrest.Bridge:OnCommand(Constants.Commands.MusicStop, function()
        self:Stop()
    end))
end

function MusicSystem:Start(): ()
    -- Publish the initial state so any UI that mounts later renders correctly straight away.
    local bridge = self._bridge
    if bridge ~= nil then
        bridge:Publish(Constants.Channels.NowPlaying, self._current)
        bridge:Publish(Constants.Channels.MusicVolume, self._volume)
    end
end

function MusicSystem:Stop_(): ()
end

function MusicSystem:Destroy(): ()
    self:Stop()
    self._maid:Destroy()
end

return MusicSystem
