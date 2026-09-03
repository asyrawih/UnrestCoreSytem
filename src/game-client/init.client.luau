--!strict
--[[
    Game -- StarterPlayer.StarterPlayerScripts.Game

    Client tidak membuat UI. Layarnya dibuat tangan di Studio, dan tag `Unrest` adalah seluruh
    cara ikut sertanya. Berkas ini cuma mengatakan dua hal: apa arti nilai yang datang dari
    server, dan apa arti sebuah tombol ditekan.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unrest = require(ReplicatedStorage.Unrest)

local Kabar = ReplicatedStorage:WaitForChild("Kabar") :: RemoteEvent
local Niat = ReplicatedStorage:WaitForChild("Niat") :: RemoteEvent

local unrest = Unrest:Start()

--[[
    Turun. Tiga baris ini mengurus setiap label bertag di seluruh game: server menyebut nama
    channel, dan setiap elemen yang mendengarkan nama itu ikut berubah. Menambah label baru
    nanti tidak menyentuh berkas ini sama sekali, cukup dua atribut di Studio.

    Nilainya tertahan, jadi kabar yang tiba sebelum layarnya direplikasi tidak hilang: label
    yang diadopsi belakangan langsung melukis nilai terakhir.
]]
Kabar.OnClientEvent:Connect(function(channel: any, nilai: any)
    if typeof(channel) ~= "string" then
        return
    end
    unrest.Bridge:Publish(channel, nilai)
end)

--[[
    Naik. Satu query mengurus semua tombol beli, berapa pun jumlahnya. Yang membedakan mereka
    adalah `UnrestPayload` yang diketik desainer, dan `elemen` di sini adalah instance yang
    benar-benar ditekan.

    Query ini mengikat hidup: tombol yang baru ditandai saat game berjalan langsung tertangkap.
]]
unrest:Query({ Tag = unrest.Tag, Role = "Beli" }, {
    Active = function(elemen: Instance)
        Niat:FireServer(elemen:GetAttribute("UnrestPayload"))
    end,

    Hover = function(elemen: Instance)
        (elemen :: GuiObject).BackgroundTransparency = 0.2
    end,

    Unhover = function(elemen: Instance)
        (elemen :: GuiObject).BackgroundTransparency = 0
    end,
})
