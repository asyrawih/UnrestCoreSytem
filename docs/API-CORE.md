# API — `Core` dan `System`

`Core` adalah registry sistem dan pemilik siklus hidupnya.

```luau
local core = unrest.Core
```

Definisi tipenya ada di `src/shared/Types.luau`, `export type Core` dan `export type System`.

---

## `System` — titik perluasan framework

Sebuah **System** adalah sepotong logika game yang memiliki state. Dia hidup di server. Dia
tidak pernah menyentuh Instance, tidak pernah tahu ada tombol, tidak pernah tahu ada layar.

Itu satu-satunya titik perluasan yang framework punya, dan `Core:Register` adalah pintunya.

```luau
export type System = {
    Name: string,
    Dependencies: { string }?,
    Init: ((self: any, unrest: Unrest) -> ())?,
    Start: ((self: any) -> ())?,
    Destroy: ((self: any) -> ())?,
}
```

| Field | Wajib? | Arti |
| --- | --- | --- |
| `Name` | **ya** | Kunci registry. String tidak kosong, dan unik. |
| `Dependencies` | opsional secara runtime | Nama sistem yang harus jalan lebih dulu. **Tulis saja walau kosong.** |
| `Init` | opsional | Dipanggil dengan singleton. Pasang `Bridge:Handle` di sini. |
| `Start` | opsional | Dipanggil setelah semua `Init` selesai. |
| `Destroy` | opsional | Pembongkaran, dalam urutan terbalik. |

### Kenapa `Destroy`, bukan `Stop`

Supaya tidak bentrok dengan kata kerja domain. `MusicSystem:Stop()` menghentikan musiknya;
`MusicSystem:Destroy()` selalu berarti framework sedang memensiunkan sistemnya. Dua hal itu
tidak boleh memakai satu nama.

### Kenapa `Dependencies` sebaiknya selalu ditulis

Secara runtime dia opsional. Tapi type checker strict mencocokkan tabel secara struktural,
dan tanpa field itu tabelmu tidak akan cocok dengan `Types.System`. Tulis
`Dependencies = {} :: { string }` walau kosong.

### Sistem terkecil yang tetap jalan

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UnrestTypes = require(ReplicatedStorage.Unrest.Types)

local Greeter = {
    Name = "Greeter",
    Dependencies = {} :: { string },
}

function Greeter:Init(unrest: UnrestTypes.Unrest): ()
    unrest.Bridge:Handle("Greet.Say", function(source, payload)
        return `halo {payload}`
    end)
end

return Greeter
```

### Mengekspor tipenya

Framework **tidak membawa tipe sistem game-mu**, dan itu disengaja: framework tidak
seharusnya tahu sistem sebuah game bernama apa. Jadi ekspor tipenya dari modul sistem itu
sendiri, atau dari `src/game/Types.luau`:

```luau
export type MusicSystem = UnrestTypes.System & {
    NowPlayingChanged: UnrestTypes.Signal<string?>,
    Play: (self: MusicSystem, name: string) -> boolean,
    Stop: (self: MusicSystem) -> (),
}
```

Lalu di tempat pemakaian:

```luau
local music = unrest:Get("MusicSystem") :: GameTypes.MusicSystem
```

---

## Siklus hidup

Tiga fase, dan urutannya penting:

1. **`Init(unrest)`** untuk setiap sistem, sesuai urutan dependensi.
2. **`Start()`** untuk setiap sistem, dalam urutan yang sama.
3. **`Destroy()`** dalam urutan **terbalik** saat dimatikan.

Dua fase pertama dipisah karena satu alasan praktis: saat `Start()` sebuah sistem berjalan,
setiap sistem lain **sudah** selesai `Init`. Jadi `Init` adalah tempat mendaftarkan diri
(`Bridge:Handle`, `Bridge:Subscribe`), dan `Start` adalah tempat mulai bekerja dan memanggil
sistem lain.

---

## Metode

### `Core:Register(definition: System): System`

Mendaftarkan sistem. Mengembalikan tabel yang kamu berikan.

```luau
unrest.Core:Register(require(script.Systems.Greeter))
-- sama dengan
unrest:Register(require(script.Systems.Greeter))
```

Yang divalidasi saat pendaftaran: `definition` harus tabel, `Name` harus string tidak kosong,
`Dependencies` (kalau ada) harus tabel berisi nama tidak kosong dan **tidak boleh menyebut
dirinya sendiri**, dan `Init`/`Start`/`Destroy` (kalau ada) harus fungsi.

**Jebakan:**

* Nama yang sudah dipakai **melempar error**. Nama sistem adalah kunci registry, jadi harus
  unik.
* **Mendaftar setelah `Start()` diizinkan**, tapi setiap dependensinya harus sudah berjalan.
  Kalau belum, pendaftarannya dibatalkan dan `Register` melempar error. Sistem yang
  didaftarkan terlambat langsung di-`Init` lalu di-`Start` saat itu juga.

### `Core:Get(name: string): System?`

Sistem bernama itu, atau `nil`.

```luau
local maybe = unrest.Core:Get("MusicSystem")
if maybe ~= nil then
    -- ada
end
```

### `Core:Expect(name: string): System`

Sama seperti `Get`, tapi **melempar error** kalau tidak ada — dengan pesan yang menyebutkan
semua sistem terdaftar, supaya salah ketik langsung kelihatan.

`Unrest:Get` adalah ini, bukan `Core:Get`.

```luau
local music = unrest.Core:Expect("MusicSystem")
```

### `Core:Has(name: string): boolean`

Apakah sistem itu terdaftar.

```luau
if unrest.Core:Has("MusicSystem") then
    unrest:Dispatch("Music.Play", "Lobby")
end
```

### `Core:List(): { string }`

Nama sistem terdaftar, **dalam urutan dependensi** — bukan urutan pendaftaran, dan bukan
urutan abjad. Ini urutan yang sama dengan urutan `Init` dan `Start` dijalankan.

```luau
print(table.concat(unrest.Core:List(), ", "))
```

### `Core:Start(unrest: Unrest): ()`

Menjalankan seluruh siklus hidup. **Jangan panggil ini langsung** — `Unrest:Start()` yang
memanggilnya, dan `Core:Start` melempar error kalau dipanggil dua kali.

### `Core:Stop(): ()`

Memanggil `Destroy()` pada setiap sistem dalam urutan terbalik. Aman dipanggil saat belum
berjalan.

### `Core:IsStarted(): boolean`

Apakah siklus hidupnya sedang berjalan.

---

## `SystemAdded: Signal<System>`

Menyala setiap kali sebuah sistem berhasil didaftarkan.

```luau
unrest.Core.SystemAdded:Connect(function(system)
    print("terdaftar:", system.Name)
end)
```

Berguna untuk alat bantu dan untuk sistem "plugin" yang memuat sistem lain saat runtime.

---

## Catatan type checker

Tiga pola yang dipaksakan checker strict saat kamu menulis sistem:

1. **`Dependencies` harus ditulis walau kosong**, atau tabelmu tidak cocok dengan
   `Types.System` secara struktural.
2. **Field state butuh tipe eksplisit di literal tabel awalnya:**
   `_sound = nil :: Sound?`. Tanpa anotasi, tipenya terkunci jadi `nil`.
3. **Sebuah metode harus didefinisikan sebelum metode yang memanggilnya**, karena tipe `self`
   tumbuh seiring berkasnya dibaca dari atas ke bawah.
