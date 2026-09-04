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
    Export Vocab -- tempel di Command Bar Studio, lalu Enter.

    Menghasilkan isi `src/game-client/Vocab.luau` dari `StarterGui`: peran, grup, dan widget
    yang benar-benar ada di layar, sebagai union bertipe.

    Kalau ada ModuleScript bertag `UnrestVocab`, isinya langsung ditulis ke sana dan yang
    dicetak cuma satu baris status. Dengan two-way sync menyala di plugin Rojo, berkasnya di
    disk ikut berubah beberapa detik kemudian; kalau mati, perubahannya menunggu di penampil
    Changes milik Rojo.

    Tanpa modul bertag, teksnya dicetak apa adanya -- salin ke berkas itu tanpa disunting.

    PINTU MCP. `execute_luau` menjalankan kode yang sama dan menangkap keluarannya, jadi sesi
    agen bisa memicu penulisan atau mengambil teksnya sendiri.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Vocab = require(ReplicatedStorage.Unrest.Tooling.Vocab)

local source = Vocab.generate(StarterGui)
local target = Vocab.target()

if target == nil then
    print(source)
else
    local changed = Vocab.write(target, source)
    if changed then
        print(`[Vocab] ditulis {#source} bita ke {target:GetFullName()}`)
    else
        print(`[Vocab] tidak ada perubahan; {target:GetFullName()} sudah mutakhir`)
    end
end
