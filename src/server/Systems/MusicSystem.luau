--!strict
--[[
    Unrest / Server / Systems / MusicSystem

    Owns the soundtrack: a named track table, the one Sound instance that plays it, and the
    master volume.

    THIS SYSTEM IS SERVER-AUTHORITATIVE. It lives in ServerScriptService and no client holds a
    reference to it. A player asks for a track by dispatching `Music.Play`, which crosses the
    gateway, is checked against its contract, and only then reaches the handler below. What
    the handler receives has already been proven to be a bounded identifier string; what it
    decides is broadcast back on the `Music.NowPlaying` channel. UI reads the channel and never
    the system.

    (The Sound instance is the one place a system creates an Instance -- SoundService is state,
    not view. It is never parented into a GUI and never handed out.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Maid = require(ReplicatedStorage.Unrest.Util.Maid)
local Signal = require(ReplicatedStorage.Unrest.Util.Signal)
local Types = require(ReplicatedStorage.Unrest.Types)

local DEFAULT_TRACKS: { Types.Track } = {
    { Name = "Lobby", SoundId = "rbxassetid://1837879082", Volume = 0.35, Looped = true },
    { Name = "Dancefloor", SoundId = "rbxassetid://1836774112", Volume = 0.5, Looped = true },
}

local MusicSystem = {
    Name = "MusicSystem",
    Dependencies = {} :: { string },

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
local function ensureSound(self: typeof(MusicSystem)): Sound
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
        --[[
            An unknown track is a normal outcome, not an attack: the payload was a valid
            identifier, it simply names nothing. The caller gets `false`, and the reason stays
            in the server log -- a client must not be able to enumerate the track table by
            watching which names come back differently.
        ]]
        warn(`[Unrest.MusicSystem] no track named "{name}". Known tracks: {trackNames(self)}.`)
        return false
    end

    local sound = ensureSound(self)
    sound.SoundId = track.SoundId
    sound.Looped = if track.Looped == nil then true else track.Looped
    sound.Volume = (track.Volume or 1) * self._volume
    sound:Play()

    self._current = name
    self.NowPlayingChanged:Fire(name)
    self:_publish()

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
    self:_publish()
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

    self:_publish()
end

--- Both music channels are `Public`: what is playing is shared by definition, so it is the
--- one place in this framework where a broadcast is the correct visibility.
function MusicSystem:_publish(): ()
    local bridge = self._bridge
    if bridge == nil then
        return
    end
    bridge:Publish(Constants.Channels.NowPlaying, self._current)
    bridge:Publish(Constants.Channels.MusicVolume, self._volume)
end

function MusicSystem:Init(unrest: Types.Unrest): ()
    local bridge = unrest.Bridge
    self._bridge = bridge

    for _, track in DEFAULT_TRACKS do
        self:AddTrack(track)
    end

    --[[
        Handlers, not method calls. Every one of these is reached only through the Bridge, so
        the same registration serves a local server dispatch and a remote request from a
        client -- and the remote one has already been through the gate by the time it lands.

        `payload` needs no defensive type check: the contract declares an identifier string and
        the gateway validated it. That is the whole point of putting the schema in the contract.
    ]]
    self._maid:Add(
        bridge:Handle(Constants.Commands.MusicPlay, function(_source: Types.CommandSource, payload: any): boolean
            return self:Play(payload :: string)
        end)
    )

    self._maid:Add(bridge:Handle(Constants.Commands.MusicStop, function(): ()
        self:Stop()
    end))

    self._maid:Add(
        bridge:Handle(Constants.Commands.MusicSetVolume, function(_source: Types.CommandSource, payload: any): ()
            self:SetVolume(payload :: number)
        end)
    )

    --[[
        A server-only command, and it is registered exactly like the others. Nothing about this
        handler is defensive, because nothing about it needs to be: no client can reach it, and
        the reason is one missing `AllowClient` line in the contract table.
    ]]
    self._maid:Add(bridge:Handle(Constants.Commands.MusicForceStopAll, function(): ()
        self:Stop()
    end))
end

function MusicSystem:Start(): ()
    -- Publish the initial state so a client that joins later renders correctly straight away.
    self:_publish()
end

function MusicSystem:Destroy(): ()
    self:Stop()
    self._maid:Destroy()
end

return MusicSystem
