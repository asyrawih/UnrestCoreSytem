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

### `Widgets: WidgetLibrary`

Kontrol berbagian-banyak: slider, toggle, apa pun yang bagian-bagiannya baru berarti kalau
digabung. Ini lapisan yang dicari **sebelum** menulis query sendiri. **Client saja** —
memanggilnya di server raise. Lihat [API Widgets](API-WIDGETS.md).

### `Scope: ScopeLibrary`

Pustaka cleanup framework ([Scythe](https://github.com/synttx/scythe)), di-export ulang di
sini. Sebuah scope itu **angka**, bukan objek: simpan di field biasa, oper ke mana saja.

```luau
local scope = unrest.Scope.scope()
unrest.Scope.add(scope, unrest.Bridge:Subscribe("Koin", perbarui))
unrest.Scope.destroy(scope)   -- semuanya lepas sekaligus
```

Ambil dari sini, **jangan** `require(ReplicatedStorage.Packages.Scythe)` sendiri. Scythe
menyimpan datanya di upvalue modul, jadi dua salinan modul berarti dua semesta handle yang
terpisah — handle dari yang satu, di mata yang lain, adalah slot milik orang lain. Lewat
`unrest.Scope` salinannya dijamin cuma satu.

---

## Metode siklus hidup

### `Unrest:Start(): Unrest`

Menyalakan framework. Mengembalikan singleton itu sendiri, jadi bisa dirantai.

Yang dilakukannya, berurutan:

1. **UI diadopsi** — hanya di client. `Elements:Start()` dipanggil. Di server langkah ini
   dilewati: ScreenGui yang ditandai memang ada di sana, tapi tidak ada yang pernah
   mengkliknya.
2. **Sistem dijalankan.** `Core:Start(unrest)` menjalankan `Init(unrest)` untuk setiap sistem
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

Yang **tidak** dilakukannya: dia tidak merobohkan Bridge dan tidak melepas UI yang diadopsi.
Ini pematian sistem, bukan pematian framework.

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

### Tidak ada metode jaringan, dan itu disengaja

Kalau kamu mencari `OpenGateway`, `UseTransport`, atau `Invoke` — semuanya sudah tidak ada.
Framework ini **bukan lapisan jaringan**. Bridge-nya bus lokal: `Dispatch` di client hanya
menjangkau handler di client itu juga.

Remote adalah urusan game-mu. Di repo ini, game contohnya memakai ByteNet di
`src/game-net`, dan pola sambungannya cuma dua baris — server mendengarkan paket lalu
`Dispatch`, client mendengarkan paket lalu `Publish`:

```luau
-- server: paket masuk jadi niat
GameNet.packets.Beli.listen(function(data, player: Player?)
    if player == nil or typeof(data) ~= "table" or typeof(data.Barang) ~= "string" then
        return
    end
    unrest.Bridge:Dispatch("Toko.Beli", { Player = player, Item = data.Barang })
end)

-- client: paket masuk jadi state yang bisa diikuti UI
GameNet.packets.Koin.listen(function(data)
    unrest.Bridge:Publish("Koin", data.Nilai)
end)
```

**Identitas tidak pernah datang dari pesannya.** `player` di atas adalah argumen kedua yang
diserahkan ByteNet, diteruskan apa adanya dari `OnServerEvent`, jadi Roblox yang mengisinya.
Paket `Beli` sengaja tidak punya field pemain, dan memang tidak boleh punya.

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

Perintah tanpa satu pun handler adalah **no-op yang diam**, bukan error. Layar sering dibangun
sebelum kode di belakangnya, dan tombol yang belum melakukan apa-apa tidak seharusnya
memuntahkan peringatan tiap kali diklik.

Lihat [API Bridge](API-BRIDGE.md).

---

## Urutan yang benar, sekali lagi

```luau
-- src/game-server/init.server.luau
local GameNet = require(ReplicatedStorage.GameNet)
local Unrest = require(ReplicatedStorage.Unrest)

Unrest:Register(require(script.Systems.Dompet))   -- 1. daftarkan sistem
Unrest:Register(require(script.Systems.Toko))

local unrest = Unrest:Start()                     -- 2. Init lalu Start setiap sistem

GameNet.packets.Beli.listen(function(data, player: Player?)  -- 3. baru dengarkan paket
    ...
end)
```

```luau
-- src/game-client/init.client.luau
local Unrest = require(ReplicatedStorage.Unrest)

local unrest = Unrest:Start()                     -- 1. UI bertag diadopsi
require(script.Shop)(unrest)                      -- 2. muat fiturnya
```

**Urutannya membawa makna.** Di server, `Start` yang menjalankan `Init` setiap sistem, dan di
situlah `Bridge:Handle` dipanggil. Mendengarkan paket **sesudahnya** berarti permintaan
paling awal yang bisa dikirim pemain pun pasti menemukan handler-nya sudah terpasang; kalau
dibalik, ada jendela waktu di mana pesan datang tapi tidak ada yang bisa menjawabnya.

Di client urutannya lebih longgar: setiap fitur mengikat lewat `Unrest:Query`, dan itu
ikatan hidup — elemen yang ditandai sepuluh menit lagi tetap terikat sepuluh menit lagi.
