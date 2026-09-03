--!strict
--[[
    Game -- ServerScriptService.Game

    Tiga langkah, dan urutannya bermakna: sistem didaftarkan, lalu `Start` menjalankan `Init`
    dan `Start` tiap sistem (di situlah handler terpasang), baru remote disambungkan. Menyambung
    remote lebih dulu berarti ada jendela di mana permintaan pemain tiba sebelum ada yang
    menjawabnya.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Remotes)
local Unrest = require(ReplicatedStorage.Unrest)

Unrest:Register(require(script.Systems.Dompet))
Unrest:Register(require(script.Systems.Toko))

local unrest = Unrest:Start()

--[[
    Batas tepercaya terakhir. `pemain` datang dari Roblox sebagai argumen pertama, tidak pernah
    dari isi pesan, dan itu satu-satunya sumber identitas yang benar.
]]
Remotes.Niat.OnServerEvent:Connect(function(pemain: Player, barang: any)
    if typeof(barang) ~= "string" then
        return
    end
    unrest.Bridge:Dispatch("Toko.Beli", { Pemain = pemain, Barang = barang })
end)
