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

# Adopsi dan Tag

Bagaimana sebuah instance Studio masuk ke dalam framework, dan bagaimana dia keluar lagi.

---

## 1. Pendaftarannya satu tag

```
Tag CollectionService:  Unrest
```

Beri tag pada sebuah instance, dan sejak detik itu:

1. sebuah **adapter** diresolusi untuk `ClassName`-nya, jadi framework tahu event apa yang dia
   punya dan properti apa yang boleh ditulis padanya;
2. atribut **`Unrest*`**-nya dibaca dan disambungkan — termasuk perintah yang dia kirim dan
   channel yang dia ikuti, tanpa satu baris kode pun;
3. dia jadi terlihat oleh **`Unrest:Query`**.

Cabut tagnya (atau hancurkan instance-nya) dan semuanya dilepas, dalam satu langkah, tanpa
ada yang tertinggal tersambung.

```luau
-- Di Studio: View → Tag Editor → tambahkan "Unrest" ke instance-nya.
-- Atau, dari kode:
game:GetService("CollectionService"):AddTag(button, "Unrest")
```

**Penandaan hidup dua arah.** Query yang dibuat sebelum elemennya ada akan mengikat elemen itu
sedetik setelah dia ditandai; elemen yang ditandai saat sesi berjalan diadopsi pada sesi itu
juga. Tidak ada yang perlu di-restart, tidak ada skrip yang perlu dijalankan ulang.

**Adopsinya khusus client.** `ScreenGui` bertag memang ada juga di server, tapi mengikat
event-nya di sana akan menyesatkan: peristiwa UI adalah sebuah **permintaan**, dan otoritasnya
adalah kontrak perintah yang dituju permintaan itu — tidak pernah tombolnya.

---

## 2. Tagnya menurun

Menandai sebuah instance mengelola instance itu **dan setiap `GuiObject` di bawahnya**. Satu
layar didaftarkan dengan satu tag pada wadahnya, bukan dengan empat puluh tag pada empat puluh
tombol:

```
ScreenGui  ← beri tag "Unrest" di sini, sekali
└── Frame                     dikelola
    ├── UIListLayout          tidak dikelola — lihat di bawah
    ├── TextButton "Play"     dikelola
    ├── TextButton "Stop"     dikelola
    └── TextLabel  "Now"      dikelola
```

Tandai satu tombol saja dan kamu tetap dapat satu tombol, karena tombol jarang punya anak
`GuiObject`. Ini satu aturan, dan dia terbaca benar dari kedua arah.

**Tidak ada kelas adopsi kedua.** Elemen yang diadopsi lewat penurunan adalah elemen biasa: dia
meresolusi adapter, membaca atribut `Unrest*`-nya sendiri, mewarisi yang bisa diwariskan, dan
ditemukan `Unrest:Query({ Tag = "Unrest", ... })`.

### Hanya keturunan `GuiObject` yang ikut terbawa

`UIListLayout`, `UIPadding`, `UICorner`, atau `UIStroke` di bawah `Frame` bertag **dibiarkan
saja**. Mereka tidak membawa event dan ada untuk menata benda lain, jadi mengadopsi mereka
cuma jadi kebisingan di `All()` dan di setiap query.

Menandai salah satunya sendiri tetap mengadopsinya. Itulah cara kamu mengikat sebuah channel
ke `UIStroke.Color`, dan itu tetap bekerja persis seperti dulu.

---

## 3. `UnrestIgnore` — jalan keluarnya

| | |
| --- | --- |
| `UnrestIgnore` | `true` |

Set pada instance mana pun dan penurunan tag **berhenti di situ**: instance itu dan semua di
bawahnya dilepas, dan tidak ada yang di bawahnya akan diadopsi.

Ini jalan darurat untuk satu subtree dekoratif di dalam layar yang selebihnya dikelola.

```
ScreenGui  ← tag "Unrest"
├── Buttons              dikelola
│   └── TextButton       dikelola
└── Decor                UnrestIgnore = true → dilepas
    ├── ImageLabel       tidak dikelola
    └── Frame            tidak dikelola
```

**Hidup dua arah.** Centang kotaknya di Studio saat game berjalan dan subtree-nya dilepas;
hapus centangnya dan subtree-nya diadopsi kembali. Tidak ada yang di-restart.

Tiga detail yang perlu kamu tahu:

* **Harus boolean `true`.** Satu-satunya atribut yang bisa mengeluarkan elemen dari framework
  bukanlah atribut yang menebak-nebak `"true"` yang diketik sebagai string.
* **Tag mengalahkannya.** `UnrestIgnore` mengeluarkan subtree dari sebuah **penurunan**, jadi
  menandai satu instance di dalam subtree yang diabaikan tetap mengadopsi instance itu —
  termasuk `UIStroke` yang ingin kamu ikat ke sebuah channel.
* Instance yang **bertag sekaligus diabaikan** mengelola dirinya sendiri dan menghentikan
  penurunan di bawahnya. Kedua atribut tetap berarti persis seperti bunyinya.

---

## 4. Apa yang hidup, dan berapa ongkosnya

| Suntingan | Hasilnya |
| --- | --- |
| menandai sebuah wadah | wadah itu dan setiap `GuiObject` di bawahnya diadopsi, saat itu juga |
| mencabut tagnya | semuanya dilepas — kecuali ada leluhur bertag kedua, atau tag mereka sendiri, yang masih menaungi |
| memindahkan `GuiObject` masuk ke subtree yang dikelola | diadopsi saat tiba |
| memindahkannya keluar | dilepas, kecuali ada sesuatu yang masih menaunginya di tempat barunya |
| menyetel `UnrestIgnore` | subtree itu dilepas |
| menghapus `UnrestIgnore` | subtree itu diadopsi kembali |

**Tag bersarang tidak berebut.** Elemen yang dinaungi dua leluhur bertag tetap dikelola sampai
keduanya hilang, karena naungan itu **dihitung ulang** pada setiap perubahan, bukan
diakumulasi. Apa pun yang terjadi, framework bertanya lagi: "apakah ini dikelola?" Tidak ada
penghitung referensi yang bisa dikurangi dalam urutan yang salah.

### Anggaran koneksinya

Sengaja dibuat dangkal.

* Satu `DescendantAdded` per **akar** bertag — bukan satu per keturunan.
* Kepergian tidak diawasi di akarnya sama sekali. Setiap elemen yang diadopsi sudah mengawasi
  `AncestryChanged`-nya sendiri, dan sinyal itu menyala **setelah** perpindahan dengan induk
  finalnya sudah terpasang, jadi pertanyaan yang diajukan ulang punya jawaban yang benar.
* Satu pengawasan `UnrestIgnore` per elemen yang diadopsi (yang sudah membawa maid).
* Satu pengawasan per **gerbang** — yaitu instance yang membawa `UnrestIgnore`, atau `Folder`
  yang dilewati penurunan tag.

Gerbang itu jumlahnya segenggam per layar, bukan satu per `UICorner`.

---

## 5. Empat pertanyaan, empat sumber tunggal

Bagian ini pendek tapi penting, dan dia adalah mode kegagalan framework ini.

Framework hanya menjawab empat pertanyaan. Masing-masing **harus** dijawab di satu tempat
saja.

| Pertanyaan | Dijawab oleh |
| --- | --- |
| Instance ini dikelola atau tidak? | predikat tag di `Selector` |
| Kelas ini bisa apa? | registry adapter |
| Konfigurasi elemen ini apa? | resolusi atribut: milik sendiri, lalu preset, lalu warisan |
| Client boleh minta ini? | kontrak perintah |

Setiap bug arsitektural serius di repo ini lahir dari satu pertanyaan yang dijawab di dua
tempat. Jadi kalau kamu menambah sesuatu, pertanyaan pertamanya bukan "kodenya ditaruh di
mana", tapi **"apakah ini menambah tempat kelima yang menjawab salah satu dari empat
pertanyaan itu"**. Kalau iya, jangan.

Selengkapnya di [Model Mental](MENTAL-MODEL.md).

---

## Selanjutnya

* **[Referensi Atribut](UI-ATTRIBUTES.md)** — apa yang bisa kamu tulis pada elemen yang sudah
  diadopsi.
* **[API Elements & Query](API-ELEMENTS.md)** — cara memilih elemen dari kode.
