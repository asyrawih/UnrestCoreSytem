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

# Peta API

Halaman ini adalah daftar isi untuk bagian referensi API. Setiap nama di sini diverifikasi
langsung terhadap `src/shared/Types.luau`, yang merupakan sumber kebenaran permukaan publik
framework.

> **Tentang contohnya.** Nama seperti `Toko.Beli`, `Koin`, atau `Dompet` yang muncul di
> halaman-halaman ini adalah **isi game contoh** di `src/game-server` dan `src/game-client`,
> bukan API framework. Framework tidak mendeklarasikan satu perintah, satu channel, satu
> preset, atau satu sistem pun. Yang framework bawa cuma kata-kata umumnya: `System`,
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
├── Bridge     -- publish/subscribe dan dispatch/handle, bus lokal
├── Adapters   -- pengetahuan per-ClassName tentang UI Roblox
├── Elements   -- adopsi UI Studio dan mesin query (client saja)
├── Widgets    -- kontrol berbagian-banyak: slider, toggle (client saja)
└── Scope      -- pustaka cleanup, di-export ulang supaya salinannya cuma satu
```

Satu modul lagi di-`require` langsung, bukan lewat singleton:

```luau
local Presets = require(ReplicatedStorage.Unrest.Presets)
```

---

## Halaman-halamannya

| Halaman | Isinya |
| --- | --- |
| [Unrest](API-UNREST.md) | Singleton-nya: `Start`, `Stop`, `IsStarted`, `Register`, `Get`, `Query`, `Dispatch`, dan field `Version`, `Context`, `Tag`, `Core`, `Bridge`, `Adapters`, `Elements`, `Widgets`, `Scope` |
| [Bridge](API-BRIDGE.md) | `Publish`, `Subscribe`, `Peek`, `Dispatch`, `Handle`, `Destroy` |
| [Core](API-CORE.md) | `Register`, `Get`, `Expect`, `Has`, `List`, `Start`, `Stop`, `IsStarted`, dan tipe `System` |
| [Elements & Query](API-ELEMENTS.md) | `ElementManager`, `Descriptor`, `QueryHandle`, `ManagedElement` |
| [Widgets](API-WIDGETS.md) | `Each`, `Drag`, `WidgetSpec`, `WidgetParts`, `Scope` |
| [Adapters](API-ADAPTERS.md) | `AdapterRegistry`, tipe `Adapter`, cara mendaftarkan kelas baru |
| [Presets](API-PRESETS.md) | `Register`, `Get`, `List` |

---

## Cheat sheet

Yang paling sering dipakai, dalam satu tabel.

| Kamu mau | Tulis |
| --- | --- |
| Menyalakan framework | `local unrest = require(ReplicatedStorage.Unrest):Start()` |
| Mendaftarkan sistem | `unrest:Register(mySystem)` |
| Mengambil sistem | `local dompet = unrest:Get("Dompet") :: Dompet.Dompet` |
| Mengirim niat | `unrest:Dispatch("Toko.Beli", "Pedang")` |
| Memasang handler | `unrest.Bridge:Handle("Toko.Beli", fn)` |
| Menerbitkan state | `unrest.Bridge:Publish("Koin", 120)` |
| Berlangganan state | `unrest.Bridge:Subscribe("Koin", fn)` |
| Membaca nilai terakhir sebuah channel | `unrest.Bridge:Peek("Koin")` |
| Memilih elemen UI | `unrest:Query({ Tag = unrest.Tag, Role = "Beli" }, { Active = fn })` |
| Merakit slider / toggle | `unrest.Widgets:Each({ Required = { ... }, OnReady = fn })` |
| Mendaftarkan preset | `Presets.Register("TombolUtama", { ... })` |
| Membereskan koneksi sekaligus | `unrest.Scope.destroy(scope)` |

---

## Catatan pemanggilan

**Titik dua, bukan titik.** Hampir semua yang ada di halaman-halaman ini adalah metode:
`unrest:Start()`, `bridge:Publish(...)`, `unrest.Widgets:Each(...)`. Pengecualiannya adalah
modul `Presets` (`Presets.Register`, `Presets.Get`, `Presets.List`), fungsi bantu
`Elements.describe`, dan seluruh `unrest.Scope` (`Scope.scope()`, `Scope.add(...)`,
`Scope.destroy(...)`) — semuanya dipanggil dengan titik.

**`Types.luau` adalah modul tipe saja.** Dia mengembalikan tabel kosong yang dibekukan. Kamu
meng-`require`-nya untuk tipenya, bukan untuk nilainya:

```luau
local Types = require(ReplicatedStorage.Unrest.Types)
local descriptor: Types.Descriptor = { Tag = "Unrest", Selector = "TextButton" }
```
