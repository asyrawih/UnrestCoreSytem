# API — `Unrest`

Singleton framework. Meng-`require` `ReplicatedStorage.Unrest` memberimu objek ini; ada satu
per runtime context, jadi satu di server dan satu di setiap client.

```luau
local Unrest = require(ReplicatedStorage.Unrest)
```

Definisi tipenya ada di `src/shared/Types.luau`, `export type Unrest`.

---

## Field

### `Version: string`

Versi framework, dari `Constants.Version`. Saat ini `"0.2.0"`.

```luau
print(unrest.Version) --> 0.2.0
```

### `Context: RuntimeContext`

`"Server"` atau `"Client"`. Ditentukan sekali saat modul di-`require`, dari
`RunService:IsServer()`.

Ini yang dibaca framework untuk memutuskan apakah sebuah dispatch tetap lokal atau menyeberang
kabel. Kode game boleh membacanya juga, tapi biasanya tidak perlu: bentuk `Dispatch` yang
sama bekerja di kedua sisi.

```luau
if unrest.Context == "Client" then
    -- kode yang hanya masuk akal di client
end
```

### `Tag: string`

Tag CollectionService yang mengikutsertakan sebuah instance Studio ke framework. Nilainya
`"Unrest"`, dari `Constants.Tag`.

Pakai field ini di dalam descriptor, bukan string harfiah — sekali ditulis, sekali salah:

```luau
unrest:Query({ Tag = unrest.Tag, Selector = "TextButton" }, handlers)
```

### `Core: Core`

Registry sistem dan siklus hidupnya. Lihat [API Core](API-CORE.md).

### `Bridge: Bridge`

Controller, sekaligus batas client/server. Lihat [API Bridge](API-BRIDGE.md).

### `Adapters: AdapterRegistry`

Pengetahuan per-`ClassName` tentang UI Roblox: event mana yang ada, properti mana yang aman
ditulis dari sebuah channel. Daftarkan adapter-mu sendiri untuk kelas kustom. Lihat
[API Adapters](API-ADAPTERS.md).

### `Elements: ElementManager`

UI Studio yang diadopsi. **Hanya berguna di client**; di server objeknya ada, tapi tidak
mengadopsi apa pun. Lihat [API Elements](API-ELEMENTS.md).

---

## Metode siklus hidup

### `Unrest:Start(): Unrest`

Menyalakan framework. Mengembalikan singleton itu sendiri, jadi bisa dirantai.

Yang dilakukannya, berurutan:

1. **Jaringan dinyalakan lebih dulu.** Setengah-client dibangun. Ini terjadi sebelum UI
   diadopsi, karena elemen yang membawa `UnrestCommand` bisa diklik sedetik setelah diadopsi,
   dan dispatch tanpa gerbang di belakangnya adalah klik yang diam-diam hilang.
2. **UI diadopsi** — hanya di client. `Elements:Start()` dipanggil.
3. **Sistem dijalankan.** `Core:Start(unrest)` menjalankan `Init(unrest)` untuk setiap sistem
   sesuai urutan dependensi, lalu `Start()` untuk setiap sistem dalam urutan yang sama.

```luau
local unrest = require(ReplicatedStorage.Unrest):Start()
```

**Aman dipanggil dua kali.** Panggilan kedua langsung mengembalikan singleton tanpa melakukan
apa-apa. Tapi `Core:Start` sendiri melempar error kalau dipanggil dua kali, jadi jangan
memanggilnya langsung.

**Jebakan:** daftarkan sistemmu **sebelum** `:Start()`. Sistem yang didaftarkan setelahnya
tetap diterima, tapi setiap dependensinya harus sudah berjalan — kalau tidak, `Register`
melempar error dan membatalkan pendaftarannya.

### `Unrest:Stop(): ()`

Mematikan sistem-sistem. `Core:Stop()` memanggil `Destroy()` pada setiap sistem dalam urutan
**terbalik**.

Yang **tidak** dilakukannya: dia tidak merobohkan Bridge, tidak melepas UI yang diadopsi, dan
tidak menutup gerbang. Ini pematian sistem, bukan pematian framework.

```luau
unrest:Stop()
```

Aman dipanggil saat belum berjalan — dia langsung kembali.

### `Unrest:IsStarted(): boolean`

Apakah `:Start()` sudah dipanggil dan `:Stop()` belum.

```luau
if not unrest:IsStarted() then
    unrest:Start()
end
```

### `Unrest:OpenGateway(): ()`

**Server saja.** Membangun gerbang otoritatif dan membuat objek remote muncul di DataModel.
Sebelum baris ini jalan, tidak ada jalan bagi client untuk mengirim apa pun.

Panggil ini sebagai **baris terakhir** bootstrap server-mu:

```luau
require(ReplicatedStorage.Game)
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:Register(require(script.Systems.Greeter))
local unrest = Unrest:Start()
unrest:OpenGateway()          -- terakhir, selalu
```

**Kenapa terakhir?** Karena `:Start()` yang menjalankan `Init` setiap sistem, dan di situlah
`Bridge:Handle` dipanggil. Membuka gerbang setelahnya berarti permintaan paling awal yang
bisa dikirim client pun pasti menemukan seluruh handler sudah terpasang. Tidak ada jendela
waktu di mana pintunya terbuka tapi ruangannya kosong.

> Gerbang server tinggal di `ServerScriptService`, jadi dia tidak pernah direplikasi ke mesin
> yang diaturnya. Itu bukan kerapian, itu keamanannya. Lihat
> [Keamanan Remote](REMOTE-SECURITY.md).

### `Unrest:UseTransport(provider: TransportProvider): Unrest`

Mengganti transport bawaan (remote Roblox) untuk **setiap** perintah dan **setiap** channel.
Mengembalikan singleton, jadi bisa dirantai.

```luau
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:UseTransport(require(ReplicatedStorage.Game.Transport))
local unrest = Unrest:Start()
```

**Harus dipanggil di antara `require` dan `:Start()`.** Jendela itu nyata: setengah-client
dipasang saat `require`, tapi transport di bawahnya baru dibangun pada `:Start()` atau pada
dispatch pertama, mana yang lebih dulu. Memasangnya setelah itu **melempar error**, bukan
diam-diam meninggalkan separuh trafik di kabel lama.

Tidak ada pencampuran per-perintah. Satu transport membawa semuanya. Lihat
[API Transport](API-TRANSPORT.md).

---

## Metode sistem

### `Unrest:Register(definition: System): System`

Mendaftarkan sebuah sistem. Sama persis dengan `Unrest.Core:Register`. Mengembalikan tabel
sistem yang kamu berikan.

```luau
Unrest:Register(require(script.Systems.Greeter))
```

Sistem wajib punya `Name` string tidak kosong dan unik. `Dependencies` opsional secara
runtime, tapi **tulis saja walau kosong** (`{} :: { string }`) supaya type checker strict
mengenalinya.

Detail dan siklus hidupnya di [API Core](API-CORE.md).

### `Unrest:Get(name: string): System`

Mengambil sistem terdaftar. **Melempar error** kalau tidak ada, dengan pesan yang menyebutkan
semua sistem yang terdaftar. Ini `Core:Expect`, bukan `Core:Get`.

```luau
local music = unrest:Get("MusicSystem") :: GameTypes.MusicSystem
music:Play("Lobby")
```

**Jebakan:** kembaliannya bertipe `System`, tipe minimum yang dibaca framework. Framework
sengaja tidak membawa tipe sistem game-mu, jadi cast-lah ke tipe yang kamu ekspor sendiri
dari modul sistem itu.

Kalau kamu butuh versi yang mengembalikan `nil` alih-alih melempar error, pakai
`unrest.Core:Get(name)`.

---

## Jalan pintas

Tiga metode berikut hanyalah jalan pintas ke objek di bawahnya. Keduanya benar-benar
identik; yang pendek dipakai supaya kode pemanggil tidak penuh titik.

### `Unrest:Query(descriptor: Descriptor, handlers: Handlers?): QueryHandle`

Jalan pintas untuk `Unrest.Elements:Query`.

```luau
local handle = unrest:Query({
    Tag = unrest.Tag,
    Selector = "GuiButton",
    Role = "ToggleMenu",
}, {
    Active = function(element)
        unrest:Dispatch("Music.Play", "Lobby")
    end,
})
```

Lihat [API Elements](API-ELEMENTS.md) untuk descriptor dan handle-nya.

### `Unrest:Dispatch(command: string, payload: any): ()`

Jalan pintas untuk `Unrest.Bridge:Dispatch`. Kirim niat, tidak menunggu, tidak pernah
yield.

```luau
unrest:Dispatch("Music.Play", "Lobby")
```

### `Unrest:Invoke(command: string, payload: any): InvokeResult`

Jalan pintas untuk `Unrest.Bridge:Invoke`. Kirim niat dan tunggu nilainya. **Yield.**
Kontraknya harus menulis `Response = true`.

```luau
local result = unrest:Invoke("Music.Play", "Lobby")
if result.Ok then
    print("berhasil:", result.Value)
else
    print("ditolak:", result.Reason)
end
```

Lihat [API Bridge](API-BRIDGE.md) untuk keduanya.

---

## Urutan yang benar, sekali lagi

```luau
-- src/game-server/init.server.luau
require(ReplicatedStorage.Game)                  -- 1. deklarasi kontrak dan preset
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:Register(require(script.Systems.Greeter)) -- 2. daftarkan sistem
local unrest = Unrest:Start()                    -- 3. Init lalu Start
unrest:OpenGateway()                             -- 4. remote muncul
```

```luau
-- src/game-client/init.client.luau
require(ReplicatedStorage.Game)                  -- 1. kontrak dan preset, sama persis
local Unrest = require(ReplicatedStorage.Unrest)
local unrest = Unrest:Start()                    -- 2. jaringan hidup, UI diadopsi
```

Kalau kamu memakai transport sendiri, sisipkan `Unrest:UseTransport(...)` tepat sebelum
`:Start()` di **kedua** berkas.
