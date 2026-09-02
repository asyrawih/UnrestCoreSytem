--!strict
--[[
    Game -- ServerScriptService.Game

    The server bootstrap. Two lines, in the only order they work in:

        1. systems  registered
        2. started  Init then Start, which is where handlers appear

    There is nothing to open afterwards. The framework carries no traffic between realms, so
    the server's Bridge is the server's alone: a channel published here is read by server code
    here, and a command dispatched here is answered by a handler registered here. Nothing a
    client does can reach this script, because there is no wire for it to arrive on.

    That is worth saying plainly, because it moves a burden rather than removing one. The
    framework used to check a contract, a rate budget and a payload schema before a handler
    ran. Now a handler runs because this game's own code asked it to, so if a system needs a
    payload to be a certain shape, that system is what checks it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unrest = require(ReplicatedStorage.Unrest)

Unrest:Register(require(script.Systems.Greeter)) -- 1. register systems

Unrest:Start() -- 2. Init then Start; every handler is now registered
