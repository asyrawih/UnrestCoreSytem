--!strict
--[[
    Menyimpan koin tiap pemain. Sistem ini tidak tahu ada UI, dan tidak menyentuh remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Unrest.Types)

local Dompet = {
    Name = "Dompet",
    Dependencies = {} :: { string },
    _koin = {} :: { [Player]: number },
}

export type Dompet = typeof(Dompet)

function Dompet:Ambil(pemain: Player): number
    return self._koin[pemain] or 0
end

function Dompet:Set(pemain: Player, jumlah: number): ()
    self._koin[pemain] = jumlah
end

function Dompet:Init(_unrest: Types.Unrest): ()
    game:GetService("Players").PlayerAdded:Connect(function(pemain: Player)
        self:Set(pemain, 100) -- saldo awal
    end)
end

--[[
    `Start` dan `Destroy` tidak mengerjakan apa pun di sini, tapi tetap harus dituliskan.
    `Types.System` menyatakan ketiganya opsional; pemeriksa tipe Luau tidak setuju, dan
    menolak tabel yang tidak punya semuanya. Jadi ini pajak, bukan pilihan.
]]
function Dompet:Start(): () end

function Dompet:Destroy(): () end

return Dompet
