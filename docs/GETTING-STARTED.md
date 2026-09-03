````
                     ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
  _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
/==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
|==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
|==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
|==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
|==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
|==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
`-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`
````

[Discord](https://discord.gg/MZYTABSSfb)

# Panduan Memulai

Ikuti halaman ini sekali, berurutan, dan kamu akan punya satu layar yang mengirim perintah
beli ke server dan satu label yang mengikuti saldo koin. Kamu tidak perlu membaca satu baris
pun kode framework untuk menyelesaikannya.

Yang diasumsikan: kamu sudah bisa memakai Roblox Studio. Yang tidak diasumsikan: apa pun
tentang framework ini.

Satu kalimat yang menghemat banyak kebingungan nanti: **framework ini murni abstraksi UI.**
Dia tidak membuat UI, dan dia juga tidak membawa jaringan. Menyeberangkan pesan antara client
dan server adalah pekerjaan game-mu, dan halaman ini menunjukkan persis bagaimana game contoh
di repo ini melakukannya.

---

## 0. Peta tempat: kode siapa taruh di mana

Ini bagian yang paling sering bikin bingung, jadi kita selesaikan dulu sebelum menulis apa
pun. Semua yang ada di `default.project.json`, tidak ada yang lain:

| Folder di disk | Muncul di DataModel sebagai | Punya siapa |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Unrest` | **framework** — jangan disentuh |
| `src/game-net` | `ReplicatedStorage.GameNet` | **kamu** — dibaca client *dan* server |
| `src/game-server` | `ServerScriptService.Game` | **kamu** — hanya server |
| `src/game-client` | `StarterPlayer.StarterPlayerScripts.Game` | **kamu** — hanya client |
| `Packages` | `ReplicatedStorage.Packages` | Wally — hasil `wally install` |

Cara mengingatnya cuma satu baris:

> **`Unrest` itu framework. Yang berawalan `game-` itu kamu.**

Awalan `game-` bukan gaya-gayaan. Berkas framework pernah **dua kali** terhapus karena
dikira milik game, jadi sekarang kepemilikan terbaca dari nama foldernya sendiri, sebelum
kamu membuka isinya.

Arah ketergantungannya cuma satu, dan tidak pernah berbalik:

> **Kode game meng-`require` framework. Framework tidak pernah meng-`require` kode game.**
> Tidak ada satu berkas pun di `src/shared` yang boleh menyebut `ReplicatedStorage.GameNet`
> atau `ServerScriptService.Game`.

Jawaban singkat untuk "aku mulai nulis script di mana":

- **Sisi server** → `src/game-server/init.server.luau`
- **Sisi client** → `src/game-client/init.client.luau`
- **Yang dipakai keduanya** → `src/game-net/` (format kabel game ini)

---

## 1. Hidupkan Rojo dan sambungkan ke Studio

```sh
rokit install     # sekali per clone; tanpa ini shim Rokit menolak jalan
wally install     # mengisi Packages/ — game contoh memakai ByteNet
rojo serve        # menyajikan default.project.json di port 34872
```

Di Studio: **Plugins → Rojo → Connect**.

> **Satu ranjau di `bytenet-max@1.0.0`.** Versi yang terbit tidak bisa di-`require` apa
> adanya: `namespaces/namespace` dan `dataTypes/struct` sama-sama meminta
> `namespacesDependencies`, sementara berkasnya bernama `namespaceDependencies` — beda satu
> huruf. Salinan di `Packages/` ditambal tangan, dan `wally install` berikutnya akan menimpa
> tambalan itu. Kalau tiba-tiba `require(ReplicatedStorage.GameNet)` gagal setelah install,
> itu penyebabnya.

**Yang seharusnya kamu lihat** di Explorer, persis seperti tabel di bagian 0:

```
ReplicatedStorage
├── Unrest        ← framework
├── GameNet       ← punyamu, dibaca dua sisi
└── Packages      ← dependensi Wally

ServerScriptService
└── Game          ← punyamu, server

StarterPlayer/StarterPlayerScripts
└── Game          ← punyamu, client
```

**Kalau tidak muncul**, kemungkinan besar kamu menjalankan `rojo serve` dari folder lain.
Jalankan dari akar repo, tempat `default.project.json` berada.

---

## 2. Tulis bootstrap server

Buka `src/game-server/init.server.luau`. Isinya tiga langkah, dan **urutannya bermakna**:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameNet = require(ReplicatedStorage.GameNet)
local Unrest = require(ReplicatedStorage.Unrest)

Unrest:Register(require(script.Systems.Dompet))   -- 1. daftarkan sistem
Unrest:Register(require(script.Systems.Toko))

local unrest = Unrest:Start()                     -- 2. Init lalu Start

GameNet.packets.Beli.listen(function(data, player: Player?): ()   -- 3. pintu dibuka
    if player == nil or typeof(data) ~= "table" or typeof(data.Barang) ~= "string" then
        return
    end
    unrest.Bridge:Dispatch("Toko.Beli", { Player = player, Item = data.Barang })
end)
```

### Kenapa urutannya begitu

Baca dari bawah, karena baris terakhir yang menjelaskan sisanya.

**Langkah 3 adalah saat pintu dibuka.** Sebelum `listen` terpasang, paket `Beli` yang dikirim
seorang pemain tidak sampai ke mana-mana. Memasangnya **paling akhir** memberi jaminan yang
enak: permintaan paling awal yang mungkin datang pun pasti menemukan seluruh handler sudah
terpasang. Tidak ada celah waktu di mana pintunya terbuka tapi ruangannya masih kosong.

Sekarang baris-baris sebelumnya jadi masuk akal:

| Langkah | Yang terjadi | Kalau dilewat |
| --- | --- | --- |
| 1. `Unrest:Register(...)` | Sistem masuk ke registry. Belum jalan, baru terdaftar. | Sistemnya tidak pernah hidup. |
| 2. `Unrest:Start()` | `Init(unrest)` untuk semua sistem sesuai urutan dependensi, lalu `Start()` untuk semua sistem. **Di sinilah `Bridge:Handle` dipanggil.** | Tidak ada handler yang terpasang, jadi `Dispatch` masuk ke ruangan kosong — diam, tanpa galat. |
| 3. `GameNet.packets.Beli.listen(...)` | Paket dari client mulai diterima dan diterjemahkan jadi satu `Bridge:Dispatch`. | Klik pemain tidak sampai ke server sama sekali. |

Perhatikan bahwa `Bridge:Handle` biasanya dipanggil di dalam `Init` sebuah sistem. Karena
`Start()` menjalankan semua `Init` sebelum langkah 3, seluruh handler sudah pasti terdaftar
saat pintu dibuka. Itu bukan kebetulan, itu alasan urutan ini dipilih.

Dua hal lagi yang penting di `listen` itu, dan keduanya tanggung jawabmu:

* **`player` adalah argumen kedua**, diteruskan apa adanya dari `OnServerEvent`. Identitas
  datang dari Roblox, **tidak pernah dari isi pesan**. Paket `Beli` tidak punya field pemain,
  dan tidak boleh punya.
* **Bentuk `data` diperiksa di sini**, karena tidak ada lapisan lain yang memeriksanya lebih
  dulu. Framework tidak memvalidasi apa pun untukmu: `Bridge:Dispatch` mengantar payload apa
  adanya.

### Sistem paling kecil yang tetap jalan

Sebuah sistem adalah tabel biasa. Lihat `src/game-server/Systems/Toko.luau`; bentuk
terkecilnya seperti ini:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Unrest.Types)

local Toko = {
    Name = "Toko",
    Dependencies = { "Dompet" },
}

function Toko:Init(unrest: Types.Unrest): ()
    unrest.Bridge:Handle("Toko.Beli", function(payload: any)
        if typeof(payload) ~= "table" then
            return
        end
        print(`{payload.Player} mau beli {payload.Item}`)
    end)
end

function Toko:Start(): () end

function Toko:Destroy(): () end

return Toko
```

Tiga hal yang wajib dan mudah terlupa:

* **`Name` wajib**, dan harus unik. Itu kunci registry-nya.
* **`Dependencies` wajib ditulis walau kosong** — `{} :: { string }`. Itu yang menjamin
  `Dompet:Init` sudah selesai sebelum `Toko:Init` jalan.
* **`Start` dan `Destroy` sebaiknya tetap ditulis walau kosong.** `Types.System`
  mendeklarasikan ketiganya opsional; type checker Luau tidak sependapat dan menolak tabel
  yang kehilangan salah satunya. Itu pajak, bukan pilihan.

Siklus hidup lengkapnya ada di [API Core](API-CORE.md).

---

## 3. Tulis bootstrap client

Buka `src/game-client/init.client.luau`. Lebih pendek:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()

require(script.Shop)(unrest)
```

Tidak ada langkah "nyalakan jaringan" di sini, karena framework tidak punya jaringan untuk
dinyalakan. Yang ada cuma dua hal, dan `Unrest:Start()` melakukannya dalam urutan ini:

1. **Mengadopsi UI.** Setiap instance bertag `Unrest` yang ada di DataModel mulai dikelola,
   dan tag yang datang belakangan tetap ditangkap. Ini **hanya terjadi di client** — di
   server `Elements` ada tapi tidak mengadopsi apa pun, karena server tidak punya layar dan
   tidak ada pemain yang mengklik apa pun di sana.
2. **Menjalankan sistem.** `Init` semuanya, lalu `Start` semuanya, sama seperti di server.

Urutannya begitu supaya sebuah sistem yang di `Init`-nya langsung memanggil `Unrest:Query`
sudah menemukan layar yang ada. Dan kalaupun tidak, query itu ikatan hidup: elemen yang
ditandai sepuluh menit lagi akan terikat sepuluh menit lagi.

Sisa berkas di `src/game-client/` cuma fitur, satu berkas satu fitur, masing-masing menerima
`unrest` sebagai argumen pertama:

```luau
require(script.Shop)(unrest)
require(script.Slider)(unrest, { --[[ aksi per UnrestGroup ]] })
require(script.Toggle)(unrest, { --[[ aksi per UnrestGroup ]] })
```

Urutan `require`-nya tidak penting. Menambah fitur berarti menambah berkas dan satu baris,
bukan menumbuhkan berkas ini.

---

## 4. Bridge tidak menyeberangi mesin — jadi jaringan itu urusanmu

Ini bagian yang paling sering disalahpahami, dan paling penting.

`Bridge` adalah **bus lokal**. Seluruh permukaannya:

```luau
bridge:Publish(channel, value)     -- state -> UI, nilainya ditahan
bridge:Subscribe(channel, handler)
bridge:Peek(channel)               -- nilai terakhir, atau nil

bridge:Dispatch(command, payload)  -- UI -> kode, kirim lalu lupakan
bridge:Handle(command, handler)
```

Tidak ada argumen `Player` di mana pun, dan tidak ada satu pun dari fungsi itu yang
menyeberangi mesin. Ada satu Bridge di server dan satu Bridge di setiap client, dan keduanya
tidak saling bicara. `Dispatch` dengan nama yang tidak ada handler-nya adalah **no-op yang
diam**, itu disengaja.

Jadi kalau sebuah tombol di layar pemain harus menghasilkan sesuatu di server, **game-mu yang
mengirim pesannya sendiri.** Repo ini memakai ByteNet, dan skemanya tinggal di
`src/game-net/init.luau`:

```luau
return ByteNetMax.defineNamespace("Game", function()
    return {
        packets = {
            Beli = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Barang = ByteNetMax.string }),
            }),
            Koin = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Nilai = ByteNetMax.uint32 }),
            }),
            Pesan = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Teks = ByteNetMax.string }),
            }),
        },
    }
end)
```

Satu paket per jenis pesan, bukan satu amplop serbaguna. Itulah gunanya ByteNet: skema
konkret yang bisa dipak rapat.

Polanya sama di kedua arah, dan cuma satu kalimat: **paket masuk, lalu segera diterjemahkan
jadi satu panggilan Bridge.**

| Arah | Yang mengirim | Yang menerima | Baris yang menyambungkannya |
| --- | --- | --- | --- |
| client → server | `GameNet.packets.Beli.send({ Barang = item })` di `Shop.luau` | `init.server.luau` | `unrest.Bridge:Dispatch("Toko.Beli", { Player = player, Item = data.Barang })` |
| server → client | `GameNet.packets.Koin.sendTo({ Nilai = saldo }, player)` di `Dompet`/`Toko` | `Shop.luau` | `bridge:Publish("Koin", data.Nilai)` |

Sisi client-nya, `src/game-client/Shop.luau`, seluruhnya cuma ini:

```luau
GameNet.packets.Koin.listen(function(data)
    bridge:Publish("Koin", data.Nilai)
end)

GameNet.packets.Pesan.listen(function(data)
    bridge:Publish("Pesan", data.Teks)
end)
```

Dua konsekuensi yang perlu kamu simpan:

* **Nama channel adalah satu-satunya sambungan antara paket dan label.** `"Koin"` di
  `Publish` harus sama persis dengan `UnrestChannel` yang diketik desainer di Studio. Versi
  lama pernah menulis `"koin"` huruf kecil, dan saldo pembuka tidak pernah tergambar —
  tanpa satu pun galat.
* **Sistem di server tidak pernah menyebut nama channel.** `Toko` mengirim paket `Koin`;
  yang memutuskan bahwa paket itu berarti channel `"Koin"` adalah client. Pemetaannya terjadi
  sekali, di satu tempat.

Karena client meng-`require` `GameNet` sebelum replikasi tentu selesai, pakai
`WaitForChild` di sana:

```luau
local GameNet = require(ReplicatedStorage:WaitForChild("GameNet"))
```

---

## 5. Tandai satu elemen, lalu tekan Play

Kemenangan terkecil yang mungkin: satu tag, nol atribut, nol kode.

1. Masukkan `ScreenGui` ke `StarterGui`, dan `TextButton` di dalamnya.
2. **View → Tag Editor**, pilih tombolnya, tambahkan tag `Unrest`.
3. Tekan Play.

Tombol itu sekarang dikelola. Dia belum melakukan apa-apa, tapi dia sudah bisa ditemukan
`Unrest:Query`, dan atribut apa pun yang kamu tambahkan padanya langsung terbaca.

**Tag itu menurun.** Menandai `ScreenGui`-nya saja sudah cukup untuk mengelola setiap
`GuiObject` di bawahnya. Satu layar diikutsertakan dengan satu tag pada wadahnya, bukan
dengan empat puluh tag pada empat puluh tombol. `UnrestIgnore = true` pada sebuah instance
mengeluarkannya kembali beserta seluruh keturunannya. Aturan lengkapnya ada di
[Adopsi dan Tag](UI-ADOPTION.md).

Penandaan bersifat langsung dua arah: tambahkan tag saat game berjalan dan elemennya
diadopsi saat itu juga; cabut tagnya dan dia dilepas saat itu juga. Tidak ada yang perlu
di-restart.

---

## 6. Buat tombolnya bekerja — tanpa kode

Pilih `TextButton` yang tadi, tambahkan dua atribut di panel Properties:

| Atribut | Tipe | Nilai |
| --- | --- | --- |
| `UnrestCommand` | string | `Menu.Tutup` |
| `UnrestPayload` | string | `Toko` |

`Menu.Tutup` bukan nama bawaan apa pun — framework tidak mengeja satu nama perintah pun.
Itu nama yang kamu karang sendiri, dan yang membuatnya berarti adalah handler yang kamu
daftarkan dengan nama yang sama.

Atribut itu persis sama artinya dengan menulis:

```luau
unrest:Dispatch("Menu.Tutup", "Toko")
```

**Atribut bukan mekanisme kedua.** Dia lewat `Bridge:Dispatch` yang sama dengan Luau tulisan
tangan, dan sampai ke handler yang sama. Dari sisi seberang Bridge, layar yang dirakit di
Studio dan layar yang dirakit di kode tidak bisa dibedakan.

Dan karena Bridge itu lokal, konsekuensinya lugas:

> **`UnrestCommand` sampai ke handler di client, bukan ke server.** Yang menangkapnya adalah
> `unrest.Bridge:Handle("Menu.Tutup", ...)` yang ditulis di `src/game-client/`. Kalau tidak
> ada yang menangkapnya, tidak terjadi apa-apa, dan tidak ada galat.

Kalau yang kamu mau adalah menyentuh server, atribut saja tidak cukup — tombolnya perlu
mengirim paket, seperti tombol beli di bagian 9.

`UnrestCommand` hanya berarti pada kelas yang bisa diaktifkan: `TextButton`, `ImageButton`,
`ClickDetector`, `ProximityPrompt`. Pada `Frame` kamu dapat peringatan yang menyebut nama
elemennya, dan sisa layarnya tetap jalan.

Kalau tombolnya dobel-klik karena jari kelewat cepat, tambahkan `UnrestCooldown` (detik).
Itu debounce di memori elemen itu sendiri, dan tidak lebih dari itu.

---

## 7. Buat label mengikuti state — tanpa kode

Sisipkan `TextLabel`, tandai `Unrest`, lalu tambahkan:

| Atribut | Tipe | Nilai |
| --- | --- | --- |
| `UnrestChannel` | string | `Koin` |
| `UnrestBind` | string | `Text` |
| `UnrestFormat` | string | `Koin: {value}` |

Nilainya datang dari `Shop.luau`, yang menerbitkannya begitu paket `Koin` tiba:

```luau
bridge:Publish("Koin", data.Nilai)
```

Tekan Play. Labelnya langsung benar, bahkan kalau dia baru diadopsi jauh setelah nilainya
diterbitkan. Sebabnya: **channel itu ditahan (retained)**. Pelanggan yang datang belakangan
tetap menerima nilai terakhir. Urutan berhenti jadi masalah — dan itu penting justru karena
paket dari server bisa tiba sebelum `PlayerGui` selesai direplikasi.

* `UnrestBind` boleh dihilangkan kalau kelasnya punya satu nilai yang jelas. `TextLabel`
  menulis `Text`, `ImageLabel` menulis `Image`, `ScrollingFrame` menulis `CanvasPosition`.
* Tanpa `UnrestFormat`, nilainya ditulis mentah. Itulah cara menggerakkan `Color3`, `UDim2`,
  atau `boolean` dari sebuah channel. Dengan format, hasilnya selalu string, dan `nil`
  menjadi kosong, bukan tulisan `nil`.
* `UnrestBind` adalah **daftar-izin per kelas**. `UnrestBind = "Parent"` cuma memberi
  peringatan dan tidak menulis apa pun — sebuah nilai yang datang dari channel tidak boleh
  menulis properti sembarangan.

---

## 8. Kurangi pengulangan — `UnrestPreset` dan `UnrestGroup`

Langkah 6 dan 7 tidak berskala. Tiga atribut di setiap label dan dua di setiap tombol berarti
banyak kesempatan salah ketik.

**Preset adalah bundel bernama.** Framework tidak membawa satu preset pun — preset menyebut
nama channel atau perintah, dan nama itu milik game. Daftarkan sendiri di kode game-mu,
sebelum `Unrest:Start()`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Presets = require(ReplicatedStorage.Unrest.Presets)

local ATTRIBUTES = Constants.Attributes

Presets.Register("LabelKoin", {
    [ATTRIBUTES.Channel] = "Koin",
    [ATTRIBUTES.Bind] = "Text",
    [ATTRIBUTES.Format] = "Koin: {value}",
})
```

Lalu di Studio, ganti tiga atribut tadi dengan satu:

| Atribut | Nilai |
| --- | --- |
| `UnrestPreset` | `LabelKoin` |

**Preset adalah nilai bawaan, bukan penimpa.** Satu hal yang berbeda tetap ditulis di
elemennya sendiri, dan yang ditulis di elemen selalu menang.

**Grup ditulis sekali.** Set `UnrestGroup = "Toko"` di **ScreenGui**-nya. Setiap keturunan
yang dikelola mewarisinya, dan `unrest:Query({ Group = "Toko" })` memilih semuanya sekaligus.

Tiga aturan yang mengatur ini, dan hanya tiga:

1. **Hanya tiga atribut yang diwariskan** — `UnrestGroup`, `UnrestCooldown`, `UnrestPreset`.
   Yang diwariskan adalah konteks, tidak pernah niat. `UnrestCommand` yang diwariskan akan
   diam-diam mempersenjatai setiap keturunan sebuah panel.
2. **Yang paling spesifik menang** — atribut elemen sendiri mengalahkan presetnya, dan
   presetnya mengalahkan leluhurnya.
3. **Penelusuran berhenti di `LayerCollector` pertama** (`ScreenGui`, `SurfaceGui`,
   `BillboardGui`), setelah membaca atributnya sendiri. Satu layar adalah cakupan terluas
   yang boleh dimiliki sebuah nilai warisan.

Detailnya di [Referensi Atribut](UI-ATTRIBUTES.md) dan [API Presets](API-PRESETS.md).

---

## 9. Kapan berhenti memakai atribut

`UnrestCommand` menyatakan **satu perintah tetap** yang berhenti di Bridge lokal. Begitu
tombolnya harus mengirim paket, atau perintah yang benar bergantung pada keadaan sekarang,
atribut sudah tidak cukup. Di situlah `Unrest:Query` masuk.

Inilah seluruh tombol beli di game contoh, satu query untuk berapa pun banyaknya, dari
`src/game-client/Shop.luau`:

```luau
unrest:Query({ Tag = unrest.Tag, Selector = "GuiButton", Role = "Beli" }, {
    Active = function(element: Instance)
        local item = element:GetAttribute("UnrestPayload")
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
```

Perhatikan pembagian kerjanya. Kode di atas tahu **cara** membeli; yang menentukan **apa**
yang dibeli tetap `UnrestPayload` yang diketik desainer. Menambah tombol beli kesepuluh
berarti menduplikasi satu tombol di Studio dan mengganti satu atribut — tidak ada baris kode
baru.

**`Role` jatuh balik ke `Instance.Name`.** Tombol yang namanya `Beli` cocok dengan query itu
tanpa satu atribut pun. Dan kalau desainer nanti menamainya ulang jadi `Btn_04_final`, dia
cukup mengisi `UnrestRole = "Beli"` dan query-nya tetap cocok. Karena itu, dalam descriptor
pilih `Role`, bukan `Name`.

Query adalah **ikatan hidup**, bukan pemindaian sekali jalan. Buat query sebelum elemennya
ada, dan elemen yang ditandai sepuluh menit lagi akan terikat sepuluh menit lagi. Umurnya
milikmu: panggil `:Destroy()` pada handle-nya saat layar yang dilayaninya pergi.

> **Kode melempar error; atribut cuma memperingatkan.** Mengikat `Submit` dari kode ke
> `TextLabel` melempar error — itu bug di kode yang kamu tulis. Kesalahan yang sama yang
> diketik sebagai atribut hanya memberi peringatan, karena atribut adalah data, biasanya
> diketik orang yang tidak sedang melihat jendela Output, dan menjatuhkan seluruh layar
> karena itu jauh lebih buruk.

Kalau yang kamu bangun terdiri dari beberapa bagian yang baru berarti kalau lengkap — slider,
sakelar — jangan menulis query sendiri. Pakai `Unrest.Widgets`, seperti `Slider.luau` dan
`Toggle.luau` di `src/game-client/`. Lihat [API Widgets](API-WIDGETS.md).

---

## Selanjutnya

* **[Modul Bersama Game](GAME-MODULE.md)** — apa saja yang benar-benar harus kamu deklarasikan
  di modul yang dibaca dua realm. Halaman pendek, dan itu memang kabar baik.
* **[Peta API](API-OVERVIEW.md)** — setiap fungsi framework, satu per satu.
* **[API Bridge](API-BRIDGE.md)** — publish/subscribe dan dispatch/handle, selengkapnya.
* **[Referensi UI](UI-BINDING.md)** — atribut, handler, dan kelas apa mendukung apa.
* **[Pemecahan Masalah](TROUBLESHOOTING.md)** — pesan galat dan artinya.
