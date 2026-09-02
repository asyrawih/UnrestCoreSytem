# Mulai di sini

UnrestCoreSystem adalah framework UI bergaya MVC untuk Roblox, ditulis dengan Luau.

Satu kalimat yang menjelaskan sisanya: **framework ini tidak membuat UI.** Kamu yang
menggambar UI-nya di Studio, lalu kamu tandai dengan tag CollectionService `Unrest`. Sejak
detik itu framework mengurusnya — menyambungkan tombol ke perintah, dan label ke state.

Kalimat kedua yang sama pentingnya: **sebuah perintah tidak bisa dijangkau client kecuali
kontraknya mengizinkan.** Menaruh atribut di Studio tidak memberi hak istimewa apa pun.

---

## Kalau kamu baru pertama kali di sini

Baca berurutan. Empat halaman, dan setelah itu kamu sudah bisa kerja.

1. **[Model Mental](MENTAL-MODEL.md)** — halaman terpendek di sini. Tiga kata benda, dua kata
   kerja, satu aturan searah.
2. **[Panduan Memulai](GETTING-STARTED.md)** — langkah demi langkah, dari folder kosong sampai
   tombol pertama yang benar-benar mengirim perintah. Halaman ini menjawab **"aku mulai nulis
   script di mana?"** untuk sisi server dan sisi client.
3. **[ModuleScript `Game`](GAME-MODULE.md)** — tempat kamu mendeklarasikan nama, kontrak, dan
   preset milik game-mu. Ini satu-satunya berkas yang **wajib** kamu isi.
4. **[Arsitektur](ARCHITECTURE.md)** — kontrak antar lapisan. Baca ini sebelum menyunting
   framework-nya sendiri.

## Kalau kamu sudah kerja dan butuh jawaban

| Butuh apa | Buka |
| --- | --- |
| Tanda tangan sebuah fungsi | [Peta API](API-OVERVIEW.md) |
| Arti sebuah atribut `Unrest*` | [Referensi Atribut](UI-ATTRIBUTES.md) |
| Kelas ini punya handler apa saja | [Kosakata Handler](UI-HANDLERS.md) dan [Cakupan Adapter](UI-ADAPTERS.md) |
| Kenapa perintahku ditolak | [Keamanan Remote](REMOTE-SECURITY.md) |
| Ada pesan galat merah di Output | [Pemecahan Masalah](TROUBLESHOOTING.md) |

---

## Tiga hal yang perlu kamu tahu tentang situs ini

### 1. Semuanya bahasa Indonesia

Nama kode tetap bahasa Inggris — `UnrestCommand`, `Bridge:Dispatch`,
`ReplicatedStorage.Game`. Itu identifier, bukan kalimat, dan menerjemahkannya cuma bikin
kodenya tidak ketemu.

### 2. Framework ini tidak tahu apa-apa soal game-mu

Dulu framework ini membawa contoh musik dan tarian di dalam dirinya sendiri. Sekarang tidak
lagi. Tidak ada `MusicSystem`, tidak ada perintah `Music.Play`, tidak ada channel
`NowPlaying` di dalam `src/shared`.

Nama-nama itu masih muncul di dokumentasi ini **sebagai contoh isi game**, karena repo ini
memang berisi satu game contoh di `src/game`. Setiap kali kamu melihatnya, ingat: itu isi
`src/game`, bukan permukaan framework. Framework hanya membawa kata-kata umum —
`System`, `Contracts`, `Bridge`, `Descriptor`.

### 3. Dua halaman menjelaskan kode yang belum ada

Kategori **Usulan** adalah rancangan, bukan dokumentasi. Isinya belum ada di `src/` dan belum
bisa dipakai. Setiap halaman di sana membawa spanduk peringatan di atasnya.

---

## Menjalankan situs ini di komputermu

```sh
npm install         # sekali saja
npm run docs:dev    # http://localhost:3000/
```

Tab **API** yang dihasilkan otomatis oleh Moonwave masih dimatikan: komentar di `src/` belum
ditulis dalam format Moonwave (`@class`, `@within`, `@prop`). Sampai itu dikerjakan, halaman
**Referensi API** di sidebar inilah referensinya, dan halaman-halaman itu ditulis tangan
langsung dari `src/shared/Types.luau`.
