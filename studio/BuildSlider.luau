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
    Build Slider -- tempel di Command Bar Studio, lalu Enter.

    Membuat StarterGui.SliderDemo lengkap dengan tag dan atributnya. Aman diulang: kalau sudah
    ada, yang lama dihapus dulu.

    Framework belum punya control Slider, jadi pembagiannya begini. Tampilan diurus atribut:
    label, isi batang, dan posisi knob semuanya dilukis dari channel. Geserannya diurus kode
    client, karena `Release` pada knob tidak menyala setelah penunjuk keluar darinya.
]]

local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")

local lama = StarterGui:FindFirstChild("SliderDemo")
if lama then
    lama:Destroy()
end

local screen = Instance.new("ScreenGui")
screen.Name = "SliderDemo"
screen.ResetOnSpawn = false
-- Penting untuk penggeseran: dengan ini AbsolutePosition sejajar dengan input.Position mentah,
-- jadi tidak ada selisih 36 piksel yang muncul kadang-kadang saja.
screen.IgnoreGuiInset = true

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(360, 120)
panel.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
panel.BorderSizePixel = 0
panel.Parent = screen

--- SATU-SATUNYA TAG. Menurun ke semua GuiObject di bawahnya.
CollectionService:AddTag(panel, "Unrest")

local judul = Instance.new("TextLabel")
judul.Name = "Judul"
judul.Position = UDim2.fromOffset(20, 16)
judul.Size = UDim2.new(1, -40, 0, 24)
judul.BackgroundTransparency = 1
judul.TextColor3 = Color3.fromRGB(240, 240, 245)
judul.TextXAlignment = Enum.TextXAlignment.Left
judul.Text = "Volume: 0%"
judul.Parent = panel
-- Menampilkan angka. Tanpa UnrestBind karena Text memang properti nilai bawaan TextLabel.
judul:SetAttribute("UnrestChannel", "Volume")
judul:SetAttribute("UnrestFormat", "Volume: {value}%")

local track = Instance.new("Frame")
track.Name = "Track"
track.Position = UDim2.fromOffset(20, 60)
track.Size = UDim2.new(1, -40, 0, 10)
track.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
track.BorderSizePixel = 0
track.Parent = panel
--- Diikat kode lewat Role, bukan lewat nama, supaya boleh diganti nama kapan saja.
track:SetAttribute("UnrestRole", "SliderTrack")

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(124, 58, 237)
fill.BorderSizePixel = 0
fill.Parent = track
-- Panjang batang dilukis framework dari channel. Nilainya UDim2, jadi tanpa UnrestFormat.
fill:SetAttribute("UnrestChannel", "VolumeFill")
fill:SetAttribute("UnrestBind", "Size")

local knob = Instance.new("TextButton")
knob.Name = "Knob"
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.fromScale(0, 0.5)
knob.Size = UDim2.fromOffset(22, 22)
knob.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
knob.Text = ""
knob.AutoButtonColor = false
knob.BorderSizePixel = 0
knob.Parent = track
knob:SetAttribute("UnrestRole", "SliderKnob")
-- Posisi knob juga dilukis framework dari channel.
knob:SetAttribute("UnrestChannel", "VolumeKnob")
knob:SetAttribute("UnrestBind", "Position")

local sudut = Instance.new("UICorner")
sudut.CornerRadius = UDim.new(1, 0)
sudut.Parent = knob

screen.Parent = StarterGui

print("[BuildSlider] StarterGui.SliderDemo dibuat. 1 tag di Panel, 6 atribut.")
