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

# Model Mental

Dokumen terpendek di repo ini, dan yang pertama harus dibaca. Kalau bagian ini sudah masuk di
kepala, sisanya cuma detail.

## Satu kalimat

**Framework ini memiliki kabel antara logika game dan UI yang kamu buat tangan, dan tidak
memiliki apa pun selain itu.**

Dia tidak membuat UI. Dia tidak menyimpan state game-mu. Dia tidak tahu game-mu tentang apa.
Dia mengurus satu hal: bagaimana sesuatu yang terjadi di logika sampai ke layar, dan bagaimana
sesuatu yang ditekan pemain sampai ke logika, tanpa keduanya saling mengenal.

## Tiga kata benda

Dibaca berurutan. Masing-masing satu tugas, dan tidak ada yang meminjam tugas tetangganya.

**System** adalah sepotong logika game yang memiliki state. Dia hidup di server. Dia tidak
pernah menyentuh Instance, tidak pernah tahu ada tombol, tidak pernah tahu ada layar. Sebuah
sistem musik tahu lagu apa yang sedang berputar; dia tidak tahu ada label yang menampilkannya.

**Bridge** adalah satu-satunya jalan antara System dan layar. Tidak ada jalan lain, dan itu
disengaja. Kalau ada jalan kedua, dua sisi akan mulai saling mengenal, dan begitu itu terjadi
merombak salah satunya berarti merombak keduanya.

**Element** adalah instance di Studio yang ikut serta lewat sebuah tag. Framework
**mengelolanya**, tidak pernah **membuatnya**. Ini pembedaan yang paling sering salah dipahami,
dan seluruh rancangan berdiri di atasnya.

## Dua kata kerja

**Publish** membawa state keluar. Nilainya ditahan, jadi pelanggan yang datang belakangan tetap
mendapat nilai terakhir. Itulah kenapa urutan tidak penting: label yang baru ditandai tiga puluh
detik setelah lagu mulai tetap menampilkan lagu yang benar di frame pertamanya.

**Dispatch** membawa niat masuk. Dia kirim-dan-lupakan, tidak pernah yield, dan tidak pernah
meninggalkan mesin ini. Perintah yang tidak ada handler-nya adalah no-op yang diam, bukan galat:
Bridge tidak tahu apa arti sebuah nama, dia cuma tahu siapa yang mendengarkannya.

```
  System  ──Publish──▶  Bridge  ──▶  Element di Studio
     ▲                    │
     └────Dispatch────────┘
```

## Empat pertanyaan, empat sumber tunggal

Ini bagian terpenting dari dokumen ini, dan sekaligus mode kegagalan framework ini.

Framework hanya menjawab empat pertanyaan. Masing-masing **harus** dijawab di satu tempat saja.

| Pertanyaan | Dijawab oleh |
| --- | --- |
| Instance ini dikelola atau tidak? | predikat tag di `Selector` |
| Kelas ini bisa apa? | registry adapter |
| Konfigurasi elemen ini apa? | resolusi atribut: milik sendiri, lalu preset, lalu warisan |
| Sampai mana sebuah tag menaungi, dan kapan itu berubah? | pembukuan cascade di `Adapters/Cascade.luau` |

**Setiap bug arsitektural serius di repo ini lahir dari satu pertanyaan yang dijawab di dua
tempat.** Sudah terjadi tiga kali: grup yang diwarisi, tag yang menurun, dan preset yang
diwarisi. Ketiganya bentuknya sama persis. Dua modul menghitung jawaban yang seharusnya identik,
lalu salah satunya diperbaiki dan yang lain tidak.

Jadi kalau kamu menambah sesuatu ke framework ini, pertanyaan pertama bukan "di mana kodenya
ditaruh", tapi **"apakah ini menambah tempat kelima yang menjawab salah satu dari empat
pertanyaan itu"**. Kalau iya, jangan.

## Empat hal yang framework ini bukan

- **Bukan library UI.** Dia tidak akan pernah membuat GuiObject. Kalau kamu ingin sesuatu
  digambar, gambar di Studio.
- **Bukan wadah state.** Channel itu papan pengumuman, bukan database. Yang memiliki state
  adalah System.
- **Bukan library jaringan.** Dia tidak punya remote, tidak punya kontrak, dan tidak punya
  argumen `Player` di mana pun. Bridge adalah bus di dalam satu mesin. Kalau game-mu perlu
  bicara antar mesin, remote itu milik game-mu, di luar framework, dan disambungkan ke Bridge
  dengan satu `Publish` atau satu `Dispatch`.
- **Bukan game-mu.** Ini yang paling gampang bocor, dan dulu memang pernah bocor: nama-nama
  Music dan Dance sempat hidup di dalam `src/shared`. Sekarang sudah tidak. Semuanya pindah ke
  sisi game, dan framework tidak lagi tahu apa-apa soal game mana pun.

## Aturan searah

Empat kalimat, dan semuanya satu arah. Kalau ada yang berbalik, ada yang salah.

1. Core tidak pernah menyentuh Instance.
2. Element tidak pernah memanggil System.
3. Semuanya menyeberang di Bridge.
4. Nama milik game mengalir ke framework, tidak pernah sebaliknya.

Yang keempat gampang dilanggar tanpa sadar. `Constants.luau` memegang kosakata framework — tag,
nama-nama atribut, himpunan yang bisa diwariskan — dan **tidak satu pun nama milik game**. Nama
channel dan nama perintah ditulis di sebelah kode yang menanganinya; framework menerimanya
sebagai string buram dan tidak pernah mengejanya sendiri.

Dan ada aturan searah kelima, yang bentuknya sama: **kode game meng-`require` framework,
framework tidak pernah meng-`require` kode game.**

## Kenapa tag, bukan kode

Satu tag di sebuah wadah membuat seluruh isinya dikelola. Itu satu-satunya cara ikut serta, dan
sengaja cuma satu.

Alasannya bukan kenyamanan. Kalau ikut sertanya lewat kode, maka setiap kali desainer memindahkan
sebuah tombol, seseorang harus menyunting Luau. Dengan tag, tombol boleh berpindah, berganti
nama, berganti kelas, dan berganti tata letak tanpa satu baris kode pun berubah. Itu seluruh
alasan framework ini ada.

Atribut adalah lapisan berikutnya dari gagasan yang sama: perakitan yang dinyatakan di Studio,
oleh orang yang membangun layarnya, bukan di skrip oleh orang yang tidak melihatnya. Dan atribut
**tidak memberi hak istimewa apa pun** — dia lewat `Bridge:Dispatch` yang sama persis dan
sampai ke handler yang sama dengan Luau tulisan tangan. Dari seberang Bridge, layar yang dirakit
di Studio dan layar yang dirakit di kode tidak bisa dibedakan.

## Kapan berhenti memakai atribut

Atribut menyatakan satu perintah tetap. Begitu perilakunya bergantung pada keadaan sekarang,
misalnya "putar kalau sedang diam, hentikan kalau sedang berbunyi", atribut sudah tidak cukup dan
kamu turun ke `Unrest:Query`. Kalau yang kamu rakit adalah kontrol berbagai bagian — slider,
sakelar — mulai dari [Widgets](API-WIDGETS.md), bukan dari query tulisan tangan.

Itu bukan kegagalan atribut, itu batas yang jelas. Dan karena peran sebuah elemen jatuh balik ke
namanya, sering kali menamai elemen dengan benar sudah menggantikan atribut sepenuhnya.

## Urutan membaca

1. Dokumen ini.
2. [Panduan Memulai](GETTING-STARTED.md) — langkah demi langkah, dari folder kosong sampai
   perintah pertama yang benar-benar terkirim.
3. [Modul Bersama Game](GAME-MODULE.md) — tempat nama, preset, dan sistem milik game-mu
   tinggal.
4. [Arsitektur](ARCHITECTURE.md) — kontrak antar lapis, kalau kamu akan menyunting
   framework-nya.
5. [Peta API](API-OVERVIEW.md) dan [Referensi UI](UI-BINDING.md) — referensi, dibuka saat
   dibutuhkan, bukan dibaca dari depan.

Berkas `PROPOSAL-*` adalah rancangan. Jangan membacanya sebagai deskripsi kode yang ada.
