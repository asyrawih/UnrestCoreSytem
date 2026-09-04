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
    Lint Unrest -- tempel di Command Bar Studio, lalu Enter.

    Menjalankan setiap aturan di `Tooling/Lint` terhadap `StarterGui` dan mencetak temuannya,
    satu baris per temuan, Error dulu. Tidak menyunting apa pun: `Fix` milik sebuah temuan
    hanya dijalankan kalau ada yang memanggilnya, dan di sini tidak ada.

    Mode edit, tanpa Play. `Tooling/Lint` murni dan tidak pernah meng-`require` `Widgets/init`
    atau `Elements/init`, jadi berkas ini juga jalan di plugin nanti.

    PINTU MCP. `execute_luau` bisa menjalankan kode yang sama persis dan menangkap
    keluarannya, jadi sesi agen tidak perlu plugin terpasang untuk melihat hasil lint.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Lint = require(ReplicatedStorage.Unrest.Tooling.Lint)

local findings = Lint.check(StarterGui)
if #findings > 0 then
    print(Lint.format(findings))
end

local counts = { Error = 0, Warning = 0, Info = 0 }
for _, finding in findings do
    counts[finding.Level] += 1
end

print(
    string.format(
        "[LintUnrest] %d temuan: %d Error, %d Warning, %d Info.",
        #findings,
        counts.Error,
        counts.Warning,
        counts.Info
    )
)
