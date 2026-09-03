--!strict
--[[
    Menerima niat beli, memutuskan, lalu memberi tahu pemain yang bersangkutan.

    `Dompet` di-require langsung, bukan lewat `unrest:Get`. Dua-duanya sah, tapi require
    langsung membuat tipenya utuh tanpa cast. `Dependencies` tetap perlu: itu yang menjamin
    `Dompet:Init` selesai sebelum `Init` di sini berjalan.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Dompet = require(script.Parent.Dompet)
local Remotes = require(script.Parent.Parent.Remotes)
local Types = require(ReplicatedStorage.Unrest.Types)

local HARGA: { [string]: number } = {
    pedang = 50,
    perisai = 30,
}

local Toko = {
    Name = "Toko",
    Dependencies = { "Dompet" },
}

--- Satu-satunya jalan keluar ke sebuah pemain. Nama channel-nya sengaja sama dengan yang
--- ditulis desainer di atribut `UnrestChannel`, karena client meneruskannya apa adanya.
local function kabari(pemain: Player, channel: string, nilai: any): ()
    Remotes.Kabar:FireClient(pemain, channel, nilai)
end

local function beli(pemain: Player, barang: string): ()
    local harga = HARGA[barang]
    if harga == nil then
        kabari(pemain, "Pesan", `barang tidak dikenal: {barang}`)
        return
    end

    local punya = Dompet:Ambil(pemain)
    if punya < harga then
        kabari(pemain, "Pesan", `koin kurang, butuh {harga}`)
        return
    end

    Dompet:Set(pemain, punya - harga)
    kabari(pemain, "Koin", punya - harga)
    kabari(pemain, "Pesan", `{barang} dibeli`)
end

function Toko:Init(unrest: Types.Unrest): ()
    --[[
        Handler menerima payload langsung. Tidak ada lagi gerbang yang memeriksanya lebih
        dulu, jadi bentuknya diperiksa di sini.
    ]]
    unrest.Bridge:Handle("Toko.Beli", function(payload: any)
        if typeof(payload) ~= "table" then
            return
        end

        local pemain = payload.Pemain
        local barang = payload.Barang
        if typeof(pemain) ~= "Instance" or not pemain:IsA("Player") or typeof(barang) ~= "string" then
            return
        end

        beli(pemain, barang)
    end)
end

--[[
    `Start` dan `Destroy` tidak mengerjakan apa pun di sini, tapi tetap harus dituliskan.
    `Types.System` menyatakan ketiganya opsional; pemeriksa tipe Luau tidak setuju, dan
    menolak tabel yang tidak punya semuanya. Jadi ini pajak, bukan pilihan.
]]
function Toko:Start(): () end

function Toko:Destroy(): () end

return Toko
