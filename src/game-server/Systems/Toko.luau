--!strict
--[[
    Takes a purchase intent, decides, then tells the player who asked.

    `Dompet` is required directly rather than fetched with `unrest:Get`. Both are valid, but
    requiring it keeps the type intact without a cast. `Dependencies` is still needed: that is
    what guarantees `Dompet:Init` has finished before this `Init` runs.

    This system never names a channel. There used to be one generic remote carrying a channel
    name on every message; now the packet itself carries the meaning, and packet-to-channel
    mapping happens once, on the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dompet = require(script.Parent.Dompet)
local GameNet = require(ReplicatedStorage.GameNet)
local Types = require(ReplicatedStorage.Unrest.Types)

local PRICES: { [string]: number } = {
    pedang = 50,
    perisai = 30,
    TopUp = 100,
}

local Toko = {
    Name = "Toko",
    Dependencies = { "Dompet" },
}

local function buy(player: Player, item: string): ()
    local price = PRICES[item]
    if price == nil then
        GameNet.packets.Pesan.sendTo({ Teks = `unknown item: {item}` }, player)
        return
    end

    local balance = Dompet:Balance(player)

    if item == "TopUp" then
        Dompet:Set(player, balance + price)
        GameNet.packets.Koin.sendTo({ Nilai = Dompet:Balance(player) }, player)
        GameNet.packets.Pesan.sendTo({ Teks = `{item} bought` }, player)
        return
    end

    if balance < price then
        GameNet.packets.Pesan.sendTo({ Teks = `not enough coins, need {price}` }, player)
        return
    end

    --- `Koin` is a `uint32`, so this difference must not go negative. The branch above is what
    --- guarantees it, which is why the subtraction cannot move above that check.
    Dompet:Set(player, balance - price)
    GameNet.packets.Koin.sendTo({ Nilai = balance - price }, player)
    GameNet.packets.Pesan.sendTo({ Teks = `{item} bought` }, player)
end

function Toko:Init(unrest: Types.Unrest): ()
    --[[
        The handler receives the payload directly. No gateway checks it first any more, so its
        shape is checked here.

        There used to be a second handler on `Toko.Topup` calling the same `buy`, while the
        entry point dispatched both names for every packet. One click therefore bought twice.
        The second name is gone, and TopUp is now just another item in `PRICES`.
    ]]
    unrest.Bridge:Handle("Toko.Beli", function(payload: any)
        if typeof(payload) ~= "table" then
            return
        end

        local player = payload.Player
        local item = payload.Item
        if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(item) ~= "string" then
            return
        end

        buy(player, item)
    end)
end

function Toko:Start(): () end

function Toko:Destroy(): () end

return Toko
