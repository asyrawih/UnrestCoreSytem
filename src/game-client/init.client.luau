--!strict
--[[
    Game -- StarterPlayer.StarterPlayerScripts.Game

    The client bootstrap. It builds no UI: the framework adopts what a designer made in Studio,
    and tagging an element `Unrest` is the whole opt-in. This file only says what a tagged
    element means.

    The query below binds live. Nothing tagged yet is not an error and not a special case --
    the handle stays empty and picks up a `PlayButton` the moment one is tagged, which is what
    makes building the UI in Studio while the game runs work at all.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

--- `Role` reads the element's `UnrestRole` attribute, falling back to its `Name`.
unrest:Query({ Tag = unrest.Tag, Role = "PlayButton" }, {
    Active = function()
        print("Test")
    end,
})
