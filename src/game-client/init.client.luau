--!strict
--[[
    Game -- StarterPlayer.StarterPlayerScripts.Game

    The client bootstrap. It builds no UI: the framework adopts what a designer made in Studio,
    and tagging an element `Unrest` is the whole opt-in. This file only says what a tagged
    element means.

    The query below binds live. Nothing tagged yet is not an error and not a special case --
    the handle stays empty and picks up a `TestButton` the moment one is tagged, which is what
    makes building the UI in Studio while the game runs work at all.

    There is nothing to declare before starting. The Bridge is a local bus, so the channels
    and commands this file uses are agreed between this script and the rest of the client, and
    nowhere else. The only thing that ever needs saying up front is a preset:

        local Presets = require(ReplicatedStorage.Unrest.Presets)
        Presets.Register("PrimaryAction", { UnrestCommand = "Music.Play", UnrestPayload = "Lobby" })

    Register above `:Start()`. An element adopted at Start resolves its `UnrestPreset` there
    and then, and a bundle registered afterwards is one it has already warned about.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

--- `Role` reads the element's `UnrestRole` attribute, falling back to its `Name`.
unrest:Query({ Tag = unrest.Tag, Role = "TestButton" }, {
    Active = function()
        print("Test")
    end,
})
