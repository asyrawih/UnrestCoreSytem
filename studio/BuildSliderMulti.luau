--!nocheck
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
    Dua slider yang berdiri sendiri. Tempel di Command Bar Studio.

    Kuncinya `UnrestGroup` di akar tiap slider. Group itu diwariskan, jadi Track dan Knob di
    bawahnya ikut memilikinya tanpa diketik ulang. Itulah identitas yang membedakan satu
    slider dari yang lain.

    Di akar juga ada `UnrestChannel`, dan itulah yang membuat slider ini hidup tanpa satu
    baris Luau pun: nilainya diambil dari channel saat mount, diterbitkan sekali saat geseran
    dilepas, dan selama jari masih menempel nilai yang datang dari channel diabaikan.
    Menduplikasi slider berarti mengganti DUA atribut di akar, Group dan Channel-nya.
]]

local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")

local lama = StarterGui:FindFirstChild("SliderMulti")
if lama then
    lama:Destroy()
end

local screen = Instance.new("ScreenGui")
screen.Name = "SliderMulti"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true

local function buatSlider(nama: string, y: number)
    local akar = Instance.new("Frame")
    akar.Name = nama
    akar.Position = UDim2.fromOffset(40, y)
    akar.Size = UDim2.fromOffset(360, 70)
    akar.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
    akar.BorderSizePixel = 0
    akar.Parent = screen

    --- SATU tag, dan atribut identitasnya. Cuma Group-nya yang berubah saat menduplikasi.
    CollectionService:AddTag(akar, "Unrest")
    akar:SetAttribute("UnrestGroup", nama)
    --- Akarnya menyebut skema yang dimainkan grup ini. Dibaca `Widgets:Report()` dan resep
    --- `Each({ Widget = "Slider" })`; tidak diwariskan, jadi tempatnya memang di sini.
    akar:SetAttribute("UnrestWidget", "Slider")
    --[[
        Dan ke mana nilainya pergi. Karena akarnya ber-`UnrestWidget`, channel ini milik
        control-nya, bukan milik Frame ini: `Elements` tidak menyentuhnya, `Widgets` yang
        berlangganan dan menerbitkan sekali saat geseran dilepas. Ini satu-satunya baris yang
        membuat slider ini bekerja -- tidak ada Luau sama sekali di sisi game.
    ]]
    akar:SetAttribute("UnrestChannel", "Volume." .. nama)

    local judul = Instance.new("TextLabel")
    judul.Name = "Judul"
    judul.Position = UDim2.fromOffset(14, 8)
    judul.Size = UDim2.new(1, -28, 0, 20)
    judul.BackgroundTransparency = 1
    judul.TextColor3 = Color3.fromRGB(240, 240, 245)
    judul.TextXAlignment = Enum.TextXAlignment.Left
    judul.Text = nama
    judul.Parent = akar
    judul:SetAttribute("UnrestRole", "SliderLabel")

    local track = Instance.new("Frame")
    track.Name = "Track"
    track.Position = UDim2.fromOffset(14, 40)
    track.Size = UDim2.new(1, -28, 0, 10)
    track.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
    track.BorderSizePixel = 0
    track.Parent = akar
    track:SetAttribute("UnrestRole", "SliderTrack")

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = Color3.fromRGB(124, 58, 237)
    fill.BorderSizePixel = 0
    fill.Parent = track
    fill:SetAttribute("UnrestRole", "SliderFill")

    local knob = Instance.new("TextButton")
    knob.Name = "Knob"
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.fromScale(0, 0.5)
    knob.Size = UDim2.fromOffset(20, 20)
    knob.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
    knob.Text = ""
    knob.AutoButtonColor = false
    knob.BorderSizePixel = 0
    knob.Parent = track
    knob:SetAttribute("UnrestRole", "SliderKnob")

    local sudut = Instance.new("UICorner")
    sudut.CornerRadius = UDim.new(1, 0)
    sudut.Parent = knob
end

buatSlider("Musik", 40)
buatSlider("Efek", 130)

screen.Parent = StarterGui
print("[BuildSliderMulti] dua slider dibuat, dibedakan lewat UnrestGroup.")
