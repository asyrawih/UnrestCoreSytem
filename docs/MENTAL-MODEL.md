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

**Dispatch** membawa niat masuk. Setiap dispatch melewati kontrak yang memutuskan apakah client
boleh memintanya sama sekali. Tombol tidak punya kuasa; kontraknya yang punya.

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
| Client boleh minta ini? | kontrak perintah |

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
- **Bukan library jaringan.** Dia memiliki kebijakan siapa boleh memanggil apa; cara byte
  bergerak itu urusan transport dan bisa diganti.
- **Bukan game-mu.** Ini yang paling gampang bocor, dan dulu memang pernah bocor: nama-nama
  Music dan Dance sempat hidup di dalam `src/shared`. Sekarang sudah tidak. Semuanya pindah ke
  `src/game`, dan framework tidak lagi tahu apa-apa soal game mana pun.

## Aturan searah

Empat kalimat, dan semuanya satu arah. Kalau ada yang berbalik, ada yang salah.

1. Core tidak pernah menyentuh Instance.
2. Element tidak pernah memanggil System.
3. Semuanya menyeberang di Bridge.
4. Kebijakan hidup di server dan tidak pernah direplikasi.

Yang keempat bukan soal kerapian, melainkan keamanan. Gerbang yang memutuskan apa yang boleh
diminta client tinggal di `ServerScriptService`, sehingga mesin yang diaturnya tidak bisa
membacanya. Kontraknya sendiri boleh dibaca siapa saja: itu daftar nama pintu, dan gemboknya ada
di server.

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
**tidak memberi hak istimewa apa pun** — dia melewati gerbang yang sama dengan Luau tulisan
tangan.

## Kapan berhenti memakai atribut

Atribut menyatakan satu perintah tetap. Begitu perilakunya bergantung pada keadaan sekarang,
misalnya "putar kalau sedang diam, hentikan kalau sedang berbunyi", atribut sudah tidak cukup dan
kamu turun ke `Unrest:Query`.

Itu bukan kegagalan atribut, itu batas yang jelas. Dan karena peran sebuah elemen jatuh balik ke
namanya, sering kali menamai elemen dengan benar sudah menggantikan atribut sepenuhnya.

## Urutan membaca

1. Dokumen ini.
2. [Panduan Memulai](GETTING-STARTED.md) — langkah demi langkah, dari folder kosong sampai
   perintah pertama yang benar-benar terkirim.
3. [ModuleScript `Game`](GAME-MODULE.md) — tempat kamu mendeklarasikan nama, kontrak, dan preset
   milik game-mu.
4. [Arsitektur](ARCHITECTURE.md) — kontrak antar lapis, kalau kamu akan menyunting
   framework-nya.
5. [Peta API](API-OVERVIEW.md) dan [Referensi UI](UI-BINDING.md) — referensi, dibuka saat
   dibutuhkan, bukan dibaca dari depan.

Dua berkas `PROPOSAL-*` adalah rancangan. Jangan membaca keduanya sebagai deskripsi kode yang
ada.
