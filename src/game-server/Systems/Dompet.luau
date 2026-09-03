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
    Holds each player's coins, and sends the opening balance the moment they join.

    This system knows nothing about UI. It sends a `Koin` packet, and the client is what
    decides that packet means the Bridge channel called "Koin". An earlier version put the
    channel name on the wire in lower case, `"koin"`, which never matched the `UnrestChannel`
    of `Koin` typed in Studio, so the opening balance was never painted. Typed packets remove
    that whole class of mistake: the channel name no longer travels.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameNet = require(ReplicatedStorage.GameNet)
local Types = require(ReplicatedStorage.Unrest.Types)

local STARTING_BALANCE = 100

local Dompet = {
    Name = "Dompet",
    Dependencies = {} :: { string },
    _coins = {} :: { [Player]: number },
}

export type Dompet = typeof(Dompet)

function Dompet:Balance(player: Player): number
    return self._coins[player] or 0
end

function Dompet:Set(player: Player, amount: number): ()
    self._coins[player] = amount
end

function Dompet:Init(_unrest: Types.Unrest): ()
    game:GetService("Players").PlayerAdded:Connect(function(player: Player)
        self:Set(player, STARTING_BALANCE)
        GameNet.packets.Koin.sendTo({ Nilai = STARTING_BALANCE }, player)
    end)
end

--[[
    `Start` and `Destroy` do nothing here but still have to be written out. `Types.System`
    declares all three optional; the Luau checker disagrees and refuses a table missing any of
    them. This is a tax, not a choice.
]]
function Dompet:Start(): () end

function Dompet:Destroy(): () end

return Dompet
