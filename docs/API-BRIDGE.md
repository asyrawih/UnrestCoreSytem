# API — `Bridge`

`Bridge` adalah controller framework, sekaligus batas client/server. Dia satu-satunya jalan
antara logika game dan layar, dan satu-satunya jalan menyeberang jaringan.

```luau
local bridge = unrest.Bridge
```

Definisi tipenya ada di `src/shared/Types.luau`, `export type Bridge`.

---

## Dua arah, empat kata kerja

```
  Core  ──Publish──▶  Bridge  ──▶  Elemen di Studio
    ▲                   │
    └────Dispatch───────┘
```

| Arah | Metode | Bentuk |
| --- | --- | --- |
| Core → UI | `Publish` / `Subscribe` / `Peek` | ditahan, jadi pelanggan yang telat tetap dapat nilai sekarang |
| UI → Core | `Dispatch` | kirim dan lupakan, tidak pernah yield |
| UI → Core | `Invoke` | permintaan/balasan, yield, kontrak harus mengizinkan |
| mana pun | `Handle` | memasang handler di realm pemilik perintahnya |

Yang menentukan sebuah dispatch tetap lokal atau menyeberang kabel adalah **kontraknya**,
bukan pemanggilnya. Kode client menulis baris yang sama untuk keduanya.

---

## Field

### `Context: RuntimeContext`

`"Server"` atau `"Client"`. Sama dengan `unrest.Context`.

### `Contracts: Contracts`

Registry kontrak. Objek yang **sama persis** dengan yang kamu dapat dari
`require(ReplicatedStorage.Unrest.Net.Contracts)`, jadi tidak ada dua registry yang bisa
berbeda pendapat.

```luau
for _, name in unrest.Bridge.Contracts:List() do
    print(name)
end
```

### `Rejected: Signal<Rejection>`

Menyala setiap kali sebuah permintaan ditolak, di sisi mana pun yang menolaknya.

```luau
unrest.Bridge.Rejected:Connect(function(rejection)
    warn(`{rejection.Command} ditolak: {rejection.Reason} — {rejection.Detail}`)
end)
```

`Rejection` berisi `Command`, `Reason` (`RejectionReason`), `Detail` (string untuk
developer), dan `Player?`.

> **`Detail` tidak pernah menyeberang kabel.** Dia dicatat di server dan berhenti di sana.
> Client yang menyelidik hanya menerima `Reason` yang kasar.

---

## Channel — state yang mengalir keluar

### `Bridge:Publish(channel: string, value: any, target: Player?): ()`

Menerbitkan state yang ditahan.

Di **server**, `Visibility` channel-nya yang memutuskan siapa yang melihat:

| `Visibility` | Yang terjadi |
| --- | --- |
| `Server` (bawaan) | Ditahan secara lokal. Tidak pernah direplikasi. |
| `Player` | **Wajib** ada `target`. Dikirim ke satu pemain itu saja. Tidak ditahan di server. |
| `Public` | Ditahan, lalu dikirim ke semua client. |

```luau
-- state milik semua orang
bridge:Publish("Music.NowPlaying", "Lobby")

-- state milik satu pemain
bridge:Publish("Dance.Current", "Wave", player)
```

Di **client**, `Publish` hanya menulis ke salinan lokal. State client tidak pernah
direplikasi: server adalah satu-satunya penulis apa pun yang bisa dilihat pemain lain.

**Jebakan yang paling sering kena:**

* Channel `Player` **tanpa** `target` melempar error. Itu disengaja — menyiarkan state
  per-pemain ke semua orang persis kesalahan yang dicegah kontraknya.
* Channel `Player` **tidak ditahan di server**. Tidak ada satu "nilai sekarang" untuk channel
  per-pemain, dan berpura-pura ada akan membuat state satu pemain terbaca sebagai state
  semua orang lewat `Peek`.
* Nilai yang gagal validasi **tidak direplikasi**, dan kamu dapat peringatan. Gagalnya
  tertutup: nilainya tetap lokal, kabelnya tetap bersih. Bahkan channel tanpa `Value` spec
  tetap diperiksa daftar-izin data biasa, jadi sebuah `Instance` tidak bisa lolos.

### `Bridge:Subscribe(channel: string, handler: (value: any) -> ()): Connection`

Berlangganan sebuah channel. Mengembalikan `Connection` dengan `:Disconnect()`.

```luau
local connection = bridge:Subscribe("Music.NowPlaying", function(value)
    print("sekarang:", value)
end)

-- nanti
connection:Disconnect()
```

**Kalau channel-nya sudah punya nilai, handler-mu langsung dipanggil** dengan nilai itu,
lewat `task.spawn`. Inilah yang membuat urutan berhenti penting: label yang baru ditandai
tiga puluh detik setelah lagu mulai tetap menampilkan lagu yang benar di frame pertamanya.

Karena panggilan pertama itu lewat `task.spawn`, dia terjadi **setelah** baris `Subscribe`
selesai, bukan di dalamnya.

### `Bridge:Peek(channel: string): any`

Nilai terakhir yang diterbitkan di channel itu, atau `nil`.

```luau
if bridge:Peek("Music.NowPlaying") == nil then
    unrest:Dispatch("Music.Play", "Lobby")
end
```

Ini yang kamu pakai saat perintah yang benar bergantung pada keadaan sekarang — persis
batas di mana atribut sudah tidak cukup dan kamu turun ke `Unrest:Query`.

`Peek` tidak yield dan tidak membuat langganan.

---

## Perintah — niat yang mengalir masuk

### `Bridge:Dispatch(command: string, payload: any): ()`

Mengirim sebuah niat. **Tidak pernah yield.** Tidak mengembalikan apa pun.

```luau
bridge:Dispatch("Music.Play", "Lobby")
```

Yang terjadi di dalam, berurutan:

1. Kontraknya dicari. Kalau tidak ada, ditolak `UnknownCommand` dengan peringatan.
2. Kalau `contract.Realm` sama dengan context sekarang, ini **dispatch lokal**: payload-nya
   divalidasi terhadap skema kontrak, lalu handler dijalankan langsung.
3. Kalau context-nya server dan realm-nya client, ditolak `WrongRealm`. **Server tidak
   pernah menyuruh client.** Server tidak bisa memverifikasi client menurut, jadi perintah ke
   arah itu bukan mekanisme, cuma saran. Server → client adalah state di channel.
4. Kalau tidak, dikirim lewat gerbang client.

**Perhatikan langkah 2.** Bahkan dispatch lokal di server pun divalidasi. "Tidak ada handler
yang pernah melihat payload yang belum divalidasi" adalah jaminan yang dijaga mutlak,
termasuk terhadap kode server yang salah ketik.

### `Bridge:Invoke(command: string, payload: any): InvokeResult`

Mengirim niat dan **menunggu** nilainya. Yield.

```luau
local result = bridge:Invoke("Music.Play", "Lobby")
if result.Ok then
    print(result.Value)
else
    warn(result.Reason)
end
```

`InvokeResult` selalu tabel dengan tiga field:

| Field | Tipe | Arti |
| --- | --- | --- |
| `Ok` | `boolean` | Berhasil atau tidak. |
| `Value` | `any` | Kembalian handler, kalau `Ok`. |
| `Reason` | `RejectionReason?` | Alasan kasar, kalau gagal. |

**Jebakan:**

* Kontraknya **wajib** menulis `Response = true`. Kalau tidak, hasilnya
  `ResponseNotAllowed` dan tidak ada yang dikirim.
* **Server tidak pernah meng-invoke client.** `RemoteFunction:InvokeClient` menyerahkan
  thread server ke mesin yang tidak dikendalikan server, tanpa timeout — client yang tidak
  pernah menjawab menggantung thread itu selamanya. Jadi mekanismenya tidak ada.
* Invoke di client dibatasi `Constants.Limits.InvokeTimeout` (10 detik) dan **tidak pernah
  mencoba ulang**. Percobaan ulang otomatis saat timeout adalah cara server yang sedang
  kepayahan mendapat salinan kedua dari setiap permintaan yang sudah telat dia kerjakan.

### `Bridge:Handle(command: string, handler: CommandHandler): Connection`

Memasang handler untuk sebuah perintah, **di realm yang memilikinya**. Mengembalikan
`Connection`.

```luau
local connection = bridge:Handle("Music.Play", function(source, payload)
    if source.Player == nil then
        -- dispatch lokal dari kode server, bukan permintaan client
    end
    return music:Play(payload :: string)
end)
```

`CommandHandler` adalah `(source: CommandSource, payload: any) -> any`.

`CommandSource` berisi:

| Field | Tipe | Arti |
| --- | --- | --- |
| `Player` | `Player?` | Pemanggilnya. Tidak nil hanya untuk permintaan yang benar-benar menyeberang jaringan. |
| `Context` | `RuntimeContext` | Realm asal dispatch-nya. |
| `Remote` | `boolean` | `true` kalau ini datang lewat remote. |

**Handler yang mengubah state otoritatif harus bercabang pada `source.Remote`, bukan pada
isi payload.** Identitas datang dari transport, tidak pernah dari pesan. Tidak ada
`payload.UserId`, dan tidak ada tempat untuk menaruhnya.

**`payload` tidak perlu kamu periksa tipenya.** Gerbang sudah membuktikannya terhadap skema
kontraknya sebelum handler dipanggil.

**Jebakan:**

* `Handle` **melempar error** kalau perintahnya tidak dideklarasikan, dengan daftar perintah
  yang ada. Handler untuk perintah yang tidak pernah dideklarasikan tidak akan pernah
  terpanggil, dan menerimanya diam-diam cuma menyembunyikan itu.
* `Handle` juga **melempar error** kalau dipanggil di realm yang salah. Handler untuk
  perintah `Realm = "Server"` harus dipasang di server.
* Handler berjalan di dalam `xpcall`. Satu sistem yang error tidak bisa menggantung gerbang
  untuk pemain lain; traceback-nya dicatat di sisi server dan pemanggil hanya dapat
  `HandlerError`.

Simpan `Connection`-nya di `Maid` sistemmu supaya ikut terlepas saat sistemnya `Destroy`.

---

## `Bridge:Destroy(): ()`

Merobohkan Bridge: melepas gerbang, mengosongkan channel dan handler, membersihkan semua
koneksi.

Kamu hampir tidak akan pernah memanggil ini. Framework tidak memanggilnya dari `Unrest:Stop`.
Setiap metode lain melempar error setelah Bridge dihancurkan.

---

## Yang **tidak** ada di sini, dan kenapa

Ada beberapa metode di objek Bridge yang sengaja **tidak** ada di tipe `Bridge`:
`AttachGateway`, `Execute`, `Receive`, `Snapshot`, `UseTransport`, `StartNetworking`,
`TransportProvider`.

Semuanya hidup di `NetTypes.BridgeSeam` — permukaan yang di-cast oleh gerbang, bukan oleh
kode game. Alasannya paling jelas pada `Execute`: dia menjalankan handler **tanpa** validasi,
tanpa batas laju, tanpa otorisasi. Menaruhnya di `Types.Bridge` berarti membuatnya bisa
dijangkau apa pun yang baru saja menerima masukan dari client.

Satu-satunya benda di kode ini yang bisa menjangkau handler tanpa penjagaan adalah objek yang
baru saja selesai menjaganya.
