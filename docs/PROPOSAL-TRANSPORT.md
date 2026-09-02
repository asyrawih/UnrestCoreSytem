# Proposal — Memisahkan Lapisan Jaringan

**Status: proposal. Belum ada yang diimplementasikan. Jangan dibangun sebelum diperintahkan.**

## 1. Yang diminta

> "Gua mau nge-decouple sesuatu yaitu Network. Gimana framework ini nge-call command dari
> sisi server, begitu pula di client. Semisal implementasi Net gua mau ganti pakai ByteNet-Max.
> Tapi framework hanya menjembatani untuk definisi; pengguna sendiri yang mendefinisikannya."

Jadi dua hal. Implementasi jaringan harus bisa diganti, dan definisi paketnya harus milik
pengguna, bukan milik framework.

## 2. Koreksi terhadap draf pertama, dan jalur migrasi yang dibukanya

Draf pertama dokumen ini menyatakan bahwa amplop generik **tidak mungkin** dibuat di atas
ByteNet, karena buffer menuntut skema konkret dan tidak ada padanan untuk `any`. **Itu salah**,
dan koreksinya membuat rencana ini jauh lebih baik.

ByteNet-Max mengekspor tipe data `unknown`. Cara kerjanya bukan menyerialisasi nilainya, tapi
menitipkannya: `write` mengalokasikan satu byte berisi indeks, lalu mendorong nilai aslinya ke
tabel referensi yang ikut dikirim di luar buffer. Jadi amplop generik **bisa** dibuat, dan
sudah saya uji type-check-nya bersih:

```luau
ByteNet.definePacket({
    value = ByteNet.struct({ command = ByteNet.string, payload = ByteNet.unknown }),
})
```

Tapi bacalah apa yang sebenarnya terjadi. Nilai yang lewat `unknown` **tidak dipadatkan sama
sekali** — dia menumpang seperti argumen remote biasa. Artinya amplop generik memberi
pengelompokan paket milik ByteNet, tapi melepaskan justru manfaat yang membuat orang memilih
ByteNet. Dan karena `unknown` berarti tidak ada skema, `Validate.Payload` milik framework
kembali menanggung seluruh beban pemeriksaan bentuk.

Jadi kesimpulan draf pertama tetap berdiri, tapi dengan alasan yang benar: **satu paket per
perintah adalah pilihan yang tepat, bukan keharusan.**

Dan karena dia pilihan, ada jalur migrasi bertahap yang tidak terlihat di draf pertama:

| Tahap | Bentuk | Kerja yang dibutuhkan |
| --- | --- | --- |
| 1 | Amplop generik memakai `ByteNet.unknown` | nol per perintah; transport langsung tukar |
| 2 | Perintah yang paling sering dipanggil dikonversi ke paket bertipe | satu definisi per perintah, sesuai kebutuhan |
| 3 | Sisanya menyusul, atau tidak sama sekali | perintah yang jarang tidak perlu dibayar |

Ini jauh lebih baik daripada menuntut setiap paket didefinisikan di muka sebelum satu baris pun
bisa dijalankan. Framework tidak perlu tahu tahap mana yang sedang dipakai: bagi dia keduanya
sama-sama transport.

**Satu peringatan tentang paketnya.** `bufferWriter.reference` di ByteNet-Max 1.0.0 berisi
`print(references)` yang tertinggal, di `process/bufferWriter.luau:75`. Setiap penulisan
`unknown` akan mencetak ke output window. Kalau Tahap 1 dipakai, itu satu baris cetak per
permintaan. Perlu di-patch di sisi pengguna, atau dilaporkan ke hulu.

**Satu catatan keamanan.** ByteNet juga mengekspor `inst` untuk mengirim referensi Instance.
`Validate.Payload` milik framework menolak Instance di dalam payload, dan penolakan itu
disengaja: Instance dalam payload adalah referensi hidup ke data model yang bisa ditulis
handler. Kalau sebuah paket memakai `inst`, kebijakan framework akan tetap menolaknya, dan itu
perilaku yang benar.

## 3. Tiga hal yang sekarang tercampur di `Net/`

Yang membuat pemisahan ini tidak sepele adalah `Net/` hari ini mengerjakan tiga pekerjaan
berbeda sekaligus:

| Pekerjaan | Contoh sekarang | Boleh diganti? |
| --- | --- | --- |
| **Transport** | membuat RemoteEvent, memanggil `FireServer` | **ya**, ini yang mau diganti |
| **Codec / skema kabel** | `ArgumentSpec` dipakai sebagai bentuk payload | **ya**, dan ByteNet memang membawa codec-nya sendiri |
| **Kebijakan** | `AllowClient`, `RateLimit`, `Authorize`, batas panjang string | **tidak pernah** |

Pemisahan yang benar bukan "keluarkan Net", melainkan **keluarkan transport dan codec,
tinggalkan kebijakan**. Kalau kebijakan ikut keluar, seseorang bisa memasang transport yang
melewati `AllowClient` dan seluruh sikap keamanan framework ini hilang dalam satu baris
konfigurasi.

## 4. Arah kendali, dan kenapa ini bagian paling penting

**Transport menyerahkan permintaan mentah ke gerbang. Gerbang yang memutuskan.** Tidak pernah
sebaliknya.

Transport tidak boleh memanggil handler. Dia hanya boleh berkata "ada permintaan dari pemain
ini, namanya ini, isinya ini". Gerbang yang menjalankan urutan penolakan yang sudah ada:
perintah dikenal, boleh dipanggil client, realm cocok, laju masih cukup, skema lolos, `Authorize`
setuju, baru handler jalan.

Kalau arahnya dibalik, transport jadi tempat kebijakan bisa dilewati, dan setiap transport baru
jadi permukaan serangan baru. Dengan arah ini, transport paling buruk sekalipun hanya bisa
mengirim sampah ke gerbang, dan gerbang menolaknya seperti biasa.

## 5. Antarmuka transport

Kecil, dan itu memang tujuannya. Kalau antarmukanya besar, tiap transport baru harus
mengimplementasikan ulang setengah framework.

**Sisi server:**

| Metode | Tugas |
| --- | --- |
| `Start()` | siapkan objek jaringannya |
| `OnRequest(handler)` | serahkan tiap permintaan masuk sebagai `(player, command, payload, wantsResponse)` dan kembalikan hasilnya |
| `PublishTo(player, channel, value)` | kirim satu nilai ke satu pemain |
| `PublishAll(channel, value)` | siarkan |
| `Destroy()` | bongkar |

**Sisi client:**

| Metode | Tugas |
| --- | --- |
| `Start()` | tunggu objek jaringannya siap |
| `Send(command, payload)` | kirim, tanpa menunggu |
| `Request(command, payload)` | kirim dan tunggu hasil |
| `OnPublish(handler)` | serahkan tiap nilai masuk sebagai `(channel, value)` |
| `Destroy()` | bongkar |

Sepuluh metode. Itu seluruh permukaannya.

Yang **tidak** ada di daftar ini, dan sengaja: validasi, pembatasan laju, otorisasi, penghitung
penyalahgunaan, dan retensi channel. Semuanya tetap di framework.

## 6. Di mana definisi ByteNet tinggal

Ini bagian "framework hanya menjembatani, pengguna yang mendefinisikan".

Kontrak perintah mendapat satu field baru yang **framework tidak pernah lihat isinya**:

```luau
-- src/game/Contracts.luau -- milik game, bukan framework
Contracts:Declare({
    Name = Names.Commands.MusicPlay,
    Realm = "Server",
    AllowClient = true,
    RateLimit = { Count = 4, Window = 1 },
    Payload = { Kind = "string", MaxLength = 64, Pattern = "^[%w_%-%.]+$" },

    -- Milik transport. Framework meneruskannya, tidak pernah membacanya.
    Wire = Packets.MusicPlay,
})
```

**Prasyarat ini sudah terpenuhi, dan bukan oleh proposal ini.** Waktu dokumen ini pertama
ditulis, kontrak masih berupa tabel statis di dalam framework, sehingga `Wire` berarti framework
memegang sesuatu milik pengguna. Setelah isi game dikeluarkan, kontrak jadi registry yang diisi
game lewat `Contracts:Declare`, jadi `Wire` sekarang **milik game secara struktural**, bukan
karena framework berjanji tidak mengintipnya. Yang tersisa cuma menambahkan field opsional itu
ke tipe kontrak dan meneruskannya ke transport.

**Kenapa satu tempat, bukan dua.** Godaannya adalah membiarkan pengguna mendefinisikan paket di
tempat terpisah dan mencocokkannya lewat nama. Itu berarti dua daftar yang harus tetap seiring,
dan yang satu diam-diam menang di kabel sementara yang lain menang di kebijakan. Menaruh
keduanya di baris yang sama membuat ketidaksesuaian terlihat saat dibaca.

## 7. Skema kabel tidak menggantikan validasi kebijakan

Ini yang paling mudah salah dipahami, jadi ditulis eksplisit.

ByteNet akan menolak buffer yang tidak sesuai skema, jadi **pemeriksaan bentuk memang jadi
gratis**. Tapi bentuk bukan kebijakan. Skema `uint8` tidak tahu bahwa volume harus antara 0 dan
1. Skema `string` tidak tahu batas panjang, tidak tahu pola yang diizinkan, dan sama sekali tidak
tahu apakah pemain ini boleh meminta perintah itu.

Aturannya, tanpa pengecualian: **framework tidak pernah menganggap transport sudah memvalidasi
apa pun.** `Validate.Payload` tetap jalan di server untuk setiap permintaan, di transport mana
pun. Kalau ternyata ByteNet membuatnya mubazir untuk satu perintah, biayanya adalah beberapa
mikrodetik. Kalau anggapan sebaliknya diambil dan ternyata salah, biayanya adalah lubang
keamanan.

Yang **boleh** berubah: batas ukuran payload dan kedalaman tabel jadi kurang relevan, karena
buffer sudah dibatasi skemanya. Tapi aturannya tetap dijalankan, karena transport bawaan masih
membutuhkannya.

## 8. Channel juga jadi paket

Retensi, visibilitas, dan penyaringan per pemain tetap di framework. Yang berpindah ke transport
hanya pengirimannya.

Di ByteNet itu berarti satu paket per channel. Kontrak channel mendapat field `Wire` yang sama.
Konsekuensi yang harus diakui: channel `Player` mengirim ke satu pemain, dan itu memang didukung
ByteNet, tapi **retensi tetap milik framework** karena ByteNet tidak menyimpan nilai terakhir.
Pelanggan yang datang terlambat tetap dilayani dari cache framework, bukan dari jaringan.

## 9. Yang berubah di kode

| Berkas | Perubahan |
| --- | --- |
| `src/shared/Net/Transport.luau` | baru: tipe antarmuka, dan tidak lebih |
| `src/shared/Net/Transports/Remotes.luau` | baru: transport bawaan, isinya dipindah dari `Net/init.luau` dan `Net/Client.luau` |
| `src/shared/Net/Client.luau` | menyusut jadi penjaga kontrak plus panggilan ke transport |
| `src/server/Net/Server.luau` | gerbangnya tetap; hanya cara permintaan tiba dan cara publish keluar yang lewat transport |
| `src/shared/Net/Types.luau` | tambah `Wire` opsional di kontrak perintah dan channel |
| `src/shared/Net/Contracts.luau` | `Declare` dan `DeclareChannel` meneruskan `Wire` apa adanya, tanpa memeriksanya |
| `src/shared/init.luau` | terima transport opsional saat konstruksi; bawaannya Remotes |
| `src/game/Packets.luau` | **milik pengguna**: definisi ByteNet, satu per perintah |
| `src/game/Transport.luau` | **milik pengguna**: adapter ByteNet yang memenuhi antarmuka Transport |

Transport ByteNet **tidak** ikut framework. Dia contoh di dokumen, atau paket terpisah milik
pengguna. Framework tidak boleh punya ketergantungan ke ByteNet.

## 10. Apa lagi yang bisa dipisah

Bagian ini ditulis sebelum survei ketergantungan dijalankan dan sebelum sebagian dikerjakan.
Keadaan sekarang:

**Sudah selesai:**

- **Isi game keluar dari framework.** 71 referensi jadi nol. Kontrak, nama channel dan perintah,
  preset, dan tipe sistem game semuanya pindah ke `ReplicatedStorage.Game`, sejajar dengan
  framework, bukan di dalamnya.
- **Diagnostics dilepas**, dan terbukti bisa dihapus tanpa merusak apa pun.

**Layak, belum dikerjakan:**

- **`Primitives` + `Signal` + `Maid` jadi paket daun.** Cukup mengubah dua baris require yang
  hari ini menunjuk `Types` padahal setiap simbol yang dipakai berasal dari `Primitives`. Itu
  juga memutus dua siklus yang muncul kalau framework ini dipecah jadi paket Wally.
- **`Core` berdiri sendiri.** Terverifikasi nol pengetahuan soal UI dan jaringan; satu-satunya
  kaitan adalah handle opaque yang tidak pernah dibacanya.
- **`Adapters/Classes` sebagai paket data murni.** 791 baris pengetahuan kelas Roblox dengan nol
  ketergantungan runtime.

**Jangan dipisah:**

- **`Adapters`, `Elements`, dan `Query` ke paket berbeda.** 21 simbol melintasi batas, 14 di
  antaranya predikat aturan bersama. Codebase ini sudah empat kali kena pola satu pertanyaan
  dijawab dua tempat, dan batas paket berversi menaikkan harga jawaban yang benar. Arah yang
  tepat berlawanan: kurangi jumlah tempat.
- **`Util/Resolver`.** Namanya utility, isinya kembar runtime dari tipe framework.

## 11. Pertanyaan terbuka

1. **Satu paket per perintah berarti pengguna menulis dua deklarasi**, kontrak dan paket, di
   baris yang sama tapi tetap dua. Bisakah framework menurunkan skema ByteNet dari `ArgumentSpec`
   yang sudah ada? Kelihatannya bisa untuk kasus sederhana dan tidak bisa untuk yang rumit, dan
   setengah-setengah lebih buruk daripada tidak sama sekali.
2. **Bagaimana `Invoke` dipetakan?** ByteNet berorientasi paket satu arah. Pola tanya-jawab
   biasanya dibangun dari dua paket plus id korelasi. Itu pekerjaan transport, tapi
   `InvokeTimeout` milik framework, dan keduanya harus sepakat.
3. **Apakah transport boleh menolak sendiri?** Buffer rusak gagal deserialisasi di transport,
   sebelum gerbang melihatnya. Penolakan itu harus tetap tercatat di penghitung penyalahgunaan,
   jadi transport butuh jalan melapor tanpa diberi kuasa memutuskan.
4. **Satu transport untuk semuanya, atau per perintah?** Mencampur ByteNet untuk yang sering dan
   remote biasa untuk yang jarang itu masuk akal, tapi menggandakan permukaan.

## 12. Status

Dokumen ini ditulis sebagai proposal, dan dibiarkan utuh sebagai catatan rancangan.

**Sebagian isinya sudah dibangun sejak dokumen ini ditulis.** Antarmuka transport ada di
`src/shared/Net/Transport.luau`, `Unrest:UseTransport` ada di composition root, dan sebuah
transport ByteNet milik game ada di `src/game/Transport.luau` bersama `src/game/Packets.luau`.

Untuk keadaan yang sekarang benar-benar berjalan, baca [API Transport](API-TRANSPORT.md).
Halaman ini tetap berguna untuk **alasan** di balik bentuknya — terutama bagian 4 tentang arah
kendali, dan bagian 7 tentang kenapa skema kabel tidak menggantikan validasi kebijakan.

Bagian yang belum dibangun: paket bertipe per perintah (Tahap 2 dan 3 di bagian 2), dan
pemisahan-pemisahan lain yang dibahas di bagian 10.
