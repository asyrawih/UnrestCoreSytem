# Panduan Memulai

Ikuti halaman ini sekali, berurutan, dan kamu akan punya satu layar yang mengirim perintah ke
server dan satu label yang mengikuti state server. Kamu tidak perlu membaca satu baris pun
kode framework untuk menyelesaikannya.

Yang diasumsikan: kamu sudah bisa memakai Roblox Studio. Yang tidak diasumsikan: apa pun
tentang framework ini.

---

## 0. Peta tempat: kode siapa taruh di mana

Ini bagian yang paling sering bikin bingung, jadi kita selesaikan dulu sebelum menulis apa
pun. Ada **lima folder**, dan hanya **tiga** yang boleh kamu sentuh.

| Folder di disk | Muncul di DataModel sebagai | Punya siapa |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Unrest` | **framework** — jangan disentuh |
| `src/server` | `ServerScriptService.Unrest` | **framework** — jangan disentuh |
| `src/game` | `ReplicatedStorage.Game` | **kamu** — dibaca client *dan* server |
| `src/game-server` | `ServerScriptService.Game` | **kamu** — hanya server |
| `src/game-client` | `StarterPlayer.StarterPlayerScripts.Game` | **kamu** — hanya client |

Cara mengingatnya cuma satu baris:

> **`Unrest` itu framework. `Game` itu kamu.**

Dua nama itu bersebelahan di DataModel, bukan bersarang. `ReplicatedStorage.Game` ada di
*sebelah* `ReplicatedStorage.Unrest`, bukan di dalamnya. Itu disengaja, dan itu juga alasan
kenapa aturan berikut bisa ditegakkan:

> **Kode game meng-`require` framework. Framework tidak pernah meng-`require` kode game.**
> Tidak ada satu berkas pun di `src/shared` atau `src/server` yang boleh menyebut
> `ReplicatedStorage.Game`.

Kalau kamu pernah tidak sengaja menghapus sesuatu di `Unrest` karena mengira itu punyamu:
bukan salahmu, tata letaknya memang tidak menjelaskan dirinya sendiri. Sekarang sudah.

Jawaban singkat untuk "aku mulai nulis script di mana":

- **Sisi server** → `src/game-server/init.server.luau`
- **Sisi client** → `src/game-client/init.client.luau`
- **Yang dipakai keduanya** → `src/game/`

---

## 1. Hidupkan Rojo dan sambungkan ke Studio

```sh
rokit install     # sekali per clone; tanpa ini shim Rokit menolak jalan
rojo serve        # menyajikan default.project.json di port 34872
```

Di Studio: **Plugins → Rojo → Connect**.

**Yang seharusnya kamu lihat** di Explorer, lima hal, persis seperti tabel di bagian 0:

```
ReplicatedStorage
├── Unrest        ← framework
└── Game          ← punyamu, dibaca dua sisi

ServerScriptService
├── Unrest        ← framework
└── Game          ← punyamu, server

StarterPlayer/StarterPlayerScripts
└── Game          ← punyamu, client
```

**Kalau tidak muncul**, kemungkinan besar kamu menjalankan `rojo serve` dari folder lain.
Jalankan dari akar repo, tempat `default.project.json` berada.

---

## 2. Tulis bootstrap server

Buat berkas `src/game-server/init.server.luau`. Isinya empat baris yang penting, dan
**urutannya bermakna**:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Game)                  -- 1. deklarasi kontrak dan preset
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:Register(require(script.Systems.Greeter)) -- 2. daftarkan sistem
local unrest = Unrest:Start()                    -- 3. Init lalu Start
unrest:OpenGateway()                             -- 4. remote muncul
```

### Kenapa urutannya begitu

Baca dari bawah, karena baris terakhir yang menjelaskan sisanya.

**Baris 4 adalah saat pintu dibuka.** `OpenGateway` yang membuat objek remote muncul di
DataModel. Sebelum baris itu jalan, tidak ada satu pun jalan bagi client untuk mengirim
apa pun ke server — bukan karena ditolak, tapi karena remote-nya belum ada.

Jadi meletakkannya **paling akhir** memberi jaminan yang enak: permintaan paling awal yang
mungkin dikirim client pun pasti menemukan seluruh handler sudah terpasang. Tidak ada celah
waktu di mana pintunya terbuka tapi ruangannya masih kosong.

Sekarang baris-baris sebelumnya jadi masuk akal:

| Baris | Yang terjadi | Kalau dilewat |
| --- | --- | --- |
| 1. `require(ReplicatedStorage.Game)` | Setiap perintah dan channel didaftarkan ke registry framework. Meng-`require`-nya **adalah** pendaftarannya. | Framework gagal tertutup: setiap perintah ditolak `UnknownCommand`. Tidak berbahaya, cuma tidak jalan. |
| 2. `Unrest:Register(...)` | Sistem masuk ke registry. Belum jalan, baru terdaftar. | Sistemnya tidak pernah hidup. |
| 3. `Unrest:Start()` | `Init(unrest)` untuk semua sistem sesuai urutan dependensi, lalu `Start()` untuk semua sistem. Di sinilah `Bridge:Handle` dipanggil. | Tidak ada handler yang terpasang. |
| 4. `unrest:OpenGateway()` | Remote dibuat. Client mulai bisa bicara. | Semua yang dikirim client tidak sampai. |

Perhatikan bahwa `Bridge:Handle` biasanya dipanggil di dalam `Init` sebuah sistem. Karena
`Start()` menjalankan semua `Init` sebelum baris 4, seluruh handler sudah pasti terdaftar
saat pintu dibuka. Itu bukan kebetulan, itu alasan urutan ini dipilih.

### Sistem paling kecil yang tetap jalan

Buat `src/game-server/Systems/Greeter.luau`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = require(ReplicatedStorage.Game)
local UnrestTypes = require(ReplicatedStorage.Unrest.Types)

local Greeter = {
    Name = "Greeter",
    Dependencies = {} :: { string },
}

function Greeter:Init(unrest: UnrestTypes.Unrest): ()
    unrest.Bridge:Handle(Game.Commands.Greet, function(source, payload)
        print(`halo, {source.Player and source.Player.Name or "server"}`)
        return true
    end)
end

return Greeter
```

Dua hal yang wajib ada di sini dan mudah terlupa:

* **`Name` wajib**, dan harus unik. Itu kunci registry-nya.
* **`Dependencies` wajib ditulis walau kosong** — `{} :: { string }`. Tanpa itu type checker
  strict tidak mengenali tabelmu sebagai `System`.

`Init`, `Start`, dan `Destroy` semuanya opsional. Lihat [API Core](API-CORE.md) untuk
siklus hidup lengkapnya.

---

## 3. Tulis bootstrap client

Buat berkas `src/game-client/init.client.luau`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Game)                  -- 1. kontrak dan preset, sama persis
local Unrest = require(ReplicatedStorage.Unrest)
local unrest = Unrest:Start()                    -- 2. jaringan hidup, UI bertag diadopsi
```

Lebih pendek dari sisi server, dan bedanya cuma satu: **tidak ada `OpenGateway` di client.**
Remote dibuat oleh server; client menunggunya. Membuka gerbang adalah tindakan yang hanya
punya arti di sisi yang memegang gembok.

Dua hal yang dilakukan `Unrest:Start()` di client:

1. Menghidupkan setengah-client dari lapisan jaringan.
2. **Mengadopsi UI.** Setiap instance bertag `Unrest` di `PlayerGui` mulai dikelola. Ini
   hanya terjadi di client — di server, `Elements` ada tapi tidak mengadopsi apa pun.

Kenapa client juga harus `require(ReplicatedStorage.Game)`? Karena Roblox menyimpan cache
ModuleScript **per realm**. Server punya salinan registry-nya sendiri, client punya
salinannya sendiri. Keduanya harus diberi tahu. Kalau client lupa, dia akan menolak mengirim
perintah yang sebenarnya sah, dengan `UnknownCommand` di sisi client.

---

## 4. Deklarasikan perintah pertamamu

Sekarang isi `src/game/`. Detail lengkapnya ada di halaman
[ModuleScript `Game`](GAME-MODULE.md); di sini kita ambil versi paling ringkasnya.

**`src/game/Names.luau`** — nama, dieja sekali saja:

```luau
--!strict
return table.freeze({
    Channels = table.freeze({
        Greeting = "Greet.Last",
    }),
    Commands = table.freeze({
        Greet = "Greet.Say",
    }),
})
```

**`src/game/Contracts.luau`** — kebijakannya. Ini yang menentukan apa yang boleh diminta
client:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contracts = require(ReplicatedStorage.Unrest.Net.Contracts)
local Names = require(script.Parent.Names)

Contracts:Declare({
    Name = Names.Commands.Greet,
    Realm = "Server",
    AllowClient = true,                    -- baris inilah yang membuka pintunya
    Payload = { Kind = "string", MaxLength = 32 },
    RateLimit = { Count = 2, Window = 1 },
    Response = true,
    Description = "Sapa pemanggilnya.",
})

Contracts:DeclareChannel({
    Name = Names.Channels.Greeting,
    Visibility = "Public",
    Value = { Kind = "string", Optional = true, MaxLength = 64 },
    Description = "Sapaan terakhir yang dikirim siapa pun.",
})

return table.freeze({})
```

**Menambah nama di `Names.luau` tidak memberi apa-apa.** Yang memberi izin adalah
`AllowClient = true` di `Contracts.luau`. Hilangkan baris itu dan perintahnya tetap ada,
tetap bisa dipakai kode server, tapi tidak bisa dijangkau client sama sekali. Ketiadaan
izin **adalah** penolakannya — tidak ada `Private = true` yang harus kamu ingat menulis.

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
dengan empat puluh tag pada empat puluh tombol. Aturan lengkapnya ada di
[Adopsi dan Tag](UI-ADOPTION.md).

Penandaan bersifat langsung dua arah: tambahkan tag saat game berjalan dan elemennya
diadopsi saat itu juga; cabut tagnya dan dia dilepas saat itu juga. Tidak ada yang perlu
di-restart.

---

## 6. Buat tombolnya bekerja — tanpa kode

Pilih `TextButton` yang tadi, tambahkan dua atribut di panel Properties:

| Atribut | Tipe | Nilai |
| --- | --- | --- |
| `UnrestCommand` | string | `Greet.Say` |
| `UnrestPayload` | string | `Halo` |

Tekan Play, klik tombolnya. Handler `Greeter` di server jalan.

Atribut itu persis sama artinya dengan menulis:

```luau
unrest:Dispatch("Greet.Say", "Halo")
```

**Atribut tidak memberi hak istimewa.** Dia lewat `Bridge:Dispatch` yang sama dengan Luau
tulisan tangan. Kontraknya tetap yang memutuskan, server tetap memvalidasi payload, server
tetap menerapkan batas laju. Ketik nama perintah yang tidak `AllowClient` ke dalam
`UnrestCommand` dan hasilnya `NotClientCallable` — sama persis seperti kalau kamu menulisnya
di kode.

`UnrestCommand` hanya berarti pada kelas yang bisa diaktifkan: `TextButton`, `ImageButton`,
`ClickDetector`, `ProximityPrompt`. Pada `Frame` kamu dapat peringatan yang menyebut nama
elemennya, dan sisa layarnya tetap jalan.

---

## 7. Buat label mengikuti state — tanpa kode

Sisipkan `TextLabel`, tandai `Unrest`, lalu tambahkan:

| Atribut | Tipe | Nilai |
| --- | --- | --- |
| `UnrestChannel` | string | `Greet.Last` |
| `UnrestBind` | string | `Text` |
| `UnrestFormat` | string | `Terakhir: {value}` |

Lalu di handler server, terbitkan nilainya:

```luau
unrest.Bridge:Publish(Game.Channels.Greeting, payload)
```

Tekan Play. Labelnya langsung benar, bahkan kalau dia baru diadopsi jauh setelah nilainya
diterbitkan. Sebabnya: **channel itu ditahan (retained)**. Pelanggan yang datang belakangan
tetap menerima nilai terakhir. Urutan berhenti jadi masalah.

* `UnrestBind` boleh dihilangkan kalau kelasnya punya satu nilai yang jelas. `TextLabel`
  menulis `Text`, `ImageLabel` menulis `Image`, `ScrollingFrame` menulis `CanvasPosition`.
* Tanpa `UnrestFormat`, nilainya ditulis mentah. Itulah cara menggerakkan `Color3`, `UDim2`,
  atau `boolean` dari sebuah channel. Dengan format, hasilnya selalu string, dan `nil`
  menjadi kosong, bukan tulisan `nil`.
* `UnrestBind` adalah **daftar-izin per kelas**. `UnrestBind = "Parent"` cuma memberi
  peringatan, tidak menulis apa pun — nilai yang bisa datang dari server tidak boleh menulis
  properti sembarangan.

---

## 8. Kurangi pengulangan — `UnrestPreset` dan `UnrestGroup`

Langkah 6 dan 7 tidak berskala. Tiga atribut di setiap label dan dua di setiap tombol berarti
banyak kesempatan salah ketik.

**Preset adalah bundel bernama.** Daftarkan di `src/game/Presets.luau`:

```luau
Presets.Register("GreetingLabel", {
    [ATTRIBUTES.Channel] = CHANNELS.Greeting,
    [ATTRIBUTES.Bind] = "Text",
    [ATTRIBUTES.Format] = "Terakhir: {value}",
})
```

Lalu di Studio, ganti tiga atribut tadi dengan satu:

| Atribut | Nilai |
| --- | --- |
| `UnrestPreset` | `GreetingLabel` |

**Preset adalah nilai bawaan, bukan penimpa.** Satu hal yang berbeda tetap ditulis di
elemennya sendiri, dan yang ditulis di elemen selalu menang.

**Grup ditulis sekali.** Set `UnrestGroup = "MenuUtama"` di **ScreenGui**-nya. Setiap
keturunan yang dikelola mewarisinya, dan `unrest:Query({ Group = "MenuUtama" })` memilih
semuanya sekaligus.

Tiga aturan yang mengatur ini, dan hanya tiga:

1. **Hanya tiga atribut yang diwariskan** — `UnrestGroup`, `UnrestCooldown`, `UnrestPreset`.
   Yang diwariskan adalah konteks, tidak pernah niat. `UnrestCommand` yang diwariskan akan
   diam-diam mempersenjatai setiap keturunan sebuah panel.
2. **Yang paling spesifik menang** — atribut elemen sendiri mengalahkan presetnya, dan
   presetnya mengalahkan leluhurnya.
3. **Penelusuran berhenti di `LayerCollector` pertama** (`ScreenGui`, `SurfaceGui`,
   `BillboardGui`), setelah membaca atributnya sendiri. Satu layar adalah cakupan terluas
   yang boleh dimiliki sebuah nilai warisan.

Detailnya di [Referensi Atribut](UI-ATTRIBUTES.md).

---

## 9. Kapan berhenti memakai atribut

`UnrestCommand` menyatakan **satu perintah tetap**. Begitu perintah yang benar bergantung
pada keadaan sekarang, atribut sudah tidak cukup. Di situlah `Unrest:Query` masuk — dan di
situlah kamu mulai menulis kode client di `src/game-client/`.

```luau
unrest:Query({
    Tag = unrest.Tag,
    Selector = "GuiButton",   -- is:A("GuiButton") -- TextButton dan ImageButton
    Role = "ToggleMenu",
}, {
    Active = function(element)
        if unrest.Bridge:Peek(Game.Channels.Greeting) == nil then
            unrest:Dispatch(Game.Commands.Greet, "Halo")
        else
            unrest:Dispatch(Game.Commands.Greet, "Dah")
        end
    end,
})
```

**`Role` jatuh balik ke `Instance.Name`.** Tombol yang namanya `ToggleMenu` cocok dengan
query itu tanpa satu atribut pun. Dan kalau desainer nanti menamainya ulang jadi
`Btn_04_final`, dia cukup mengisi `UnrestRole = "ToggleMenu"` dan query-nya tetap cocok.
Karena itu, dalam descriptor pilih `Role`, bukan `Name`.

Query adalah **ikatan hidup**, bukan pemindaian sekali jalan. Buat query sebelum elemennya
ada, dan elemen yang ditandai sepuluh menit lagi akan terikat sepuluh menit lagi. Umurnya
milikmu: panggil `:Destroy()` pada handle-nya saat layar yang dilayaninya pergi.

> **Kode melempar error; atribut cuma memperingatkan.** Mengikat `Submit` dari kode ke
> `TextLabel` melempar error — itu bug di kode yang kamu tulis. Kesalahan yang sama yang
> diketik sebagai atribut hanya memberi peringatan, karena atribut adalah data, biasanya
> diketik orang yang tidak sedang melihat jendela Output, dan menjatuhkan seluruh layar
> karena itu jauh lebih buruk.

---

## 10. Ganti transport-nya (opsional)

Secara bawaan framework memakai remote Roblox biasa. Kalau kamu mau memakai ByteNet atau
pustaka jaringan lain, pasang di antara `require` dan `:Start()`:

```luau
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:UseTransport(require(ReplicatedStorage.Game.Transport))
local unrest = Unrest:Start()
```

Jendela waktunya nyata, bukan formalitas: memasangnya setelah `:Start()` akan melempar error,
bukan diam-diam memindahkan separuh trafik. Lihat [API Transport](API-TRANSPORT.md).

---

## Selanjutnya

* **[ModuleScript `Game`](GAME-MODULE.md)** — isi `src/game/` selengkapnya, dan apa yang
  minimal harus kamu definisikan di sana.
* **[Peta API](API-OVERVIEW.md)** — setiap fungsi framework, satu per satu.
* **[Referensi UI](UI-BINDING.md)** — atribut, handler, dan kelas apa mendukung apa.
* **[Keamanan Remote](REMOTE-SECURITY.md)** — jalur penolakan, berurutan.
* **[Pemecahan Masalah](TROUBLESHOOTING.md)** — pesan galat dan artinya.
