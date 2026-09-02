--!strict
--[[
    Game / Systems / Greeter

    The smallest system that is still a whole one: a name, its dependencies, the two lifecycle
    hooks, one handler for a declared command and one publish to a declared channel.

    It keeps no Sound and plays no audio -- it remembers which track was asked for and says so.
    Swapping in a real MusicSystem is a change to this file and to nothing else, because the
    contract is what the client and the gateway agreed on, not this table.

    WHY `Bridge:Handle` IS IN `Init` AND `Bridge:Publish` IS IN `Start`. Core runs every
    system's `Init` before any system's `Start`, so registering handlers in `Init` is what
    makes "every command is answered before the gateway opens" true for a whole set of systems
    rather than one at a time. `Start` is then free to touch state that every other system has
    already declared.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = require(ReplicatedStorage.Game)
local Types = require(ReplicatedStorage.Unrest.Types)

--- `Types.System` plus this system's own state. Written here rather than in `Game/Types` for
--- the same reason the framework does not know what a track is: nobody else needs the shape.
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
        The handler runs only after the gateway has checked the contract, the rate budget, the
        payload schema and the Authorize hook, so `payload` here is already a track name that
        satisfies `Contracts`' IDENTIFIER spec. `source.Remote` says whether this crossed the
        wire; nothing below needs to care, which is the point of the gate being elsewhere.
    ]]
    unrest.Bridge:Handle(Game.Commands.MusicPlay, function(_source: Types.CommandSource, payload: any): boolean
        self.Current = payload :: string
        self.Bridge:Publish(Game.Channels.NowPlaying, self.Current)
        return true
    end)
end

function Greeter:Start(): ()
    --- Retained state: publishing the opening value means a UI that binds later still gets one.
    self.Bridge:Publish(Game.Channels.NowPlaying, self.Current)
end

return (Greeter :: any) :: Greeter
