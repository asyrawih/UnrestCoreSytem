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
    The shop, client side.

    Two directions, both crossing the local Bridge:

      * down -- a packet from the server becomes a channel value, and tagged labels paint
        themselves from it;
      * up   -- a tagged button sends a packet, and the server decides what it means.

    The channel names here must match the `UnrestChannel` a designer typed in Studio exactly.
    That string is the only thing connecting a packet to the label that displays it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameNet = require(ReplicatedStorage:WaitForChild("GameNet"))
local Types = require(ReplicatedStorage.Unrest.Types)

return function(unrest: Types.Unrest): ()
    local bridge = unrest.Bridge

    --[[
        One packet, one channel. Channel values are retained, so news arriving before the
        screen has replicated is not lost: a label adopted later paints the last value on its
        first frame.
    ]]
    GameNet.packets.Koin.listen(function(data)
        bridge:Publish("Koin", data.Nilai)
    end)

    GameNet.packets.Pesan.listen(function(data)
        bridge:Publish("Pesan", data.Teks)
    end)

    --[[
        One query covers every buy button, however many there are. What separates them is the
        `UnrestPayload` a designer typed, and `element` here is the instance actually pressed.
    ]]
    unrest:Query({ Tag = unrest.Tag, Selector = "GuiButton", Role = "Beli" }, {
        Active = function(element: Instance)
            local item = element:GetAttribute("UnrestPayload")
            --[[
                `GetAttribute` returns nil when the attribute is absent, not an empty string.
                The `Beli` packet can only carry a string, and anything else breaks the whole
                outgoing batch, so it is dropped here.
            ]]
            if typeof(item) ~= "string" or item == "" then
                warn(`[Shop] {element:GetFullName()} has no string UnrestPayload.`)
                return
            end
            GameNet.packets.Beli.send({ Barang = item })
        end,

        Hover = function(element: Instance)
            (element :: GuiObject).BackgroundTransparency = 0.2
        end,

        Unhover = function(element: Instance)
            (element :: GuiObject).BackgroundTransparency = 0
        end,
    })
end
