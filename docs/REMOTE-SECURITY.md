# Keamanan Remote

> Bridge adalah controller framework **sekaligus** batas client/server. Halaman ini adalah
> separuh yang batas: apa yang bisa dijangkau client, apa yang tidak, dan kenapa "tidak"-nya
> adalah sifat rancangan, bukan pemeriksaan yang kebetulan diingat seseorang.

---

## 1. Satu gagasan

**Sebuah perintah tidak bisa dijangkau client kecuali kontraknya mengizinkan, dan server
memutuskan itu dengan membaca kontraknya — tidak pernah dengan membaca pesannya.**

Setiap mekanisme di bawah adalah konsekuensinya. Separuh yang penting adalah klausa kedua:
karena izinnya dicari **berdasarkan nama** di sebuah tabel milik server, tidak ada yang bisa
dikirim client untuk memperluas izinnya sendiri. Izinnya memang tidak pernah ada di dalam
pesan, dan amplopnya tidak punya tempat untuk menaruhnya.

```
    CLIENT                                   |  SERVER
                                             |
  Bridge:Dispatch("Music.Play", "Lobby")     |
        |                                    |
        | contract.Realm == "Server"         |
        v                                    |
  Net/Client.luau  -- penjaga anjuran -------|-----------------------------.
        |          (kenyamanan, bukan kontrol)                             |
        | kirim(command, payload)            |                             |
        `------------------------------------|--> Net/Server.luau          |
                                             |     1 UnknownCommand        |
                                             |     2 NotClientCallable  <--' uji yang sama,
                                             |     3 WrongRealm            yang ini berarti
                                             |     4 ResponseNotAllowed
                                             |     5 RateLimited (global)
                                             |     6 RateLimited (perintah)
                                             |     7 BadPayload
                                             |     8 Unauthorized
                                             |          |
                                             |          v
                                             |     Bridge:Execute -> handler (xpcall)
                                             |          |
                                             |          v
                                             |     Bridge:Publish -> visibilitas channel
                                             |          |
    Bridge:Subscribe  <----- UnrestPublish --|----------'
```

---

## 2. Di mana berkasnya tinggal, dan kenapa itu sifat keamanan

| Berkas | Realm | Kenapa di situ |
| --- | --- | --- |
| `src/shared/Net/Types.luau` | ReplicatedStorage | Tipe saja. |
| `src/shared/Net/Contracts.luau` | ReplicatedStorage | **Pengetahuan publik, dengan sengaja.** Daftar nama pintu dan mana yang punya gagang di luar. |
| `src/shared/Net/Validate.luau` | ReplicatedStorage | Penelusur skema yang sama untuk kedua sisi; dia tidak memegang kebijakan. |
| `src/shared/Net/Transport.luau` | ReplicatedStorage | Antarmuka transport. Sepuluh metode, dan tidak memutuskan apa pun. |
| `src/shared/Net/Client.luau` | ReplicatedStorage | Bridge harus bisa membangunnya di client. |
| `src/server/Net/Server.luau` | **ServerScriptService** | **Kebijakannya tidak pernah direplikasi ke mesin yang diaturnya.** |

Client bisa membaca tabel kontrak. Itu bukan kebocoran: mengetahui bahwa
`Music.ForceStopAll` ada dan khusus server tidak memberi tahu penyerang apa pun yang bisa
mereka lakukan, karena gemboknya ada di `src/server/Net/Server.luau`, yang tidak pernah
mereka terima.

Asimetri cara kedua gerbang dipasang mengikuti dari sini. Setengah-client dibangun oleh
konstruktor Bridge sendiri — jadi sebuah client **terjaring secara konstruksi**, dan bootstrap
tidak bisa gagal terbuka karena lupa menyambungkannya. Setengah-server tidak bisa dijangkau
dari `ReplicatedStorage` sama sekali, jadi bootstrap server memasangnya secara eksplisit lewat
`OpenGateway`.

---

## 3. Bentuk kontraknya

Framework **tidak mendeklarasikan satu perintah pun dan satu channel pun.** Registry-nya
kosong sejak awal, dan registry kosong menolak segalanya. Nama-nama itu milik game, dan
didaftarkan lewat `Contracts:Declare` — lihat [ModuleScript `Game`](GAME-MODULE.md) dan
[API Contracts](API-CONTRACTS.md).

Jadi tabel di bawah menggambarkan **bentuk**, bukan isi bawaan.

### Perintah

| Field | Efeknya terhadap keamanan |
| --- | --- |
| `Realm` | Di mana handler-nya jalan. Perintah `"Server"` yang di-dispatch client diteruskan; perintah `"Client"` tidak pernah meninggalkan client. |
| `AllowClient` | **Ini kontrolnya.** Absen atau `false` berarti tidak terjangkau client sama sekali. |
| `Payload` | Skema. Perintah **tanpa** `Payload` menerima `nil` saja. |
| `RateLimit` | Jatah per pemain. Bawaannya 10 per detik. |
| `Authorize` | Gerbang terakhir, satu-satunya yang bisa melihat state game. |
| `Response` | Apakah `Bridge:Invoke` diizinkan. |
| `Wire` | Milik transport. Framework tidak pernah membacanya. |

Contoh nyata dari game contoh di `src/game/Contracts.luau` — dua perintah yang **tidak** bisa
dijangkau client:

```luau
Contracts:Declare({
    Name = "Music.ForceStopAll",
    Realm = "Server",
    Description = "Perintah operator: senyapkan soundtrack.",
})
```

Perhatikan apa yang **tidak** ditulis di situ. Tidak ada `AllowClient`. Tidak ada
`Private = true`. Tidak ada klausa penjaga. Perintahnya tidak terjangkau karena **tidak ada
yang menuliskan izinnya**. Kode server men-dispatch-nya sebebas perintah lain; client yang
mengirim namanya dapat `NotClientCallable` dan tidak belajar apa pun.

### Channel

| `Visibility` | Sejauh mana nilainya merambat |
| --- | --- |
| `"Server"` | **Bawaan.** Tidak pernah meninggalkan server. |
| `"Player"` | Direplikasi ke satu pemain yang disebut. Tidak ditahan di server. |
| `"Public"` | Direplikasi ke setiap client. |

Bawaan `Server` adalah contoh yang sama dari sisi channel: **jawaban yang aman adalah jawaban
yang kamu dapat dengan tidak memikirkannya.** Channel yang lupa dideklarasikan, atau
dideklarasikan asal-asalan, tidak direplikasi.

Contoh kedua dari game contoh: sebuah channel yang membawa **nama** karakter, bukan
karakternya. Skema `string?`-nya yang menegakkan itu — sebuah `Model` adalah `Instance`,
`Instance` bukan data biasa, dan validasi menolaknya. Bahkan kalau skemanya dihapus, daftar-izin
data biasa tetap menolaknya. Membalik channel itu jadi `Public` karena tidak sengaja
menghasilkan penolakan di log server, bukan kebocoran.

---

## 4. Jalur penolakan, berurutan

Gerbang server menolak permintaan di baris pertama yang berkata tidak. Urutannya tidak
sembarangan.

| # | `RejectionReason` | Pemicunya |
| --- | --- | --- |
| 1 | `UnknownCommand` | Field pertama amplopnya bukan string 1…128 karakter, atau tidak ada kontrak yang mendeklarasikannya. |
| 2 | `NotClientCallable` | Kontraknya tidak menulis `AllowClient = true`. **Ini kontrol keamanannya.** |
| 3 | `WrongRealm` | Kontraknya tidak menjalankan perintah ini di server. |
| 4 | `ResponseNotAllowed` | `Invoke` dipakai untuk perintah tanpa `Response = true`. |
| 5 | `RateLimited` | Jatah **global** pemain itu, melintasi semua perintah, sudah habis. |
| 6 | `RateLimited` | Jatah pemain itu untuk **perintah ini** sudah habis. |
| 7 | `BadPayload` | Payload-nya tidak memenuhi `ArgumentSpec` kontraknya. |
| 8 | `Unauthorized` | Kait `Authorize` berkata tidak — atau melempar error, yang juga gagal tertutup. |
| 9 | `HandlerError` / `NoHandler` | Handler-nya error, atau tidak ada yang terdaftar. Bukan salah client; tidak dihitung terhadapnya. |

Tiga urutan di antaranya menanggung beban:

* **Uji client-callable ada di urutan kedua, sebelum apa pun membaca payload.** Perintah yang
  tidak boleh dipanggil client ditolak tanpa argumennya pernah diperiksa, jadi skema sebuah
  perintah yang tak terjangkau bukan permukaan serangan.
* **Batas laju datang sebelum validasi skema.** Menelusuri tabel yang dalam adalah bagian
  mahal dari sebuah permintaan, dan biaya itu harus jatuh ke jatah si banjir, bukan ke waktu
  frame server.
* **Jatah global diperiksa sebelum jatah per perintah.** Batas per perintah saja bisa
  dihindari dengan menyebarkan banjir ke banyak perintah murah, masing-masing masih di bawah
  plafonnya sendiri. Ember global itulah yang membuat jumlahnya ikut terbatas.

### Apa yang dipelajari pemanggil

`Reason` yang kasar, dan tidak lebih. Setiap `Detail` — field yang gagal, alasan dari kait
`Authorize`, traceback sebuah handler — dicatat di server dan tidak pernah menyeberang kabel.

Client yang menyelidik sebuah perintah tidak bisa membedakan "kamu mati" dari "kamu belum
dimuat" dari "itu khusus staf", jadi dia tidak bisa memetakan isi server dengan mengamati
kebohongan mana yang gagal berbeda.

### Penolakan milik client sendiri

`Net/Client.luau` menjalankan uji yang **identik** sebelum mengirim, dan menyalakan
`NetClient.Refused` saat gagal.

Penolakan itu membeli persis dua hal: **sinyal yang berisik di depan keyboard** saat seorang
programmer men-dispatch sesuatu yang kontraknya tidak pernah buka, dan **tidak ada trafik
remote yang terbuang**.

Dia membeli **nol** keamanan. Dia berjalan di mesin yang dimiliki pemain, dan seorang
exploiter tinggal menghapusnya. Server tidak tahu, tidak bertanya, dan tidak peduli apakah dia
berjalan. Kalau keduanya berselisih, server yang menang; kalau salah satunya harus dihapus,
hapus yang di client.

---

## 5. Validasi payload

`Net/Validate.luau` adalah **daftar-izin**. Sebuah nilai ditolak kecuali dia salah satu dari:

```
nil   boolean   number   string   table   Vector3   Color3   EnumItem
```

Selebihnya ditolak tanpa diperiksa — `Instance`, fungsi, thread, userdata, tabel bermetatable,
tabel yang menunjuk ke dirinya sendiri.

Masing-masing adalah bahaya yang spesifik, bukan keberatan gaya penulisan:

* `Instance` adalah referensi hidup yang mungkin ditulis handler.
* Metatable mengubah `payload.Apapun` jadi kode pilihan penyerang.
* Tabel bersiklus mengubah setiap penelusuran rekursif jadi hang.

Semuanya juga dibatasi, karena **biaya memeriksa itu sendiri adalah permukaan serangan**
(`Constants.Limits`):

| Batas | Nilai | Yang dibatasi |
| --- | --- | --- |
| `MaxPayloadDepth` | 4 | Bersarang, supaya penelusurannya tidak bisa dibuat dalam. |
| `MaxPayloadEntries` | 32 | Entri per tabel, supaya tidak bisa dibuat lebar. |
| `MaxStringLength` | 256 | Setiap string, termasuk kunci tabel. `MaxLength` sebuah kontrak hanya bisa lebih ketat. |

Di atas pemeriksaan jenis, sebuah `ArgumentSpec` boleh menuntut: `Optional`, `MaxLength`,
`Pattern` yang harus cocok **penuh**, `Min`/`Max` (angka non-finit — `NaN` dan kedua tak
hingga — ditolak sebelum batasnya dipertimbangkan, karena mereka lolos begitu saja dari
perbandingan yang naif), `OneOf`, serta `Of` dan `Fields` yang rekursif.

Dua aturan di sana adalah "tolak secara bawaan" yang dinyatakan ulang satu tingkat lebih
dalam:

* **Perintah tanpa `Payload` menerima `nil` dan tidak ada yang lain.** Handler yang ditulis
  untuk `nil` tidak akan pernah dikejutkan sebuah tabel.
* **Skema dengan `Fields` menolak field yang tidak dideklarasikan**, bukan mengabaikannya.
  Field yang tidak dideklarasikan bukan ruang kosong yang gratis.

Nilai **kembalian** handler yang menyeberang balik ke client mendapat daftar-izin data biasa
yang sama, jadi handler tidak bisa asal menyerahkan `Instance` ke pemanggil yang meminta
boolean.

---

## 6. Identitas

Pemainnya adalah **argumen pertama yang ditaruh Roblox di callback remote**, dan tidak ada hal
lain yang pernah dikonsultasikan.

Dia sampai ke handler sebagai `CommandSource.Player`. Tidak ada `payload.Target`, tidak ada
`payload.UserId`, tidak ada `payload.IsAdmin` — dan, yang paling penting, **tidak ada tempat
di amplopnya untuk menaruh satu pun**.

"Mainkan emote di karakter orang lain" bukan permintaan yang divalidasi framework ini dengan
hati-hati; itu permintaan yang **tidak bisa dia representasikan**.

`CommandSource.Remote` memberi tahu handler apakah permintaan ini menyeberang kabel sama
sekali. Handler yang mengubah state otoritatif bercabang pada itu, **tidak pernah** pada
payload.

Aturan yang sama berlaku ke transport: `player` datang dari pengetahuan transport sendiri
tentang siapa yang mengirim. **Transport yang tidak bisa memastikan siapa pengirim sebuah
pesan tidak boleh mengantarnya sama sekali.**

---

## 7. Batas laju

Sebuah **token bucket** per pemain per perintah, ditambah satu ember global per pemain.

Pilihan ini di atas sliding window berisi daftar timestamp adalah sifat keamanan tersendiri:
daftar timestamp **tumbuh bersama banjir yang mengisinya**, jadi membatasi laju seorang
penyerang justru makin mahal makin keras dia menyerang. Token bucket cuma dua angka, O(1)
dalam waktu dan ruang, apa pun yang datang.

Ember dan penghitung penolakan seorang pemain dihapus saat `PlayerRemoving`, jadi tabel
state-nya tidak bisa tumbuh seumur hidup server. Loop keluar-masuk bukan kebocoran memori.

---

## 8. Pelaporan penyalahgunaan, bukan main hakim sendiri

Penolakan dihitung per pemain. Melewati `Constants.Limits.AbuseThreshold` (25), dan setiap 25
setelahnya, `NetServer.AbuseDetected` menyala dengan pemain dan hitungannya. Setelah itu
framework **tidak melakukan apa-apa**.

Menendang berdasarkan heuristik akan menendang pemain dengan koneksi buruk dan pemain yang
tombolnya kepencet dua kali. Framework tidak tahu apa itu "curang" di game-mu; sinyal itu
adalah sambungan tempat sistem moderasi**mu** dipasang. `NetServer.Rejected` adalah sambungan
yang sepadan untuk telemetri.

`HandlerError` secara eksplisit **tidak** dihitung terhadap pemain. Sistem yang error tidak
boleh bisa membuat penggunanya sendiri dilaporkan.

---

## 9. Bentuk transport

Tiga objek tereplikasi, dan tidak pernah lebih:

| Objek | Arah | Untuk apa |
| --- | --- | --- |
| `UnrestDispatch` (`RemoteEvent`) | client → server | Kirim dan lupakan. |
| `UnrestInvoke` (`RemoteFunction`) | client → server | Permintaan/balasan. |
| `UnrestPublish` (`RemoteEvent`) | server → client | Replikasi channel. |

Satu titik sempit per arah, bukan satu remote per fitur: ada persis **satu** fungsi di seluruh
kode ini yang memutuskan apakah sebuah permintaan hidup, jadi fitur baru menambah baris di
sebuah tabel, bukan menambah pintu.

**Server tidak pernah meng-invoke client.** `RemoteFunction:InvokeClient` menyerahkan thread
milik server ke mesin yang tidak dikendalikan server, tanpa timeout yang bisa memutusnya;
client yang cukup dengan tidak pernah menjawab menggantung thread itu selamanya. Trafik
server → client adalah `FireClient` satu arah.

Sejalan dengan itu, **server juga tidak pernah memerintah client**. `Bridge:Dispatch` untuk
perintah `Realm = "Client"` dari server adalah penolakan `WrongRealm`, dengan sengaja. Server
tidak bisa memverifikasi bahwa client menurut, jadi perintah ke arah itu cuma saran yang
menyamar jadi mekanisme. Server → client adalah **state di sebuah channel**, dan client yang
memutuskan apa yang digambar.

`Invoke` di client membatasi dirinya dengan `Constants.Limits.InvokeTimeout` (10 detik), dan
**tidak pernah mencoba ulang**: percobaan ulang otomatis saat timeout adalah cara server yang
sedang kepayahan mendapat salinan kedua dari setiap permintaan yang sudah telat dia kerjakan.

Transport bisa diganti sepenuhnya, tapi **antarmukanya searah**: transport menyerahkan
permintaan mentah ke gerbang dan gerbang yang menjawab. Transport tidak pernah menjalankan
handler, tidak pernah membaca kontrak, dan tidak pernah tahu apakah sebuah client boleh
meminta hal yang baru saja dia antar. Lihat [API Transport](API-TRANSPORT.md).

---

## 10. Isolasi handler

Handler berjalan di dalam `xpcall`, di dalam `Bridge:Execute`. Satu sistem yang buruk tidak
bisa menggantung gerbang untuk setiap pemain lain. Traceback-nya ditangkap dan dicatat **di
server**, tempat dia berguna; pemanggil menerima `HandlerError` dan tidak lebih.

`Bridge:Execute` sengaja **tanpa gerbang** — tanpa validasi, tanpa batas laju, tanpa
otorisasi — dan sengaja **tidak ada** di `Types.Bridge`. Dia tinggal di `NetTypes.BridgeSeam`,
yang di-cast oleh gerbang server.

Jadi satu-satunya benda di kode ini yang bisa menjangkau handler tanpa penjagaan adalah objek
yang baru saja selesai menjaganya.

---

## 11. Model ancaman — apa yang dihentikan dan apa yang tidak

**Dihentikan:**

- Memanggil perintah khusus server dari client, bagaimanapun client-nya ditambal.
- Memalsukan identitas: tidak ada field untuk itu.
- Mengirim payload yang cacat bentuk, kebesaran, terlalu dalam, bersiklus, atau membawa
  `Instance`.
- Membanjiri satu perintah, atau banyak perintah murah, atau keluar-masuk untuk mereset
  jatah.
- Mempelajari **kenapa** sebuah permintaan gagal, di luar alasan yang kasar.
- Membocorkan channel `Server` karena lupa memikirkannya.
- Handler yang error menjatuhkan gerbang, atau membuat penggunanya sendiri dilaporkan.

**Tidak dihentikan, dan memang di luar cakupan:**

- Client yang berbohong tentang input yang **sah** di dalam skemanya. Hanya kait `Authorize`,
  yang bisa melihat state game, yang bisa menilai itu.
- Kesalahan logika tingkat aplikasi di dalam sebuah handler. Gerbang membuktikan bentuknya,
  bukan maknanya.
- Analisis trafik: nama kontrak bersifat publik, jadi penyerang tahu apa saja yang ada. Itu
  memang rancangannya — gemboknya tidak berada di gedung yang sama dengan petanya.
