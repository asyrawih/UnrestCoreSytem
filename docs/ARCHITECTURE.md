# Arsitektur

Framework Model/View/Controller untuk Roblox, dibangun di atas dua aturan.

**Framework tidak membuat UI.** Setiap elemen dibuat tangan di Roblox Studio. Menandai sebuah
instance dengan `Unrest` adalah seluruh pendaftarannya: dia diadopsi, adapter diresolusi untuk
`ClassName`-nya, atribut `Unrest*`-nya disambungkan, dan dia jadi terlihat oleh
`Unrest:Query`. Mencabut tagnya melepasnya. Tidak ada komponen, tidak ada `Mount`, dan tidak
ada apa pun di `ReplicatedStorage` yang menggambar tombol.

**Sebuah perintah tidak bisa dijangkau client kecuali kontraknya mengizinkan.** Penjaga di
client dan gerbang di server membaca kontrak yang sama, dan server tidak pernah memercayai
salinan milik client.

```
   Core (Model)              Bridge (Controller)              View
  ┌──────────────┐          ┌───────────────────┐      ┌──────────────────┐
  │  System milik│          │ Publish/Subscribe │      │  UI dibuat di    │
  │  game, hidup │  ──────► │ Dispatch/Invoke   │ ───► │  Studio, ditandai│
  │  di server   │          │ Handle            │      │  `Unrest`        │
  └──────────────┘          ├───────────────────┤      └──────────────────┘
   otoritatif               │ Net: kontrak,     │              ▲
                            │ validasi,         │              │
                            │ batas laju        │      CollectionService
                            └───────────────────┘       adopsi + adapter
```

Core tidak pernah menyentuh Instance. UI yang diadopsi tidak pernah memanggil sebuah System.
Semuanya menyeberang di Bridge, dan Bridge bertanya ke kontrak apa yang boleh.

---

## 1. Tata letak: siapa memiliki apa

| Folder di disk | Muncul di DataModel sebagai | Punya siapa |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Unrest` | framework |
| `src/server` | `ServerScriptService.Unrest` | framework |
| `src/game` | `ReplicatedStorage.Game` | game, dibaca kedua realm |
| `src/game-server` | `ServerScriptService.Game` | game, server |
| `src/game-client` | `StarterPlayer.StarterPlayerScripts.Game` | game, client |

`Unrest` dan `Game` **bersebelahan**, bukan bersarang. Itu yang membuat aturan berikut bisa
ditegakkan hanya dengan membaca `require`-nya:

> **Kode game meng-`require` framework. Framework tidak pernah meng-`require` kode game.**

Tidak ada satu berkas pun di `src/shared` atau `src/server` yang boleh menyebut
`ReplicatedStorage.Game`. Kalau ada, sesuatu yang seharusnya ada di sisi game sudah bocor ke
framework.

---

## 2. Kontrak antar lapis

| Lapis | Tinggal di | Boleh bergantung pada | Tidak pernah |
| --- | --- | --- | --- |
| `Primitives` | ReplicatedStorage | tidak apa-apa | — |
| `Util` (Signal, Scope, Resolver) | ReplicatedStorage | Primitives | state game |
| `Core` | registry di shared, sistem di sisi game-server | Bridge, Util | Instance, UI, layar pemain |
| `Bridge` | ReplicatedStorage | Net, Util | tahu tombol itu apa |
| `Net` | kontrak di shared, gerbang khusus server | tipe Bridge, Constants | memercayai payload |
| `Adapters` | ReplicatedStorage | Primitives | logika game |
| `Elements` | ReplicatedStorage, khusus client saat runtime | Adapters, Bridge | memanggil sistem langsung |

Dua batas modul menanggung beban.

**Kontrak itu publik; gemboknya tidak.** `Net/Contracts.luau` ada di `ReplicatedStorage`,
tempat client mana pun bisa membacanya. Itu memang disengaja. Isinya daftar nama pintu dan
mana yang punya gagang di sisi luar; gemboknya adalah gerbang server, yang tinggal di
`ServerScriptService` dan tidak pernah direplikasi.

**Sistem hidup di sisi server.** Registry `Core` adalah mesin bersama, tapi sistem yang
memegang state otoritatif tinggal di `src/game-server/`. Client tidak bisa membacanya, jadi
dia tidak bisa belajar darinya atau memanggilnya kecuali lewat perintah yang dideklarasikan.

---

## 3. Adopsi — bagaimana UI Studio masuk

Desainer membangun antarmuka seperti biasa. Satu-satunya tindakan yang menghadap framework
adalah menambahkan tag `Unrest`. Saat diadopsi:

1. **Adapter diresolusi.** Registry memilih adapter paling spesifik yang di-`:IsA()` instance
   itu, lalu meratakan rantai `Extends`-nya, jadi `TextButton` mewarisi semua yang
   dideklarasikan `GuiButton` dan `GuiObject`. Hasilnya di-cache per `ClassName`.
2. **Atribut disambungkan.** Atribut `Unrest*` berubah jadi perilaku yang hidup, dan
   tersambung ulang saat nilainya berubah.
3. **Elemennya jadi bisa di-query.** Setiap `Unrest:Query` yang descriptor-nya sekarang cocok
   langsung mengambilnya — query adalah ikatan hidup, bukan pemindaian sekali jalan.

**Adopsinya khusus client.** `ScreenGui` bertag memang ada juga di server, tapi mengikat
event-nya di sana akan tidak berguna sekaligus menyesatkan: **peristiwa UI adalah sebuah
permintaan**, dan otoritasnya adalah kontrak perintah yang dituju permintaan itu, tidak pernah
tombol yang mengirimnya.

Selengkapnya di [Adopsi dan Tag](UI-ADOPTION.md) dan [Cakupan Adapter](UI-ADAPTERS.md).

---

## 4. Bridge

| Arah | API | Bentuk |
| --- | --- | --- |
| Core → UI | `Publish` / `Subscribe` / `Peek` | ditahan, jadi pelanggan yang telat tetap dapat nilai sekarang |
| UI → Core | `Dispatch` | kirim dan lupakan, tidak pernah yield |
| UI → Core | `Invoke` | permintaan/balasan, yield, kontrak harus mengizinkan |
| mana pun | `Handle` | memasang handler di realm pemilik perintahnya |

Penahanan itulah yang membuat urutan adopsi tidak relevan: elemen yang ditandai tiga puluh
detik setelah sebuah nilai diterbitkan tetap merender state sekarang di frame pertamanya.

Yang menentukan sebuah dispatch tetap lokal atau menyeberang kabel adalah `Realm` milik
perintahnya, **bukan pemanggilnya**. Baris kode client yang sama bekerja untuk keduanya.

Selengkapnya di [API Bridge](API-BRIDGE.md).

---

## 5. Model keamanan

Bentuknya, dalam delapan poin. Rinciannya di [Keamanan Remote](REMOTE-SECURITY.md).

- **Tolak secara bawaan.** Tanpa `AllowClient = true`, tidak ada akses client.
- **Pemeriksaan client adalah kenyamanan; pemeriksaan server adalah kontrolnya.** Client
  menolak mengirim perintah yang tidak sah supaya kesalahannya muncul saat pengembangan, dan
  server melakukan pemeriksaan yang identik saat kedatangan tanpa peduli apa yang dilakukan
  client.
- **Identitas datang dari transport.** Pemainnya adalah yang ditaruh Roblox di argumen pertama
  callback remote, tidak pernah sebuah field di payload.
- **Payload adalah data biasa, dan dibatasi.** Divalidasi terhadap `ArgumentSpec` — tipe,
  panjang string, batas dan kefinitan angka, kedalaman dan lebar tabel. Tidak ada Instance,
  tidak ada fungsi, tidak ada metatable, tidak ada siklus.
- **Dua batas laju.** Per pemain per perintah, ditambah jatah global per pemain, supaya banyak
  perintah murah tidak bisa dipakai menghindari jatah per perintah.
- **Satu gerbang.** Satu `RemoteEvent` dan satu `RemoteFunction`, keduanya client → server.
  Server tidak pernah meng-invoke client. Replikasi channel adalah event server → client yang
  terpisah.
- **Channel menyatakan sejauh mana dia merambat.** `Server` adalah bawaannya, jadi sebuah
  channel tidak bisa bocor karena kelalaian.
- **Penolakan tidak mengajari client apa pun.** Alasannya dicatat di sisi server; pemanggil
  cuma menerima kegagalan yang kasar.

---

## 6. Siklus hidup sistem

1. `Init(unrest)` untuk setiap sistem, sesuai urutan dependensi.
2. `Start()` untuk setiap sistem, dalam urutan yang sama.
3. `Destroy()` dalam urutan terbalik saat dimatikan.

Kait pembongkarannya `Destroy`, bukan `Stop`, supaya tidak pernah bentrok dengan kata kerja
domain: `MusicSystem:Stop()` menghentikan musiknya, `MusicSystem:Destroy()` memensiunkan
sistemnya.

`Dependencies` adalah cara urutan dinyatakan. Tabel sistem harus menulis field itu walau
kosong (`{} :: { string }`) supaya type checker strict mencocokkannya secara struktural.

Selengkapnya di [API Core](API-CORE.md).

---

## 7. Bootstrap, dan kenapa gerbangnya dibuka terakhir

```luau
-- src/game-server/init.server.luau
require(ReplicatedStorage.Game)                  -- 1. deklarasi kontrak dan preset
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:Register(require(script.Systems.Greeter)) -- 2. daftarkan sistem
local unrest = Unrest:Start()                    -- 3. Init lalu Start
unrest:OpenGateway()                             -- 4. remote muncul
```

Remote baru muncul saat gerbang dinyalakan. Menyalakannya **terakhir** berarti permintaan
paling awal yang bisa dikirim client pun sudah pasti menemukan seluruh handler terpasang —
karena handler dipasang di `Init`, dan `Init` selesai di baris 3.

Tidak ada jendela waktu di mana pintunya terbuka dan ruangannya kosong.

---

## 8. Catatan type checker saat memperluas

Tiga pola yang dipaksakan checker strict:

- Tabel sistem harus menulis `Dependencies` walau kosong, atau dia tidak akan cocok dengan
  `Types.System` secara struktural.
- Field state butuh tipe eksplisit di literal tabel awalnya: `_sound = nil :: Sound?`.
- Sebuah metode harus didefinisikan sebelum metode yang memanggilnya, karena tipe `self`
  tumbuh seiring berkasnya dibaca.

---

## 9. Peta berkas

```
src/shared/            ReplicatedStorage.Unrest — direplikasi, anggap setiap client membacanya
  init.luau            composition root; singleton-nya
  Primitives.luau      tipe Signal/Scope/Connection, nol require
  Types.luau           permukaan tipe publik, meng-export ulang dua di bawah
  Constants.luau       tag, nama atribut, nama remote, batas keras
  Util/                Signal, Scope (Scythe), Resolver
  Core/init.luau       registry sistem dan siklus hidupnya
  Bridge/init.luau     publish/subscribe, dispatch/invoke, perutean jaringan
  Net/                 Types, Contracts, Client, Validate, Transport — pengetahuan publik saja
  Net/Transports/      transport bawaan di atas remote Roblox
  Adapters/            registry, adapter per kelas, selector, mesin query
  Presets.luau         bundel atribut bernama; kosong sampai game mengisinya
  Elements/init.luau   adopsi UI Studio bertag (khusus client saat runtime)

src/server/            ServerScriptService.Unrest — tidak pernah direplikasi
  Net/Server.luau      gerbang otoritatif

src/game/              ReplicatedStorage.Game — punyamu, dibaca kedua realm
  init.luau            pintu depan; meng-require-nya mendeklarasikan semuanya
  Names.luau           nama channel dan perintah
  Contracts.luau       kebijakan, sebagai data
  Presets.luau         bundel atribut
  Types.luau           bentuk sistem game ini
  Packets.luau         format kabel game ini
  Transport.luau       transport ByteNet, sebagai TransportProvider

src/game-server/       ServerScriptService.Game — punyamu, server
  init.server.luau     bootstrap server
  Systems/             sistem-sistem game ini

src/game-client/       StarterPlayer.StarterPlayerScripts.Game — punyamu, client
  init.client.luau     bootstrap client
```
