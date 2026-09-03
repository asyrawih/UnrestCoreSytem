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
    Build Toggle -- tempel di Command Bar Studio.

    Dua switch mandiri, dibedakan lewat `UnrestGroup`. Aman diulang.
]]

local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")

local lama = StarterGui:FindFirstChild("ToggleDemo")
if lama then
    lama:Destroy()
end

local screen = Instance.new("ScreenGui")
screen.Name = "ToggleDemo"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true

local function buat(nama: string, y: number)
    local akar = Instance.new("Frame")
    akar.Name = nama
    akar.Position = UDim2.fromOffset(460, y)
    akar.Size = UDim2.fromOffset(260, 60)
    akar.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
    akar.BorderSizePixel = 0
    akar.Parent = screen

    CollectionService:AddTag(akar, "Unrest")
    akar:SetAttribute("UnrestGroup", nama)

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Position = UDim2.fromOffset(14, 8)
    label.Size = UDim2.new(1, -28, 0, 18)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(240, 240, 245)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = nama
    label.Parent = akar
    label:SetAttribute("UnrestRole", "ToggleLabel")

    local button = Instance.new("TextButton")
    button.Name = "Button"
    button.Position = UDim2.fromOffset(14, 32)
    button.Size = UDim2.fromOffset(56, 20)
    button.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
    button.Text = ""
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.Parent = akar
    button:SetAttribute("UnrestRole", "ToggleButton")

    local sudut = Instance.new("UICorner")
    sudut.CornerRadius = UDim.new(1, 0)
    sudut.Parent = button

    local knob = Instance.new("Frame")
    knob.Name = "Knob"
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.fromScale(0, 0.5)
    knob.Size = UDim2.fromOffset(18, 18)
    knob.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
    knob.BorderSizePixel = 0
    knob.Parent = button
    knob:SetAttribute("UnrestRole", "ToggleKnob")

    local bulat = Instance.new("UICorner")
    bulat.CornerRadius = UDim.new(1, 0)
    bulat.Parent = knob
end

buat("Fullscreen", 40)
buat("Notifikasi", 130)

screen.Parent = StarterGui
print("[BuildToggle] dua switch dibuat.")
