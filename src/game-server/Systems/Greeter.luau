--!strict
--[[
    Game / Systems / Greeter

    The smallest system that is still a whole one: a name, its dependencies, the two lifecycle
    hooks, one handler for a command and one publish to a channel.

    It keeps no Sound and plays no audio -- it remembers which track was asked for and says so.
    Swapping in a real MusicSystem is a change to this file and to nothing else.

    THE NAMES ARE LOCAL, and that is not laziness. A command name is an agreement between the
    code that dispatches it and the code that handles it, and both of those live in this realm:
    the Bridge does not cross the client/server line. Spelling `Music.Play` in a shared module
    would suggest the client's copy of that string means something here. It does not.

    WHY `Bridge:Handle` IS IN `Init` AND `Bridge:Publish` IS IN `Start`. Core runs every
    system's `Init` before any system's `Start`, so registering handlers in `Init` is what
    makes "every command is answered before anything dispatches one" true for a whole set of
    systems rather than one at a time. `Start` is then free to touch state that every other
    system has already declared.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Unrest.Types)

--- UI -> Core. An intent this system answers.
local MUSIC_PLAY = "Music.Play"
--- Core -> UI. Retained state; a subscriber immediately receives the last value.
local NOW_PLAYING = "Music.NowPlaying"

--- `Types.System` plus this system's own state. Written here rather than in a shared module
--- for the same reason the framework does not know what a track is: nobody else needs the shape.
export type Greeter = Types.System & {
    --- The track the server last accepted, or nil for silence.
    Current: string?,
    Bridge: Types.Bridge,
}

local Greeter = {
    Name = "Greeter",
    --- Declared even though it is empty: Core matches the shape structurally.
    Dependencies = {} :: { string },
    Current = nil :: string?,
    --- Filled by `Init`, which Core always runs before `Start`.
    Bridge = (nil :: any) :: Types.Bridge,
}

function Greeter:Init(unrest: Types.Unrest): ()
    self.Bridge = unrest.Bridge

    --[[
        Nothing checked `payload` on the way in. There is no gateway left to check it against,
        because there is no caller left that this game did not write: a dispatch comes from
        game code, or from an element's `UnrestCommand` attribute that a designer typed. So
        the handler is what decides what it will accept, and a bad name is a bug in this place
        file rather than a message from somewhere hostile.
    ]]
    unrest.Bridge:Handle(MUSIC_PLAY, function(payload: any): ()
        if typeof(payload) ~= "string" then
            warn(`[Greeter] {MUSIC_PLAY} wants a track name, got {typeof(payload)}. Ignored.`)
            return
        end

        self.Current = payload
        self.Bridge:Publish(NOW_PLAYING, self.Current)
    end)
end

function Greeter:Start(): ()
    --- Retained state: publishing the opening value means a UI that binds later still gets one.
    self.Bridge:Publish(NOW_PLAYING, self.Current)
end

return (Greeter :: any) :: Greeter
