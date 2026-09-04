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

    Mencetak isi `src/game-client/Vocab.luau` yang dihasilkan dari `StarterGui`: peran, grup,
    dan widget yang benar-benar ada di layar, sebagai union bertipe. Salin keluarannya ke
    berkas itu apa adanya; jangan disunting tangan, ekspor ulang.

    Plugin Studio tidak punya akses berkas, jadi menyalin adalah rute yang pasti jalan.

    PINTU MCP. `execute_luau` menjalankan kode yang sama dan menangkap keluarannya, jadi sesi
    agen bisa menulis hasilnya langsung ke disk tanpa menyalin tangan.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Vocab = require(ReplicatedStorage.Unrest.Tooling.Vocab)

print(Vocab.generate(StarterGui))
