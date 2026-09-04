--!strict
--[[
                     ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
  _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
/==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
|==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
|==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
|==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
|==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
|==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
`-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`

    https://discord.gg/MZYTABSSfb
]]

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

local Manifest = require(script.Manifest)
local Presets = require(ReplicatedStorage.Unrest.Presets)
local Schemas = require(ReplicatedStorage.Unrest.Widgets.Schemas)
local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

--[[
    The manifest, made real.

    `Manifest.luau` is pure data so that the Studio tooling can read it in edit mode, where
    nothing has run. This loop is the other reader: it turns the same table into registrations,
    before any feature loads, so a preset or a schema a feature names is already declared by
    the time the screen is adopted.
]]
for name, bundle in Manifest.Presets do
    Presets.Register(name, bundle)
end
for _, schema in Manifest.Widgets do
    Schemas.Register(schema)
end

require(script.ServerList)(unrest)
