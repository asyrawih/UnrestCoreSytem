# API — `Contracts`

`Contracts` adalah registry kebijakan. Dia yang memutuskan perintah apa yang ada, siapa yang
boleh memintanya, bentuk payload apa yang diterima, dan seberapa jauh sebuah channel boleh
merambat.

```luau
local Contracts = require(ReplicatedStorage.Unrest.Net.Contracts)
-- objek yang sama persis:
local Contracts = unrest.Bridge.Contracts
```

Definisi tipenya ada di `src/shared/Net/Types.luau`, di-`export` ulang lewat
`src/shared/Types.luau`.

---

## Framework tidak mendeklarasikan apa pun

Registry-nya kosong sejak awal. Framework tidak membawa satu perintah pun dan satu channel
pun. Nama-nama itu milik game, dan game mendaftarkannya lewat `Declare` dan `DeclareChannel`
sebelum framework dinyalakan. Lihat [ModuleScript `Game`](GAME-MODULE.md).

Registry yang tidak pernah dideklarasikan apa-apa **menolak segalanya**, dan itulah sebabnya
registry kosong itu aman.

Kontrak tinggal di `ReplicatedStorage` dengan sengaja. Isinya pengetahuan publik: daftar nama
pintu, dan mana yang punya gagang di sisi luar. Gemboknya ada di server.

---

## Aturan tunggalnya

> **Sebuah perintah tidak bisa dijangkau client kecuali kontraknya menulis
> `AllowClient = true`.**

Bukan "kecuali ditandai privat". Bukan "kecuali ada pengecekan yang ditambahkan".
**Ketiadaan izin itulah penolakannya.**

---

## Field

### `Contracts.Commands: { [string]: CommandContract }`

### `Contracts.Channels: { [string]: ChannelContract }`

Registry yang hidup. Keduanya tumbuh saat deklarasi berdatangan, jadi keduanya benda yang
tepat untuk di-iterasi oleh alat bantu, dan benda yang **salah** untuk dipegang referensinya
lalu dianggap sudah lengkap.

---

## `Contracts:Declare(contract: CommandContract): CommandContract`

Mendaftarkan perintah, mengembalikan kontraknya yang sudah dibekukan.

```luau
Contracts:Declare({
    Name = "Music.Play",
    Realm = "Server",
    AllowClient = true,
    Payload = { Kind = "string", MaxLength = 64, Pattern = "[%w_%-%.]+" },
    RateLimit = { Count = 4, Window = 1 },
    Response = true,
    Description = "Putar lagu terdaftar berdasarkan nama.",
})
```

**Melempar error** kalau: kontraknya cacat bentuk; `AllowClient` atau `Authorize` ditulis di
luar realm server; atau nama itu sudah pernah dideklarasikan.

Penolakan nama ganda itu penting. Sebuah perintah punya persis satu kontrak, dan diam-diam
menggabungkan dua kontrak adalah cara sebuah `Realm` menghilang tanpa ada yang sadar.

### `CommandContract`

| Field | Tipe | Wajib? | Arti |
| --- | --- | --- | --- |
| `Name` | `string` | **ya** | Nama perintahnya. |
| `Realm` | `RuntimeContext` | **ya** | Di mana handler-nya jalan. Perintah `"Server"` yang di-dispatch dari client diteruskan; perintah `"Client"` tidak pernah meninggalkan client. |
| `AllowClient` | `boolean?` | tidak | **Ini kontrol keamanannya.** Absen atau `false` berarti tidak terjangkau client sama sekali. |
| `Payload` | `ArgumentSpec?` | tidak | Skema payload. Perintah **tanpa** `Payload` hanya menerima `nil`. |
| `RateLimit` | `RateLimitSpec?` | tidak | Jatah per pemain. Jatuh balik ke `Constants.Limits.Default*`. |
| `Authorize` | fungsi? | tidak | Gerbang terakhir sebelum handler. Lihat di bawah. |
| `Response` | `boolean?` | tidak | Apakah `Bridge:Invoke` boleh dipakai. |
| `Description` | `string?` | tidak | Satu baris penjelasan, muncul di pesan galat. |
| `Wire` | `any?` | tidak | Milik transport. **Framework tidak pernah membacanya.** |

### `Authorize`

```luau
Authorize: ((player: Player, payload: any) -> (boolean, string?))?
```

Gerbang terakhir sebelum handler, dan satu-satunya yang bisa melihat state game. Berjalan di
**server**, setelah pemeriksaan skema dan batas laju lolos — jadi dia boleh mengasumsikan
payload sudah benar bentuknya.

```luau
local function hasLivingCharacter(player: Player, _payload: any): (boolean, string?)
    local character = player.Character
    if character == nil then
        return false, "pemain belum punya karakter"
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid == nil or humanoid.Health <= 0 then
        return false, "pemain sedang mati"
    end
    return true, nil
end
```

Kembalikan `false` plus alasan untuk menolak. **Alasannya dicatat di server dan tidak pernah
dikirim ke client.** Client yang menyelidik hanya belajar `Unauthorized`; dia tidak bisa
membedakan "kamu mati" dari "kamu belum dimuat" dari "emote itu khusus staf", jadi dia tidak
bisa memetakan isi server dengan mengamati kebohongan mana yang gagal berbeda.

`Authorize` yang **melempar error** juga gagal tertutup: ditolak.

> **Jangan pernah menutup rahasia di dalam `Authorize`.** Modul kontrak tinggal di
> `ReplicatedStorage`, jadi client bisa membaca fungsinya. Dia boleh membaca state game
> karena dia hanya *dijalankan* di server; salinan yang dipegang client mati.

### `Wire`

Field milik transport, dan **framework tidak pernah membacanya**. Apa pun yang dibutuhkan
transport terpasang untuk menaruh perintah ini di kabelnya — paket ByteNet, codec, sebuah
id — dideklarasikan di baris yang sama dengan kebijakan yang mengaturnya, supaya
ketidakcocokan di antara keduanya terlihat saat dibaca, bukan saat runtime.

`Declare` tidak memvalidasinya, tidak ada gerbang yang mengonsultasikannya, dan transport
remote bawaan mengabaikannya sepenuhnya. Tipenya `any` dengan sengaja: memberinya tipe berarti
framework punya pendapat tentang pustaka yang seharusnya tidak pernah dia bergantung padanya.

---

## `Contracts:DeclareChannel(declaration: ChannelDeclaration): ChannelContract`

Mendaftarkan channel, menerapkan bawaan `Server` untuk `Visibility` yang tidak ditulis.

```luau
Contracts:DeclareChannel({
    Name = "Music.NowPlaying",
    Visibility = "Public",
    Value = { Kind = "string", Optional = true, MaxLength = 64 },
    Description = "Lagu yang sedang didengar semua orang, atau nil.",
})
```

### `ChannelVisibility`

| Nilai | Sejauh mana nilainya merambat |
| --- | --- |
| `"Server"` | **Bawaan.** Tidak pernah meninggalkan server. |
| `"Player"` | Direplikasi ke satu pemain yang disebut saja. |
| `"Public"` | Direplikasi ke setiap client. |

Bawaannya `Server` supaya channel baru **tidak bisa bocor karena kelalaian**. Jawaban yang
aman adalah jawaban yang kamu dapat dengan tidak memikirkannya.

Perhatikan bahwa tipe deklarasinya (`ChannelDeclaration`) membuat `Visibility` opsional,
sementara kontrak hasilnya (`ChannelContract`) selalu punya. Itu disengaja: bawaan yang aman
harus jadi hal yang **paling pendek** untuk diketik.

### `ChannelContract`

| Field | Tipe | Arti |
| --- | --- | --- |
| `Name` | `string` | Nama channel-nya. |
| `Visibility` | `ChannelVisibility` | Sejauh mana nilainya merambat. |
| `Value` | `ArgumentSpec?` | Skema yang harus dipenuhi nilainya sebelum boleh direplikasi. |
| `Description` | `string?` | Satu baris penjelasan. |
| `Wire` | `any?` | Milik transport, seperti pada kontrak perintah. |

---

## Pembacaan

### `Contracts:List(): { string }`

Nama perintah yang dideklarasikan, terurut. Ini yang dicantumkan pesan galat.

### `Contracts:GetCommand(name: string): CommandContract?`

Kontrak untuk nama itu, atau `nil` kalau tidak pernah dideklarasikan.

### `Contracts:ExpectCommand(name: string): CommandContract`

Sama, tapi **melempar error** dengan daftar perintah yang ada.

### `Contracts:GetChannel(name: string): ChannelContract?`

### `Contracts:IsClientCallable(name: string): boolean`

Apakah client boleh meminta nama itu. **Satu pertanyaan yang ditanyakan kedua sisi** — dan
karena itu satu fungsi, keduanya tidak bisa berbeda pendapat.

---

## `ArgumentSpec` — skema payload

```luau
export type ArgumentSpec = {
    Kind: ArgumentKind,
    Optional: boolean?,
    MaxLength: number?,
    Pattern: string?,
    Min: number?,
    Max: number?,
    OneOf: { any }?,
    Of: ArgumentSpec?,
    Fields: { [string]: ArgumentSpec }?,
}
```

### `ArgumentKind`

```
"string" | "number" | "integer" | "boolean" | "nil" | "table" | "Vector3" | "Color3" | "EnumItem"
```

Sempit dengan sengaja. Tidak ada `Instance`, tidak ada fungsi, tidak ada userdata di luar
daftar itu — karena tidak satu pun dari mereka bisa dipercaya atau dibatasi biayanya saat
datang dari client.

### Pembatas

| Field | Berlaku untuk | Arti |
| --- | --- | --- |
| `Optional` | semua | Menerima `nil` selain `Kind`. |
| `MaxLength` | string | Panjang maksimum. Dibatasi lagi oleh `Constants.Limits.MaxStringLength` (256). |
| `Pattern` | string | Pola Lua yang harus cocok **penuh**. |
| `Min` / `Max` | number | Batas inklusif. Angka non-finit selalu ditolak. |
| `OneOf` | semua | Nilainya harus salah satu dari daftar ini. |
| `Of` | table | Skema yang diterapkan ke **setiap** entri. |
| `Fields` | table | Skema per nama field. |

Contoh:

```luau
-- satu identifier
{ Kind = "string", MaxLength = 64, Pattern = "[%w_%-%.]+" }

-- angka 0..1
{ Kind = "number", Min = 0, Max = 1 }

-- daftar identifier
{ Kind = "table", Of = { Kind = "string", MaxLength = 32 } }

-- tabel dengan field bernama
{ Kind = "table", Fields = {
    Item = { Kind = "string", MaxLength = 32 },
    Jumlah = { Kind = "integer", Min = 1, Max = 99 },
} }
```

### Dua aturan yang sering mengejutkan

* **Perintah tanpa `Payload` menerima `nil` dan tidak ada yang lain.** Handler yang ditulis
  untuk `nil` tidak akan pernah dikejutkan sebuah tabel.
* **Skema dengan `Fields` menolak field yang tidak dideklarasikan**, bukan mengabaikannya.
  Field yang tidak dideklarasikan bukan ruang kosong yang gratis.

Batas keras yang selalu berlaku, dari `Constants.Limits`:

| Batas | Nilai | Yang dibatasi |
| --- | --- | --- |
| `MaxPayloadDepth` | 4 | Kedalaman bersarang. |
| `MaxPayloadEntries` | 32 | Entri per tabel. |
| `MaxStringLength` | 256 | Setiap string, termasuk kunci tabel. |

Lihat [Keamanan Remote](REMOTE-SECURITY.md) untuk gambaran lengkapnya.

---

## `RateLimitSpec`

```luau
export type RateLimitSpec = { Count: number, Window: number }
```

`Count` panggilan yang diizinkan per pemain, per `Window` detik.

Tanpa `RateLimit`, kontraknya jatuh balik ke `Constants.Limits.DefaultRateCount` (10) per
`DefaultRateWindow` (1 detik).

Di atas itu ada **jatah global 60 permintaan per detik per pemain**, melintasi semua perintah
sekaligus, supaya banjir tidak bisa dihindarkan dengan menyebarnya ke banyak perintah murah
yang masing-masing masih di bawah plafonnya sendiri.

---

## `RejectionReason`

Alasan kasar yang bisa kamu terima:

```
"UnknownCommand" | "NotClientCallable" | "WrongRealm" | "BadPayload" | "RateLimited"
| "Unauthorized" | "HandlerError" | "NoHandler" | "Timeout" | "ResponseNotAllowed"
```

Urutan pemeriksaannya, dan kenapa urutan itu, ada di
[Keamanan Remote](REMOTE-SECURITY.md).
