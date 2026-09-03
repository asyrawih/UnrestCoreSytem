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

# Modul Bersama Game

Halaman ini menjawab satu pertanyaan: **apa yang wajib aku deklarasikan di modul yang dibaca
client dan server sekaligus?**

Jawaban singkatnya, dan halaman ini pendek justru karena itu:

> **Framework tidak menuntut apa pun.** Satu-satunya alasan kamu masih butuh modul bersama
> adalah karena *game-mu* mengirim pesan sendiri antar mesin, dan kedua sisi harus sepakat
> soal bentuk pesannya.

Kalau game-mu tidak pernah menyeberangi mesin, kamu tidak butuh modul bersama sama sekali.

---

## 1. Kenapa halaman ini jadi sependek ini

Rancangan lama menuntut satu modul bersama yang mendeklarasikan setiap perintah, setiap
channel, kebijakan siapa boleh memanggil apa, plus format kabelnya. Itu ditolak, dan alasannya
lugas: **terlalu banyak yang harus ditulis pemakai sebelum satu tombol pun jalan**, dan
sebagian besar yang ditulis itu cuma mengulang hal yang sudah kelihatan di kodenya sendiri.

Yang tersisa sekarang adalah lapisan yang memang tidak bisa dihindari: kalau dua mesin
bertukar pesan, keduanya harus membaca skema yang sama. Sisanya hilang.

Framework ini murni abstraksi UI. Dia tidak membawa jaringan, tidak punya registry perintah,
dan tidak memvalidasi payload. `Bridge` adalah bus lokal — lihat [API Bridge](API-BRIDGE.md).
Perintah dan channel adalah string biasa yang framework antar apa adanya.

---

## 2. Satu-satunya modul bersama: `GameNet`

Di disk letaknya `src/game-net/`. Di DataModel dia muncul **di sebelah** framework, bukan di
dalamnya:

```
ReplicatedStorage
├── Unrest        ← framework
├── GameNet       ← punyamu, dibaca dua realm
└── Packages      ← dependensi Wally
```

Isinya, seluruhnya, cuma format kabel game ini:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNetMax = require(ReplicatedStorage.Packages.ByteNet)

return ByteNetMax.defineNamespace("Game", function()
    return {
        packets = {
            Beli = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Barang = ByteNetMax.string }),
            }),
            Koin = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Nilai = ByteNetMax.uint32 }),
            }),
            Pesan = ByteNetMax.definePacket({
                value = ByteNetMax.struct({ Teks = ByteNetMax.string }),
            }),
        },
    }
end)
```

Tiga hal yang menjelaskan bentuk itu:

* **Dia harus bersama.** ByteNet memberi id pada paket berdasarkan urutan definisinya, jadi
  kedua realm wajib membaca berkas yang sama supaya id-nya sepakat. Ini satu-satunya alasan
  modul ini dibaca dua sisi.
* **Satu paket per jenis pesan**, bukan satu amplop serbaguna. Amplop serbaguna butuh
  `ByteNet.unknown`, yang tidak memak apa-apa dan cuma menitipkan nilainya di samping buffer
  seperti argumen remote biasa. Harganya jujur: channel baru berarti paket baru di sini plus
  satu pemetaan di client.
* **Tidak ada satu pun nama framework di berkas ini.** Tidak ada `Unrest`, tidak ada
  `Bridge`. Modul ini tidak tahu framework itu ada, dan framework tidak tahu modul ini ada.

Arah ketergantungannya tetap satu arah, seperti dulu:

> **Kode game meng-`require` framework. Framework tidak pernah meng-`require` kode game.**
> Tidak ada satu berkas pun di `src/shared` yang boleh menyebut `ReplicatedStorage.GameNet`.

---

## 3. Yang **tidak** perlu kamu deklarasikan di mana pun

Ini bagian yang paling berguna kalau kamu pernah membaca versi lama halaman ini.

| Dulu ditulis di modul bersama | Sekarang |
| --- | --- |
| Daftar nama perintah | Tidak ada. String biasa, dieja di tempat dia dipakai. |
| Daftar nama channel | Tidak ada. Sama, string biasa. |
| Izin "perintah ini boleh dipanggil client" | Tidak ada konsepnya. `Bridge` tidak menyeberangi mesin, jadi tidak ada yang perlu diizinkan. |
| Skema payload dan batas laju per perintah | Kamu sendiri yang memeriksa, di tempat paket diterima. Lihat `src/game-server/init.server.luau`. |
| Berkas tipe bersama untuk sistem-sistemmu | Tiap sistem mengekspor tipenya dari modulnya sendiri (`export type Dompet = typeof(Dompet)` di `Dompet.luau`). |
| Pilihan pustaka jaringan | Tidak ada tempatnya lagi di framework. Kamu memanggil pustakamu langsung. |

---

## 4. Lalu nama perintah dan channel tinggal di mana?

**Di sebelah kode yang menanganinya.** Itu aturannya, dan framework memang tidak boleh
mengeja satu pun dari nama-nama itu.

| Nama | Diketik di mana saja | Jenisnya |
| --- | --- | --- |
| `"Toko.Beli"` | `src/game-server/init.server.luau` (`Bridge:Dispatch`) dan `src/game-server/Systems/Toko.luau` (`Bridge:Handle`) | perintah, server saja |
| `"Koin"` | `src/game-client/Shop.luau` (`Bridge:Publish`) dan atribut `UnrestChannel` di Studio | channel, client saja |
| `"Pesan"` | sama seperti `"Koin"` | channel, client saja |

Perhatikan bahwa tidak satu pun dari nama itu menyeberangi mesin. Yang menyeberang adalah
paket. Nama channel diputuskan **di sisi penerima**: `Toko` mengirim paket `Koin` tanpa pernah
menyebut kata "channel", dan client yang memutuskan paket itu berarti channel `"Koin"`.

Harga dari kebebasan ini harus dikatakan terang-terangan:

> **Nama yang salah ketik itu diam.** `Bridge:Dispatch` ke nama yang tidak ada handler-nya
> adalah no-op tanpa galat, dan `UnrestChannel` yang tidak cocok dengan `Publish` mana pun
> membuat label tidak pernah terisi. Tidak ada yang menangkapnya untukmu.

Versi lama pernah menerbitkan `"koin"` huruf kecil sementara Studio menulis `Koin`, dan saldo
pembuka tidak pernah tergambar sekali pun tanpa satu baris merah di Output. Kalau sebuah nama
dipakai di lebih dari satu berkas, angkat jadi konstanta lokal di berkas yang memilikinya,
lalu impor dari sana.

---

## 5. Preset — satu-satunya deklarasi opsional yang tersisa

`UnrestPreset` adalah satu-satunya atribut yang isinya harus didaftarkan lebih dulu di kode.
Framework tidak membawa satu preset pun, karena preset menyebut nama channel atau perintah,
dan nama itu milik game.

```luau
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)
local Presets = require(ReplicatedStorage.Unrest.Presets)

local ATTRIBUTES = Constants.Attributes

Presets.Register("LabelKoin", {
    [ATTRIBUTES.Channel] = "Koin",
    [ATTRIBUTES.Bind] = "Text",
    [ATTRIBUTES.Format] = "Koin: {value}",
})
```

Dua hal soal tempat menaruhnya:

* **Ini bukan modul bersama.** Preset hanya berarti di realm yang mengadopsi UI, dan adopsi
  cuma terjadi di client. Taruh di `src/game-client/`, dan jalankan sebelum
  `Unrest:Start()`.
* **Kuncinya wajib nama atribut `Unrest*`.** `Presets.Register` melempar error untuk kunci
  lain, jadi pakai `Constants.Attributes` dan biarkan salah ketik jadi indeks nil.

Game contoh di repo ini tidak mendaftarkan satu preset pun — atributnya diketik langsung di
Studio. Itu sah. Preset adalah kenyamanan supaya "apa itu label koin" diputuskan sekali di
kode yang bisa ditelaah, bukan syarat. Selengkapnya di [API Presets](API-PRESETS.md).

---

## 6. Daftar periksa

- [ ] Ada `src/game-net/init.luau` **kalau dan hanya kalau** game-mu mengirim pesan antar
      mesin. Kalau tidak, hapus saja.
- [ ] Kedua realm meng-`require` berkas paket yang sama, supaya id paketnya sepakat.
- [ ] Client memakai `ReplicatedStorage:WaitForChild("GameNet")`, karena replikasi belum
      tentu selesai saat script client jalan.
- [ ] Setiap paket yang masuk diperiksa bentuknya di tempat dia diterima — tidak ada lapisan
      lain yang melakukannya.
- [ ] Identitas pemain diambil dari argumen kedua `listen`, **tidak pernah** dari isi paket.
- [ ] Nama channel yang diterbitkan `Bridge:Publish` sama persis, huruf demi huruf, dengan
      `UnrestChannel` yang diketik di Studio.
- [ ] Tidak ada satu pun berkas di `src/shared` yang menyebut `ReplicatedStorage.GameNet`
      atau `ServerScriptService.Game`.

Langkah demi langkahnya, dari folder kosong sampai tombol pertama, ada di
[Panduan Memulai](GETTING-STARTED.md).
