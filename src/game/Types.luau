--!strict
--[[
    Game / Types

    The shapes of this game's systems.

    These used to live in the framework's `Types.luau`, which meant the framework shipped
    knowing what a track and an emote are. It does not need to: `Types.System` is the only
    thing `Core` reads, and everything below is `System` plus the verbs this game happens to
    want. The framework's type module keeps the lifecycle, the adapters and the net types --
    the things any game would need -- and this file keeps the rest.

    The direction is the whole rule: game code requires the framework, never the other way.
    So this module imports `System` and `Signal` from `ReplicatedStorage.Unrest.Types`, and
    nothing under `src/shared` may ever import this one.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnrestTypes = require(ReplicatedStorage.Unrest.Types)

type Signal<T...> = UnrestTypes.Signal<T...>
type System = UnrestTypes.System

--------------------------------------------------------------------------------
-- Music
--------------------------------------------------------------------------------

export type Track = {
    Name: string,
    SoundId: string,
    Volume: number?,
    Looped: boolean?,
}

export type MusicSystem = System & {
    NowPlayingChanged: Signal<string?>,
    AddTrack: (self: MusicSystem, track: Track) -> (),
    Play: (self: MusicSystem, name: string) -> boolean,
    Stop: (self: MusicSystem) -> (),
    SetVolume: (self: MusicSystem, volume: number) -> (),
    GetCurrent: (self: MusicSystem) -> string?,
    List: (self: MusicSystem) -> { string },
}

--------------------------------------------------------------------------------
-- Avatars
--------------------------------------------------------------------------------

export type AvatarContext = System & {
    CharacterAdded: Signal<Player, Model>,
    CharacterRemoving: Signal<Player, Model>,
    Resolve: (self: AvatarContext, player: Player?) -> Player?,
    GetCharacter: (self: AvatarContext, player: Player?) -> Model?,
    GetHumanoid: (self: AvatarContext, player: Player?) -> Humanoid?,
    GetAnimator: (self: AvatarContext, player: Player?) -> Animator?,
}

--------------------------------------------------------------------------------
-- Dances
--------------------------------------------------------------------------------

export type DanceSystem = System & {
    DanceChanged: Signal<Player, string?>,
    AddDance: (self: DanceSystem, name: string, animationId: string) -> (),
    Play: (self: DanceSystem, name: string, player: Player?) -> boolean,
    Stop: (self: DanceSystem, player: Player?) -> (),
    GetCurrent: (self: DanceSystem, player: Player?) -> string?,
    List: (self: DanceSystem) -> { string },
}

--------------------------------------------------------------------------------
-- Plugins
--------------------------------------------------------------------------------

export type PluginExtended = System & {
    PluginAdded: Signal<System>,
    Register: (self: PluginExtended, definition: System) -> System,
    --- Requires every ModuleScript child of `container` and registers what they return.
    LoadFromFolder: (self: PluginExtended, container: Instance) -> { System },
    List: (self: PluginExtended) -> { string },
}

-- Type-only module: the returned table is intentionally empty.
return table.freeze({})
