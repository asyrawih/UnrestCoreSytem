# API — `Transport`

Transport adalah sambungan antara **kebijakan** framework dan **cara byte benar-benar
bergerak**.

Bawaannya remote Roblox. Kamu bisa menggantinya dengan pustaka apa pun — ByteNet, misalnya —
tanpa menyentuh satu baris pun kode framework.

Definisi tipenya ada di `src/shared/Net/Transport.luau`, di-`export` ulang lewat
`src/shared/Types.luau`.

---

## Aturan arah, dan kenapa itu keamanan

> **Transport tidak memutuskan apa pun.** Dia tidak pernah menjalankan handler, tidak pernah
> membaca kontrak, dan tidak pernah tahu apakah sebuah client boleh meminta hal yang baru
> saja dia antar. Dia menyerahkan permintaan mentah ke gerbang, dan gerbang yang menjawab.

Arah itulah seluruh sifat keamanannya. Kalau dibalik — kalau transport ikut memutuskan —
setiap transport baru jadi jalan pintas baru mengelilingi gerbang.

Seperti yang tertulis sekarang, hal terburuk yang bisa dilakukan sebuah transport adalah
mengantar sampah. Dan gerbang menolak sampah dari transport persis seperti dia menolak sampah
dari mana pun.

Sepuluh metode, lima per sisi, dan sengaja tidak lebih. Validasi, batas laju, otorisasi,
penghitung penyalahgunaan, dan penahanan channel semuanya tetap di framework.

---

## Memasangnya

```luau
local Unrest = require(ReplicatedStorage.Unrest)
Unrest:UseTransport(require(ReplicatedStorage.Game.Transport))
local unrest = Unrest:Start()
```

**Harus di antara `require` dan `:Start()`.** Jendela itu nyata: setengah-client dipasang
saat `require`, tapi transport di bawahnya baru dibangun pada `:Start()` atau pada dispatch
pertama, mana yang lebih dulu. Memasangnya setelah itu **melempar error**, bukan diam-diam
meninggalkan separuh trafik di kabel lama.

Tidak ada pencampuran per-perintah. **Satu transport membawa semuanya** — setiap perintah dan
setiap channel.

Pasang di **kedua** bootstrap. Hanya sisi yang cocok dengan context sekarang yang akan
dibangun, jadi client tidak pernah membangun setengah-server dan sebaliknya.

### Kenapa bukan argumen `require`

`require` tidak menerima argumen, dan modul ini adalah singleton yang dibangun saat
di-`require`. Jadi tidak ada panggilan konstruktor tempat sebuah game bisa mengoper
transport.

Pilihan jujurnya tinggal dua: sebuah setter, atau modul kedua yang harus di-`require` sebelum
modul ini. Dan "require A sebelum B atau jaringannya berubah diam-diam" adalah jenis aturan
urutan yang dipatuhi selama sebulan.

Jadi: `Unrest:UseTransport(provider)`, sah di antara `require` dan `:Start()`, dengan bawaan
remote.

---

## `TransportProvider`

Yang kamu serahkan ke framework:

```luau
export type TransportProvider = {
    Name: string,
    Server: (() -> ServerTransport)?,
    Client: (() -> ClientTransport)?,
}
```

| Field | Arti |
| --- | --- |
| `Name` | Nama transport, untuk pesan galat. **Wajib string.** |
| `Server` | Pabrik setengah-server. Dipanggil hanya di server. |
| `Client` | Pabrik setengah-client. Dipanggil hanya di client. |

Kedua pabriknya opsional karena tidak ada realm yang punya keduanya. Bentuk yang khas:

```luau
-- src/game/Transport.luau
return table.freeze({
    Name = "ByteNet",
    Server = newServer,
    Client = newClient,
})
```

Modulnya mengembalikan provider itu sendiri, jadi memasangnya cukup satu baris.

---

## `ServerTransport`

```luau
export type ServerTransport = {
    Start: (self: ServerTransport) -> (),
    OnRequest: (self: ServerTransport, handler: RequestHandler) -> (),
    OnRefusal: (self: ServerTransport, report: RefusalReporter) -> (),
    PublishTo: (self: ServerTransport, player: Player, channel: string, value: any) -> (),
    PublishAll: (self: ServerTransport, channel: string, value: any) -> (),
    Destroy: (self: ServerTransport) -> (),
}
```

| Metode | Kewajibanmu |
| --- | --- |
| `OnRequest(handler)` | Simpan gerbangnya. Dipanggil **sekali, sebelum `Start`**. |
| `OnRefusal(report)` | Simpan pelapornya. Opsional untuk dipakai. |
| `Start()` | Mulai mendengarkan. |
| `PublishTo(player, channel, value)` | Kirim satu nilai ke satu pemain. |
| `PublishAll(channel, value)` | Kirim satu nilai ke semua orang. |
| `Destroy()` | Bersihkan. |

### `RequestHandler`

```luau
export type RequestHandler = (player: Player, command: string, payload: any, wantsResponse: boolean) -> InvokeResult
```

Yang didaftarkan gerbang ke transport-mu. Panggil ini setiap kali sebuah permintaan tiba.

> **`player` datang dari pengetahuan transport sendiri tentang siapa yang mengirim, tidak
> pernah dari payload.** Transport yang tidak bisa memastikan siapa pengirim sebuah pesan
> **tidak boleh mengantarnya sama sekali.**

### `RefusalReporter`

```luau
export type RefusalReporter = (player: Player?, command: string?, reason: RejectionReason, detail: string) -> ()
```

Cara transport melaporkan sesuatu yang dia buang sebelum gerbang sempat melihatnya — buffer
yang gagal dideserialisasi, pesan yang bentuknya salah untuk kabel ini.

Transport **boleh membuang**; transport **tidak boleh memutuskan apa artinya**. Laporannya
ada supaya pesan yang dibuang tetap sampai ke penghitung penyalahgunaan, alih-alih tidak
terlihat oleh satu-satunya bagian sistem yang sedang menghitung.

---

## `ClientTransport`

```luau
export type ClientTransport = {
    Start: (self: ClientTransport) -> (),
    Send: (self: ClientTransport, command: string, payload: any) -> (),
    Request: (self: ClientTransport, command: string, payload: any) -> InvokeResult,
    OnPublish: (self: ClientTransport, handler: PublishHandler) -> (),
    Destroy: (self: ClientTransport) -> (),
}
```

| Metode | Kewajibanmu |
| --- | --- |
| `Start()` | Mulai. |
| `Send(command, payload)` | Kirim dan lupakan. **Tidak boleh yield.** |
| `Request(command, payload)` | Permintaan dan balasan. Yield. |
| `OnPublish(handler)` | Simpan handler untuk nilai channel yang direplikasi. |
| `Destroy()` | Bersihkan. |

### `PublishHandler`

```luau
export type PublishHandler = (channel: string, value: any) -> ()
```

### Tentang `Request`

Cara perjalanan bolak-baliknya dibangun adalah **urusan transport**. Remote punya mekanisme
itu secara bawaan; pustaka paket butuh dua paket dan sebuah id korelasi.

Framework hanya menyediakan tenggat waktunya, `Constants.Limits.InvokeTimeout` (10 detik),
dan memperlakukan jawaban yang tidak datang sebagai **timeout**, bukan penolakan — karena
framework tidak bisa membedakan keduanya dan tidak boleh menebak.

---

## Transport bawaan

Kalau kamu tidak memanggil `UseTransport`, framework memakai remote Roblox. Tiga objek
tereplikasi, dan tidak pernah lebih:

| Objek | Arah | Untuk apa |
| --- | --- | --- |
| `UnrestDispatch` (`RemoteEvent`) | client → server | Kirim dan lupakan. |
| `UnrestInvoke` (`RemoteFunction`) | client → server | Permintaan/balasan. |
| `UnrestPublish` (`RemoteEvent`) | server → client | Replikasi channel. |

Ketiganya hidup di folder `UnrestRemotes`. Nama-namanya ada di `Constants.Remotes`.

**Tidak ada fungsi server → client, dan itu disengaja.**
`RemoteFunction:InvokeClient` menyerahkan thread milik server ke mesin yang tidak dikendalikan
server, tanpa timeout yang bisa dipasang padanya. Client yang cukup dengan tidak pernah
menjawab akan menggantung thread itu selamanya.

---

## Menulis transport-mu sendiri

Bentuk minimalnya:

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Unrest.Types)

local function newServer(): Types.ServerTransport
    local onRequest: Types.RequestHandler? = nil
    local server = {}

    function server:OnRequest(handler: Types.RequestHandler): ()
        onRequest = handler
    end

    function server:OnRefusal(_report: Types.RefusalReporter): () end

    function server:Start(): ()
        -- mulai mendengarkan; setiap pesan yang masuk memanggil:
        --   onRequest(player, command, payload, wantsResponse)
    end

    function server:PublishTo(player: Player, channel: string, value: any): () end
    function server:PublishAll(channel: string, value: any): () end
    function server:Destroy(): () end

    return (server :: any) :: Types.ServerTransport
end

return table.freeze({
    Name = "MilikSaya",
    Server = newServer,
    Client = nil,
})
```

Contoh nyata yang lengkap ada di `src/game/Transport.luau` dan `src/game/Packets.luau` —
sebuah transport ByteNet, ditulis sepenuhnya di sisi game. Framework tidak punya ketergantungan
pada pustaka jaringan mana pun, dan tidak boleh pernah punya.

### Kalau kamu memakai skema per perintah

Taruh definisi paketnya di field `Wire` kontrak perintah itu — di baris yang sama dengan
kebijakan yang mengaturnya. Framework membawanya apa adanya dan tidak pernah membacanya.
Lihat [API Contracts](API-CONTRACTS.md).

Amplop generik — satu paket `Request` yang membawa nama perintah dan buffer payload buram —
membuat mendeklarasikan perintah baru tidak berbiaya apa pun di kabel. Paket bertipe per
perintah adalah optimasi setelahnya, bukan sebelumnya.
