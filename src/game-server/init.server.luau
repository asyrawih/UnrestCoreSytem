--!strict
--[[
    Game -- ServerScriptService.Game

    Three steps, and the order carries meaning: systems are registered, then `Start` runs every
    system's `Init` and `Start` (which is where handlers appear), and only then is the packet
    listener attached. Attaching it first would leave a window where a player's request arrives
    before anything can answer it.

    There is no `Remotes.luau` any more. What used to be two `RemoteEvent`s created here is now
    three packets in `ReplicatedStorage.GameNet`, required as-is by both realms. The framework
    still knows nothing about any of it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameNet = require(ReplicatedStorage.GameNet)
local Unrest = require(ReplicatedStorage.Unrest)

Unrest:Register(require(script.Systems.Dompet))
Unrest:Register(require(script.Systems.Toko))

local unrest = Unrest:Start()

--[[
    The last trusted boundary. `player` is the SECOND argument ByteNet hands over, passed
    straight through from `OnServerEvent`, so Roblox is what fills it in. Identity never comes
    from the message: the `Beli` packet has no player field, and must not have one.

    The shape of `data` is still checked here because no gateway checks it first. The packet
    schema guarantees a string `Barang` if the buffer decoded at all, but decoded is not the
    same as sensible, and whether that item exists is Toko's decision.
]]
GameNet.packets.Beli.listen(function(data, player: Player?): ()
    if player == nil or typeof(data) ~= "table" or typeof(data.Barang) ~= "string" then
        return
    end
    unrest.Bridge:Dispatch("Toko.Beli", { Player = player, Item = data.Barang })
end)
