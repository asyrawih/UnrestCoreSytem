# ModuleScript `Game`

`ReplicatedStorage.Game` adalah tempat game-mu tinggal. Ini satu-satunya berkas yang
**wajib** kamu isi sebelum framework berguna.

Di disk letaknya `src/game/`.

---

## 1. Apa ini, dan kenapa ada

Framework ini tidak tahu apa-apa soal game-mu. Itu bukan kekurangan, itu keseluruhan
rancangannya. Framework tidak tahu perintahmu bernama apa, channel-mu ada berapa, atau tombol
"putar" itu artinya apa. Dia hanya tahu cara **membawa** sebuah perintah dan cara
**menerapkan** kebijakan atasnya.

Jadi harus ada satu tempat yang menyimpan pengetahuan itu. Tempatnya di sini.

`ReplicatedStorage.Game` ada **di sebelah** `ReplicatedStorage.Unrest`, bukan di dalamnya:

```
ReplicatedStorage
├── Unrest        ← framework
└── Game          ← punyamu
```

Dan arah ketergantungannya cuma satu:

> **Kode game meng-`require` framework. Framework tidak pernah meng-`require` kode game.**

Tidak ada satu berkas pun di `src/shared` atau `src/server` yang boleh menyebut
`ReplicatedStorage.Game`. Kalau kamu pernah tergoda menulisnya, itu tandanya sesuatu yang
seharusnya ada di `src/game` terlanjur bocor ke framework.

Isinya adalah hal-hal yang **client dan server harus sepakati**, tapi framework tidak boleh
memilikinya:

* nama channel dan perintah game ini;
* kontrak untuk masing-masing, didaftarkan ke registry framework;
* bundel preset yang dipanggil desainer dari Studio lewat nama.

---

## 2. Meng-`require`-nya **adalah** mendeklarasikannya

Ini bagian yang paling penting dan paling mudah salah dibaca.

```luau
require(ReplicatedStorage.Game)
```

Baris itu bukan impor yang nilainya ingin dipakai. Baris itu **pekerjaannya**. Saat modul ini
di-`require`, dia meng-`require` `Contracts` dan `Presets` di dalamnya, dan kedua modul itu
memanggil `Contracts:Declare` dan `Presets.Register` sebagai efek samping.

Setelah itu barulah dia mengembalikan `Channels` dan `Commands`.

Susunan itu disengaja: **satu-satunya cara mendapatkan sebuah nama adalah lewat modul yang
sudah mendeklarasikannya.** Jadi "memakai perintah yang tidak pernah dideklarasikan" bukan
bentuk yang bisa ada di kode ini.

**Kedua bootstrap harus meng-`require`-nya.** Roblox menyimpan cache ModuleScript per realm,
jadi server punya salinan registry-nya sendiri dan client punya salinannya sendiri. Keduanya
harus diberi tahu. Itu bukan duplikasi, itu memang tujuannya.

Kalau salah satu lupa, framework **gagal tertutup**: perintah yang tidak dideklarasikan
ditolak penjaga di client, lalu ditolak lagi oleh gerbang di server. Yang kamu dapat adalah
penolakan yang berisik, bukan pintu yang terbuka.

Dan karena `Contracts:Declare` menolak nama yang sudah pernah dideklarasikan, `init.luau`
inilah yang memastikan tidak ada yang mencoba mendeklarasikan dua kali.

---

## 3. Isi minimalnya

Ini pertanyaan yang paling sering ditanyakan: **apa yang minimal harus aku definisikan di
sana?**

Jawabannya: **satu berkas, `init.luau`, dan minimal satu kontrak.** Sisanya adalah kerapian.

### Versi paling kecil yang tetap jalan

Satu berkas, `src/game/init.luau`:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contracts = require(ReplicatedStorage.Unrest.Net.Contracts)

local COMMANDS = table.freeze({
    Greet = "Greet.Say",
})

Contracts:Declare({
    Name = COMMANDS.Greet,
    Realm = "Server",
    AllowClient = true,
    Payload = { Kind = "string", MaxLength = 32 },
    Response = true,
})

return table.freeze({
    Channels = table.freeze({}),
    Commands = COMMANDS,
})
```

Itu saja. `require(ReplicatedStorage.Game)` di kedua bootstrap sekarang berarti sesuatu, dan
`Greet.Say` sudah bisa dipanggil client.

Yang **tidak** wajib:

* Channel — game yang hanya mengirim niat dan tidak menampilkan state tidak butuh satu pun.
* Preset — itu kenyamanan untuk desainer, bukan syarat.
* `Types.luau` — hanya berguna kalau kamu memakai type checker strict.
* `Transport.luau` — tanpa itu framework memakai remote Roblox biasa, dan itu baik-baik saja.

### Aturan minimalnya, dalam satu tabel

| Kalau kamu mau... | Kamu wajib punya |
| --- | --- |
| perintah apa pun berjalan | satu `Contracts:Declare` |
| perintah itu bisa dipanggil client | `AllowClient = true` di kontraknya |
| `Bridge:Invoke` boleh dipakai untuk perintah itu | `Response = true` di kontraknya |
| sebuah channel bisa direplikasi ke client | `Contracts:DeclareChannel` dengan `Visibility` selain `Server` |
| atribut `UnrestPreset` bisa dipakai | satu `Presets.Register` |

---

## 4. Bentuk lengkapnya, satu berkas per pekerjaan

Begitu game-mu tumbuh, satu berkas jadi sesak. Bentuk yang dipakai repo ini memecahnya jadi
enam, satu per pekerjaan:

| Berkas | Isinya |
| --- | --- |
| `init.luau` | Pintu depan. Meng-`require`-nya mendeklarasikan semuanya, lalu mengembalikan `Channels` dan `Commands`. Kedua bootstrap meng-`require` ini dan tidak yang lain. |
| `Names.luau` | Nama channel dan perintah, dieja **sekali**. |
| `Contracts.luau` | `Contracts:Declare` / `:DeclareChannel` untuk setiap nama. Di-`require` demi efek sampingnya. |
| `Presets.luau` | `Presets.Register` untuk setiap bundel atribut. Di-`require` demi efek sampingnya. |
| `Types.luau` | Bentuk sistem-sistem game ini, untuk type checker. |
| `Packets.luau` + `Transport.luau` | Format kabel milik game ini, kalau kamu mengganti transport. |

### `Names.luau` — nama dieja sekali

```luau
--!strict
return table.freeze({
    Channels = table.freeze({
        NowPlaying = "Music.NowPlaying",
        MusicVolume = "Music.Volume",
    }),
    Commands = table.freeze({
        MusicPlay = "Music.Play",
        MusicStop = "Music.Stop",
    }),
})
```

Kenapa repot-repot? Supaya salah ketik menjadi **indeks nil di baris pemanggilnya**, bukan
string yang diam-diam tidak cocok dengan apa pun.

Dan perlu ditegaskan: **menambah baris di sini tidak memberi apa-apa.** Ini pembukuan.
Menambah baris di `Contracts.luau` adalah keputusan.

### `Contracts.luau` — kebijakannya, sebagai data

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contracts = require(ReplicatedStorage.Unrest.Net.Contracts)
local Names = require(script.Parent.Names)

Contracts:Declare({
    Name = Names.Commands.MusicPlay,
    Realm = "Server",
    AllowClient = true,
    Payload = { Kind = "string", MaxLength = 64, Pattern = "[%w_%-%.]+" },
    RateLimit = { Count = 4, Window = 1 },
    Response = true,
    Description = "Putar lagu terdaftar berdasarkan nama.",
})

Contracts:DeclareChannel({
    Name = Names.Channels.NowPlaying,
    Visibility = "Public",
    Value = { Kind = "string", Optional = true, MaxLength = 64 },
    Description = "Lagu yang sedang didengar semua orang, atau nil.",
})

return table.freeze({})
```

Aturannya satu, dan sisanya konsekuensi:

> **Sebuah perintah tidak bisa dijangkau client kecuali kontraknya menulis
> `AllowClient = true`.**

Bukan "kecuali ditandai privat". Bukan "kecuali ada pengecekan yang ditambahkan".
**Ketiadaan izin itulah penolakannya.** Perintah tanpa baris itu tetap bisa dipakai kode
server sebebas-bebasnya; client yang mengirim namanya cuma dapat `NotClientCallable` dan
tidak belajar apa pun.

Channel mengikuti bentuk yang sama lewat `Visibility`, yang bawaannya `Server`. Channel yang
tidak dideklarasikan tidak direplikasi. Dia tidak bisa bocor karena kelalaian.

> **Catatan tentang `Authorize`.** Modul ini tinggal di ReplicatedStorage, jadi client bisa
> membaca fungsi-fungsinya. **Jangan pernah menutup rahasia di sini.** Fungsi itu boleh
> membaca state game (`player.Character`, atribut milik server) karena dia hanya *dijalankan*
> di server — salinan yang dipegang client mati, tidak pernah dieksekusi.

Referensi lengkap setiap field ada di [API Contracts](API-CONTRACTS.md).

### `Presets.luau` — bundel atribut

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Names = require(script.Parent.Names)
local Presets = require(ReplicatedStorage.Unrest.Presets)

local ATTRIBUTES = Constants.Attributes

Presets.Register("MusicToggle", {
    [ATTRIBUTES.Command] = Names.Commands.MusicPlay,
    [ATTRIBUTES.Payload] = "Lobby",
    [ATTRIBUTES.Channel] = Names.Channels.NowPlaying,
    [ATTRIBUTES.Bind] = "Text",
    [ATTRIBUTES.Format] = "Musik: {value}",
})

return table.freeze({})
```

Desainer cukup menulis satu atribut, `UnrestPreset = "MusicToggle"`, dan `ElementManager`
memekarkannya jadi lima.

Gunanya bukan sekadar ringkas. Gunanya: **"apa itu tombol musik" diputuskan sekali, di kode,
yang bisa ditelaah**, bukan diketik ulang di setiap tombol lalu perlahan melenceng.

**Framework tidak membawa satu preset pun.** Tabelnya kosong sejak awal, dan itu disengaja:
preset menyebut nama perintah atau channel, dan nama itu milik game.

Preset adalah singkatan, bukan hak istimewa. Preset yang menyebut perintah yang tidak
dideklarasikan tetap ditolak saat dispatch.

### `Types.luau` — bentuk sistemmu

Kalau kamu memakai `--!strict`, deklarasikan tipe setiap sistem dari modulnya sendiri:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnrestTypes = require(ReplicatedStorage.Unrest.Types)

type Signal<T...> = UnrestTypes.Signal<T...>
type System = UnrestTypes.System

export type MusicSystem = System & {
    NowPlayingChanged: Signal<string?>,
    Play: (self: MusicSystem, name: string) -> boolean,
    Stop: (self: MusicSystem) -> (),
}
```

Perhatikan arahnya: berkas ini mengimpor `System` dan `Signal` **dari framework**. Framework
tidak pernah mengimpor apa pun dari sini. Framework hanya membaca `Types.System`; apa yang
kamu tambahkan di atasnya adalah urusanmu.

### `Transport.luau` — kalau kamu mengganti kabelnya

`init.luau` sengaja **tidak** meng-`require` `Transport.luau`. Mount `Packages` bersifat
opsional, jadi sebuah `require` di sini akan membuat ByteNet yang hilang merusak seluruh
perintah di game, bukan cuma transport yang membutuhkannya.

Memasangnya adalah satu baris eksplisit di bootstrap:

```luau
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:UseTransport(require(ReplicatedStorage.Game.Transport))
```

Selengkapnya di [API Transport](API-TRANSPORT.md).

---

## 5. Daftar periksa

Sebelum kamu tekan Play, pastikan semuanya benar:

- [ ] `src/game/init.luau` ada, dan meng-`require` modul yang mendeklarasikan.
- [ ] Setiap perintah yang kamu pakai punya `Contracts:Declare`.
- [ ] Perintah yang dipanggil dari client punya `AllowClient = true`.
- [ ] Perintah yang dipanggil lewat `Bridge:Invoke` punya `Response = true`.
- [ ] Channel yang harus dilihat client punya `Visibility = "Public"` atau `"Player"`.
- [ ] `src/game-server/init.server.luau` meng-`require(ReplicatedStorage.Game)` **sebelum**
      `Unrest:Start()`.
- [ ] `src/game-client/init.client.luau` juga meng-`require(ReplicatedStorage.Game)`.
- [ ] Tidak ada satu pun berkas di `src/shared` atau `src/server` yang menyebut
      `ReplicatedStorage.Game`.
