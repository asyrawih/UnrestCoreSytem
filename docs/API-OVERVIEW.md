# Peta API

Halaman ini adalah daftar isi untuk bagian referensi API. Setiap nama di sini diverifikasi
langsung terhadap `src/shared/Types.luau`, yang merupakan sumber kebenaran permukaan publik
framework.

> **Tentang contohnya.** Nama seperti `Music.Play`, `Music.NowPlaying`, atau `MusicSystem`
> yang muncul di halaman-halaman ini adalah **isi game contoh** di `src/game`, bukan API
> framework. Framework tidak mendeklarasikan satu perintah, satu channel, satu preset, atau
> satu sistem pun. Yang framework bawa cuma kata-kata umumnya: `System`, `Contracts`,
> `Bridge`, `Descriptor`.

---

## Cara membaca bagian ini

Framework mengekspor **satu objek**: singleton `Unrest`. Semua yang lain dijangkau lewat
field pada objek itu, atau lewat modul yang kamu `require` langsung.

```luau
local Unrest = require(ReplicatedStorage.Unrest)
```

Objek itu satu per runtime context. Ada satu di server, dan satu di setiap client.

```
Unrest
├── Core       -- registry sistem dan siklus hidupnya
├── Bridge     -- publish/subscribe, dispatch/invoke, batas jaringan
├── Adapters   -- pengetahuan per-ClassName tentang UI Roblox
└── Elements   -- adopsi UI Studio dan mesin query (client saja)
```

Dua modul lagi di-`require` langsung, bukan lewat singleton:

```luau
local Contracts = require(ReplicatedStorage.Unrest.Net.Contracts)
local Presets = require(ReplicatedStorage.Unrest.Presets)
```

`Contracts` juga tersedia sebagai `Unrest.Bridge.Contracts` — objek yang sama persis, jadi
tidak ada dua registry yang bisa berbeda pendapat.

---

## Halaman-halamannya

| Halaman | Isinya |
| --- | --- |
| [Unrest](API-UNREST.md) | Singleton-nya: `Start`, `Stop`, `IsStarted`, `Register`, `Get`, `Query`, `Dispatch`, `Invoke`, `UseTransport`, `OpenGateway`, dan field `Version`, `Context`, `Tag`, `Core`, `Bridge`, `Adapters`, `Elements` |
| [Bridge](API-BRIDGE.md) | `Publish`, `Subscribe`, `Peek`, `Dispatch`, `Invoke`, `Handle`, `Destroy`, sinyal `Rejected` |
| [Core](API-CORE.md) | `Register`, `Get`, `Expect`, `Has`, `List`, `Start`, `Stop`, `IsStarted`, dan tipe `System` |
| [Elements & Query](API-ELEMENTS.md) | `ElementManager`, `Descriptor`, `QueryHandle`, `ManagedElement` |
| [Adapters](API-ADAPTERS.md) | `AdapterRegistry`, tipe `Adapter`, cara mendaftarkan kelas baru |
| [Contracts](API-CONTRACTS.md) | `Declare`, `DeclareChannel`, `ArgumentSpec`, `CommandContract`, `ChannelContract` |
| [Presets](API-PRESETS.md) | `Register`, `Get`, `List` |
| [Transport](API-TRANSPORT.md) | `TransportProvider`, `ServerTransport`, `ClientTransport` |

---

## Cheat sheet

Yang paling sering dipakai, dalam satu tabel.

| Kamu mau | Tulis |
| --- | --- |
| Menyalakan framework | `local unrest = require(ReplicatedStorage.Unrest):Start()` |
| Membuka gerbang (server saja) | `unrest:OpenGateway()` |
| Mendaftarkan sistem | `unrest:Register(mySystem)` |
| Mengambil sistem | `local music = unrest:Get("MusicSystem") :: GameTypes.MusicSystem` |
| Mengirim niat, tanpa balasan | `unrest:Dispatch("Music.Play", "Lobby")` |
| Mengirim niat, menunggu balasan | `local result = unrest:Invoke("Music.Play", "Lobby")` |
| Memasang handler (di realm pemiliknya) | `unrest.Bridge:Handle("Music.Play", fn)` |
| Menerbitkan state | `unrest.Bridge:Publish("Music.NowPlaying", "Lobby")` |
| Berlangganan state | `unrest.Bridge:Subscribe("Music.NowPlaying", fn)` |
| Membaca nilai terakhir sebuah channel | `unrest.Bridge:Peek("Music.NowPlaying")` |
| Memilih elemen UI | `unrest:Query({ Tag = unrest.Tag, Role = "Play" }, { Active = fn })` |
| Mendeklarasikan perintah | `Contracts:Declare({ Name = ..., Realm = "Server" })` |
| Mendaftarkan preset | `Presets.Register("MusicToggle", { ... })` |
| Mengganti transport | `Unrest:UseTransport(provider)` sebelum `:Start()` |

---

## Catatan pemanggilan

**Titik dua, bukan titik.** Hampir semua yang ada di halaman-halaman ini adalah metode:
`unrest:Start()`, `bridge:Publish(...)`, `Contracts:Declare(...)`. Dua pengecualian adalah
modul `Presets` (`Presets.Register`, `Presets.Get`, `Presets.List`) dan fungsi bantu
`Elements.describe`, yang keduanya dipanggil dengan titik.

**`Types.luau` adalah modul tipe saja.** Dia mengembalikan tabel kosong yang dibekukan. Kamu
meng-`require`-nya untuk tipenya, bukan untuk nilainya:

```luau
local Types = require(ReplicatedStorage.Unrest.Types)
local descriptor: Types.Descriptor = { Tag = "Unrest", Selector = "TextButton" }
```
