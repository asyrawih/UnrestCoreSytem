--!strict
--[[
    Game / Presets

    Preset adalah bundel atribut yang dipanggil dengan satu nama dari Studio. Alih-alih
    menulis lima atribut di setiap tombol, seorang desainer menulis satu:

        UnrestPreset = "TombolUtama"

    Gunanya bukan sekadar mempersingkat ketikan. Yang dipersingkat itu efek sampingnya. Yang
    sebenarnya didapat adalah "apa itu tombol utama" diputuskan sekali, di kode yang bisa
    ditelaah, bukan diketik ulang di tiap tombol lalu perlahan melenceng satu sama lain.

    BERKAS INI BOLEH KOSONG. Framework tidak mengirim satu preset pun, dan sebuah game bisa
    berjalan penuh tanpa mendaftarkan apa pun di sini. Isi berkas ini kalau kamu mendapati
    dirimu mengetik kumpulan atribut yang sama berulang kali.

    Preset adalah nilai bawaan, bukan penimpa. Atribut yang ditulis langsung di elemen selalu
    menang atas preset, sehingga satu tombol bisa memakai preset yang sama lalu menyimpang di
    satu hal saja.

    Dan preset tidak memberi hak istimewa apa pun. `UnrestCommand` yang datang dari preset
    melewati gerbang yang sama dengan yang diketik tangan.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Presets = require(ReplicatedStorage.Unrest.Presets)

--[[
    Contoh, sengaja dikomentari. Buka komentarnya dan sesuaikan, atau hapus seluruh blok ini.

    Nama perintah dan channel di dalam sebuah preset harus yang sudah dideklarasikan di
    `Contracts.luau`, kalau tidak dispatch-nya akan ditolak gerbang seperti biasa.
]]

-- Presets.Register("TombolUtama", {
--     UnrestCommand = "Music.Play",
--     UnrestPayload = "Lobby",
-- })

--- Dikembalikan supaya kode game bisa mendaftarkan preset belakangan, misalnya preset yang
--- namanya baru diketahui saat runtime.
return Presets
