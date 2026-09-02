# Proposal — Memisahkan Lapisan Jaringan

**Status: proposal. Belum ada yang diimplementasikan. Jangan dibangun sebelum diperintahkan.**

## 1. Yang diminta

> "Gua mau nge-decouple sesuatu yaitu Network. Gimana framework ini nge-call command dari
> sisi server, begitu pula di client. Semisal implementasi Net gua mau ganti pakai ByteNet-Max.
> Tapi framework hanya menjembatani untuk definisi; pengguna sendiri yang mendefinisikannya."

Jadi dua hal. Implementasi jaringan harus bisa diganti, dan definisi paketnya harus milik
pengguna, bukan milik framework.

## 2. Satu temuan yang menentukan seluruh bentuk rancangan

Gerbang jaringan sekarang berbentuk **satu amplop generik**: satu RemoteEvent dan satu
RemoteFunction, dengan nama perintah sebagai string dan payload sebagai `any`. Itu bekerja
karena remote Roblox menerima nilai apa pun.

**ByteNet tidak bisa melakukan itu.** Dia menyerialisasi ke buffer, dan buffer menuntut skema
konkret: `uint8`, `string`, `struct { ... }`. Tidak ada padanan untuk `any`. Artinya satu amplop
generik **tidak mungkin dibuat di atas ByteNet**, dan bukan karena rancangannya kurang bagus,
tapi karena itu memang harga dari serialisasi buffer.

Konsekuensinya: memakai ByteNet **memaksa satu paket per perintah**. Itu bukan kekurangan, itu
justru sisi kuatnya, karena nama perintah tidak perlu ikut dikirim di kabel sama sekali. Tapi
itu berarti rancangan pemisahannya harus mengakomodasi transport yang punya definisi per
perintah, bukan sekadar transport yang mengirim tabel.

Seluruh rancangan di bawah ini turun dari satu kalimat itu.

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
[Commands.MusicPlay] = {
    Name = Commands.MusicPlay,
    Realm = "Server",
    AllowClient = true,
    RateLimit = { Count = 4, Window = 1 },
    Payload = { Kind = "string", MaxLength = 64, Pattern = "^[%w_%-%.]+$" },

    -- Milik transport. Framework meneruskannya, tidak pernah membacanya.
    Wire = Packets.MusicPlay,
}
```

`Packets.MusicPlay` adalah definisi ByteNet milik pengguna, di file pengguna. Framework
menyerahkannya ke transport dan tidak tahu apa-apa soal isinya. Transport bawaan mengabaikan
field itu sepenuhnya.

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
| `src/shared/Net/Types.luau` | tambah `Wire` di kontrak perintah dan channel |
| `src/shared/init.luau` | terima transport opsional saat konstruksi; bawaannya Remotes |

Transport ByteNet **tidak** ikut framework. Dia contoh di dokumen, atau paket terpisah milik
pengguna. Framework tidak boleh punya ketergantungan ke ByteNet.

## 10. Apa lagi yang bisa dipisah

Penilaian awal. Satu agent sedang mengukur ketergantungan nyata antar modul, dan bagian ini
akan diperbarui dengan angkanya.

**Yang jelas layak:**

- **`Util/` (Signal, Maid, Resolver)** — tidak bergantung pada apa pun di framework selain tipe.
  Setiap project Roblox butuh ini.
- **`Presets.luau` dan isi `Contracts.luau`** — keduanya tabel data. Bentuknya milik framework,
  isinya milik game. Yang perlu dipisah adalah isinya, dan itu sudah hampir terjadi.
- **`Diagnostics.luau`** — sudah opsional, dan barusan terbukti: file itu dihapus dan tidak ada
  yang rusak.

**Yang perlu dipikir dua kali:**

- **`Adapters/`** — kelihatan paling terpisah karena isinya cuma pengetahuan kelas Roblox. Tapi
  `Elements` dan `Query` sama-sama menanyakan pertanyaan yang jawabannya harus tunggal.
- **`Core/`** — registry sistem yang secara prinsip tidak tahu apa-apa soal UI dan jaringan.
  Kandidat kuat, tapi nilainya kecil karena ukurannya memang kecil.

**Yang jangan dipisah:**

- **`Adapters`, `Elements`, dan `Query` ke paket berbeda.** Codebase ini sudah **dua kali** kena
  pola bug yang sama: dua tempat menjawab satu pertanyaan dengan cara berbeda, pertama soal grup
  yang diwarisi dan kedua soal tag yang menurun. Perbaikannya selalu memaksa aturannya tinggal di
  satu tempat. Memisahkan ketiganya ke balik batas paket membuat pola itu **lebih mungkin**
  terulang, bukan kurang, karena aturan bersama jadi harus diekspor dan diversikan.

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

Proposal. Belum ada kode.
