--!strict
--[[
    Game -- StarterPlayer.StarterPlayerScripts.Game

    The client bootstrap. It does two things: start the framework, then load the features.

    There is deliberately no logic here beyond wiring. Each feature lives in its own file and
    takes `unrest` as its first argument, so adding one means adding a file and a line rather
    than growing this one.

    Load order does not matter. Every feature binds through `Unrest:Query`, and those bind
    live: an element tagged later, even while the game is running, is still picked up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

require(script.Shop)(unrest)

--[[
    What each slider's value means is decided here, per `UnrestGroup`, not inside the slider.

    `OnChange` fires on every move, so it belongs to anything the player should feel while
    dragging. `OnCommit` fires once on release, and belongs to anything that costs something.

    A slider with no entry here still paints itself and still publishes `Volume.<group>`.
]]
require(script.Slider)(unrest, {
    Musik = {
        OnChange = function(value: number)
            print(`musik ke {value}`)
        end,
    },

    Raise = {
        OnChange = function(value: number)
            print(`musik ke {value}`)
        end,
    },

    Efek = {
        OnCommit = function(value: number)
            print(`efek disetel ke {value}`)
        end,
    },

    Bloom = {
        OnCommit = function(value: number)
            print(`efek disetel ke {value}`)
        end,
    },
})

--[[
    Switches use the same shape as sliders: actions keyed by `UnrestGroup`. There is no
    `OnCommit` here because a press is already the settled value, and `Initial` exists because
    a switch that assumed off would fight whatever the game already knows.
]]
require(script.Toggle)(unrest, {
    Fullscreen = {
        Initial = true,
        OnChange = function(value: boolean)
            print(`fullscreen {if value then "on" else "off"}`)
        end,
    },

    Notifikasi = {
        OnChange = function(value: boolean)
            print(`notifikasi {if value then "on" else "off"}`)
        end,
    },
})
