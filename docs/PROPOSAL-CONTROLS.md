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

# Proposal — Controls (v2)

**Status: masih proposal.** Yang dijelaskan di sini — control yang digerakkan atribut,
`UnrestValue`, katalog — belum ada.

Yang **sudah** ada adalah langkah pertama yang jauh lebih kecil: `Unrest.Widgets`
([API Widgets](API-WIDGETS.md)). Itu API level-kode, bukan atribut: kamu menyebut peran yang
dibutuhkan dan menerima satu tabel per `UnrestGroup` beserta cleanup scope-nya. Dokumen ini
tetap proposal karena lapisan atributnya belum diambil keputusannya.

Versi 1 sudah ditelaah dua kali, satu dari sisi rancangan dan satu dari sisi ongkos. Keduanya
menemukan hal yang mematahkan asumsi, jadi dokumen ini bukan penyuntingan kecil. Bagian 0
mencatat apa yang berubah dan kenapa, supaya keputusan yang sudah pernah diambil tidak diambil
ulang tanpa sebab.

---

## 0. Apa yang berubah dari v1

| Yang berubah | Sebabnya |
| --- | --- |
| `Fill` tidak lagi dipatok ke `Size`, tapi memakai ulang `UnrestBind` | v1 mengaku menyerah pada slider berupa rona warna atau sudut putar. Ternyata tidak perlu: `Rotation`, `UIGradient.Offset`, `UIScale.Scale`, dan `CanvasGroup.GroupTransparency` semuanya sudah `Bindable`. Ini **menghapus** satu konsep, bukan menambah. |
| Atribut baru `UnrestValue` di part | Tanpa ini `TabGroup` di katalog v1 tidak bisa diimplementasikan, dan tiga perombakan wajar tidak tercakup. Satu atribut menutup ketiganya. |
| `UnrestMin` / `UnrestMax` / `UnrestStep` / `UnrestFormat` dibuang dari akar | Rentang dan format adalah urusan part yang menampilkannya, bukan urusan control. Membawanya di akar memaksa resolusi lintas-elemen yang tidak ada presedennya. |
| Katalog menyusut jadi satu entri | `ProgressBar` adalah `Slider` tanpa bagian input. Dua entri katalog untuk satu perilaku adalah ongkos konsep tanpa pengembalian. |
| Akar control tidak lagi diwiring sebagai elemen biasa | Bukan pilihan gaya. Hari ini akar control akan memuntahkan dua peringatan palsu per sesi, dan kalau akarnya `TextButton` malah benar-benar mengirim perintah cacat. |
| Bagian baru 10, kepemilikan lukisan | v1 memberi kurang dari satu paragraf untuk tiga hal yang benar-benar menentukan keberhasilan, sambil menghabiskan enam puluh persen kata untuk resolusi part yang ternyata separuh yang mudah. |
| Rekomendasi preset dibalik | `UnrestPreset` itu diwariskan dan ekspansinya per elemen, jadi preset control bocor ke setiap part. v1 justru menyebutnya tempat preset paling terbayar. |
| Uji penerimaan jadi dua | Uji tunggal v1 hanya menguji perombakan kulit dengan perilaku identik, dan ditulis absolut. Perombakan sungguhan hampir selalu membawa sedikit perilaku baru. |

---

## 1. Masalahnya

> "Tujuan gua bikin framework itu adalah ketika gua desain UI, padahal core system-nya sama
> aja. Jadi gua butuh satu hal yang mudah ketika gua nge-switch UI. Semisal gua bikin slider,
> ketika gua rombak UI-nya itu bakal berubah lagi implementasinya. Jadi gua butuh High API
> untuk ini."

Framework ini sudah menjaga agar perombakan UI tidak menyentuh core. Yang belum terlindungi
adalah lapisan di antaranya.

Slider bukan satu elemen. Dia sebuah Frame yang menentukan sumbu, sesuatu yang digeser, sesuatu
yang mengikuti, dan sesuatu yang melaporkan. Beberapa instance yang baru berarti "slider" kalau
ada yang tahu hubungan di antara mereka. Hari ini hubungan itu ditulis di dalam skrip, untuk
satu susunan pohon tertentu. Rombak desainnya dan setiap barisnya salah. Core-nya selamat;
lemnya tidak.

## 2. Kenapa yang sudah ada belum cukup

`Query` sudah menyelesaikan separuh masalah: dia menemukan sesuatu lewat peran, bukan lewat
jalur. Yang belum ada adalah **perilakunya ditulis sekali oleh framework, bukan sekali per
layar.**

Tapi ada satu kelas perombakan yang harus dicatat jujur di depan, karena dia melawan seluruh
proposal ini. Slider yang dirombak jadi tiga tombol Low/Medium/High **tidak butuh Controls sama
sekali**: tiga `TextButton` dengan `UnrestCommand = "Music.SetVolume"` dan `UnrestPayload`
masing-masing sudah jalan hari ini, dan preset `VolumeButton` memang sudah dibuat untuk pola
itu. Controls hanya menang ketika satu nilai kontinu digerakkan oleh beberapa instance yang
saling terkait. Di luar itu, lapisan atribut yang sudah ada lebih murah dan harus dipakai.

## 3. Uji penerimaan

Dua uji, bukan satu. Uji pertama saja terlalu longgar dan v1 menuliskannya terlalu percaya diri.

**Uji A, perombakan kulit.** Bangun `MenuV1` dengan sebuah slider. Belakangan bangun `MenuV2`
dari nol: tata letak berbeda, kelas berbeda, sumbu berbeda. Hapus yang lama, pasang yang baru,
tekan Play. **Nol baris Luau berubah.**

**Uji B, perombakan yang membawa sedikit perilaku baru.** `MenuV2` sama, kecuali readout-nya
sekarang persen alih-alih pecahan, dan yang digeser dihapus sehingga track-nya sendiri yang
diklik. **Perubahan yang dibutuhkan harus berada di Studio, bukan di Luau.**

Uji B adalah yang sebenarnya. Perombakan nyata hampir selalu sembilan puluh persen kulit dan
sepuluh persen perilaku baru, dan sepuluh persen itulah yang membunuh lapisan seperti ini.

## 4. Modelnya

**Control adalah perilaku bernama di atas sebuah subtree.** `UnrestControl = "Slider"` pada
sebuah Frame berarti framework yang memiliki perilaku subtree itu.

**Part adalah instance yang memainkan peran bernama di dalam subtree itu.** Ditemukan lewat
peran, tidak pernah lewat jalur.

**Part menyatakan properti yang dia tulis, bukan kelas yang harus dia miliki.** Ini perubahan
terbesar dari v1 dan penjelasannya ada di bagian 5.

Satu koreksi jujur terhadap v1. Model kemampuan tidak seampuh yang v1 klaim: `Press` dan `Size`
keduanya dideklarasikan di `GuiObject`, jadi pemeriksaannya bernilai benar untuk setiap
GuiObject yang ada. Model itu baru benar-benar menyaring setelah part menyebut properti yang dia
tulis, karena `CanBind` terhadap properti yang disebut adalah pertanyaan yang bisa dijawab
tidak.

## 5. Permukaan atribut

Di akar control:

| Atribut | Artinya |
| --- | --- |
| `UnrestControl` | nama control-nya. Menandai subtree-nya. |
| `UnrestChannel` | channel tempat control membaca nilai otoritatifnya. |
| `UnrestCommand` | perintah yang dikirim ketika pengguna mengubah nilainya. |

Tiga. Itu saja.

Di setiap part:

| Atribut | Artinya |
| --- | --- |
| `UnrestPart` | peran yang dimainkan instance ini, misal `"Track"`. |
| `UnrestBind` | properti yang ditulis control ke instance ini. Atribut yang sudah ada, dipakai ulang. |
| `UnrestValue` | rentang atau nilai tetap part ini, sebagai string berpembatas. |

**Kenapa `UnrestBind` dipakai ulang.** v1 mendefinisikan `Fill` sebagai "`Size` yang boleh
ditulis", dan karena itu mengaku menyerah pada slider yang nilainya dinyatakan sebagai rona
warna atau sudut putar. Padahal itu masalah yang kodenya sudah selesaikan. Kalau part `Fill`
menyatakan sendiri properti yang dia tulis, maka satu definisi mencakup panjang batang, sudut
jarum, offset gradient, transparansi, dan skala. Tidak ada control buatan sendiri yang
dibutuhkan, dan daftar izin `Bindable` akhirnya melakukan pekerjaan nyata.

```
Fill (Frame)         UnrestPart = "Fill"   UnrestBind = "Size"      UnrestValue = "0,1"
Needle (ImageLabel)  UnrestPart = "Fill"   UnrestBind = "Rotation"  UnrestValue = "-120,120"
Glow (CanvasGroup)   UnrestPart = "Fill"   UnrestBind = "GroupTransparency"  UnrestValue = "1,0"
```

Ketiganya part `Fill` yang sah. Control menginterpolasi dari rentang channel ke rentang part.

**Kenapa `UnrestValue` ditambahkan.** Tanpa cara memberi nilai ke sebuah part, tiga hal tidak
bisa dinyatakan sama sekali: memasangkan panel ke tab, tiga tombol preset yang masing-masing
mewakili satu nilai, dan sederet bintang yang menyala menurut nilai. `TabGroup` di katalog v1
bahkan tidak bisa diimplementasikan karena ini. Satu atribut menutup ketiganya.

**`UnrestPart` sengaja bukan `UnrestRole`,** dan alasannya lebih kuat daripada yang v1 tulis.
`Selector.roleOf` jatuh ke `Instance.Name` kalau atributnya kosong, jadi **setiap instance sudah
punya role tanpa ada yang mengetiknya**. Menumpangkan resolusi part ke Role berarti setiap Frame
dekoratif yang kebetulan bernama `Fill` jadi kandidat part. `UnrestPart` juga **tidak boleh**
masuk `Constants.Inheritable`, dan pemindaian part **mengabaikan `UnrestRole` sepenuhnya**.

## 6. Contoh nyata

### V1, horizontal

```
Volume (Frame)          UnrestControl = "Slider"
                        UnrestChannel = "Music.Volume"
                        UnrestCommand = "Music.SetVolume"
  Track (Frame)         UnrestPart = "Track"
    Fill (Frame)        UnrestPart = "Fill"   UnrestBind = "Size"  UnrestValue = "0,1"
    Knob (ImageLabel)   UnrestPart = "Knob"   UnrestBind = "Position"
  Readout (TextLabel)   UnrestPart = "Value"  UnrestBind = "Text"  UnrestValue = "0,100"
```

`Readout` menyatakan rentang tampilannya sendiri, `0,100`, sementara channel-nya tetap 0 sampai
1. Ini memperbaiki bug di contoh unggulan v1, yang dengan `UnrestFormat = "Volume {value}%"`
sebenarnya akan menampilkan `Volume 0.4312139749527%`, dan yang perbaikan naifnya
(`UnrestMax = 100`) akan ditolak skema payload di setiap gerakan.

### V2, hasil perombakan

Vertikal, knob dihapus sehingga track-nya sendiri yang diklik, fill jadi `CanvasGroup`, readout
pindah ke dalam track.

```
VolumeDial (Frame)      UnrestControl = "Slider"
                        UnrestChannel = "Music.Volume"
                        UnrestCommand = "Music.SetVolume"
  Column (Frame)        UnrestPart = "Track"
    Level (CanvasGroup) UnrestPart = "Fill"   UnrestBind = "Size"  UnrestValue = "0,1"
    Number (TextLabel)  UnrestPart = "Value"  UnrestBind = "Text"  UnrestValue = "0,100"
```

Kelas berbeda, nama berbeda, pohon berbeda, sumbu berbeda, dan satu part hilang sepenuhnya.
**Tidak ada Luau yang berubah.** Ini lolos Uji A dan Uji B sekaligus.

## 7. Katalog

**Satu entri.**

| Control | Part | Wajib |
| --- | --- | --- |
| `Slider` | Track | ya |
| | Fill, Knob, Value | tidak, berapa pun jumlahnya |

`ProgressBar` adalah `Slider` yang subtree-nya tidak menyatakan bagian input. Tidak perlu entri
sendiri: bagian 9 sudah menetapkan bahwa part opsional yang absen itu sah dan diam.

`Toggle`, `Stepper`, dan `TabGroup` dibayar setelah `Slider` terbukti, bukan sebelumnya. Sebuah
toggle hari ini sudah satu `GuiButton` dengan `UnrestCommand` dan `UnrestChannel`, tanpa satu
pun konsep baru, jadi membangunnya lebih dulu berarti membangun control pertama yang biayanya
konsep dan hasilnya nol.

## 8. Resolusi part

Aturannya tinggal di satu tempat dan dipakai semua pihak yang butuh jawabannya, mengikuti
preseden `Selector.ancestorChain` dan `Selector.cascadeUnder`.

- Control memindai subtree-nya sendiri untuk `UnrestPart`, terdekat lebih dulu.
- Pemindaian **berhenti di akar control bersarang, inklusif sebagai kandidat part, eksklusif
  sebagai jalur turun.** v1 menulisnya ambigu, dan salah satu bacaannya mematikan control
  bersarang yang juga merupakan part induknya.
- Dua instance yang mengaku part yang sama adalah peringatan, dan yang terdekat menang.
- Pengawasan langsung **gratis**: setiap GuiObject di dalam subtree sudah jadi elemen terkelola
  lewat tag berjenjang, dan setiap elemen sudah membawa pengawas untuk tiap nama di `WATCHED`.
  Tambahkan atribut control ke `WATCHED` dan tidak ada satu pun koneksi per-descendant yang
  perlu dipasang.
- v1 mensyaratkan part yang **diganti nama** ikut meresolusi ulang. Itu salah dan syaratnya
  dibuang: part ditemukan lewat atribut, bukan nama.

Konsekuensi yang harus ditulis jujur: part yang bukan GuiObject, misalnya `UIStroke` yang
dijadikan Fill, tidak diadopsi tag berjenjang sehingga tidak diawasi. Untuk Tahap 1 itu batasan
yang diakui, bukan yang didiamkan.

**Satu perbaikan wajib di luar Controls.** Daftar `WATCHED` di `Elements` berisi nama tetap,
sementara lapisan preset menyalin semua kuncinya. Kalau atribut control tidak ditambahkan ke
`WATCHED`, sebuah preset yang menyetel atribut control akan **mengalahkan** nilai yang diketik
desainer di instance-nya, yaitu kebalikan persis dari aturan "paling spesifik menang". Gejalanya
cuma "kadang slider saya rentangnya salah", dan tidak akan ada yang menemukannya dengan membaca.

## 9. Apa yang terjadi kalau salah

**Kode melempar error, atribut memperingatkan.** Control dinyatakan di Studio oleh orang yang
tidak sedang melihat output window.

| Keadaan | Perilaku |
| --- | --- |
| Part wajib tidak ada | peringatkan **setelah subtree berhenti berubah**, bukan langsung. Layar yang belum tereplikasi akan selalu kehilangan Track pada frame pertama, dan peringatan yang selalu muncul dan selalu salah adalah peringatan yang semua orang belajar abaikan. |
| Part opsional tidak ada | diam. |
| Part tidak bisa menulis properti yang dia sebut | peringatkan, sebutkan instance, kelas, dan properti. Ini pemeriksaan yang akhirnya menolak sesuatu. |
| Nama control tidak dikenal | peringatkan, sebutkan daftar yang terdaftar. |
| Part hilang saat runtime | wajib: kembali diam dan peringatkan. Opsional: berhenti menggerakkannya. |
| Channel menerbitkan nilai di luar rentang | jepit untuk melukis, **jangan** jepit untuk `Get()`, dan peringatkan sekali. |
| Akar control berada di dalam subtree `UnrestIgnore` | akarnya tidak pernah diadopsi, jadi control-nya mati total. Ini **wajib** memperingatkan, karena kalau tidak, desainer memasang `UnrestIgnore` di pembungkus dekoratif dan slider-nya hilang tanpa jejak. |

Ditambah `Controls:Validate(screenGui)` yang mengembalikan laporan alih-alih peringatan, supaya
sebuah perombakan bisa diperiksa sebelum menekan Play.

## 10. Kepemilikan lukisan, penolakan, dan laju

Bagian ini tidak ada di v1. Tiga hal di bawah inilah yang menentukan apakah proposal ini
berhasil, dan v1 memberi ketiganya kurang dari satu paragraf.

### 10.1 Sesi geser tidak boleh dibangun di atas `Press` dan `Release`

`Press` dan `Release` terikat ke `InputBegan` dan `InputEnded` milik GuiObject.
**`GuiObject.InputEnded` hanya menyala kalau penunjuk masih di atas instance itu.** Menggeser
berarti penunjuk keluar dalam dua puluh piksel pertama, jadi `Release` tidak akan pernah
menyala dan control-nya nyangkut dalam keadaan "sedang digeser" selamanya.

Artinya `Slider` **tidak bisa dibangun di atas pasangan handler itu**, padahal v1 menjanjikannya
di dua tempat. Kontrak part `Track` bukan `Press`, melainkan `Press` **ditambah sesi geser yang
dimiliki control**, dan sesi itu adalah satu-satunya tempat framework boleh menyentuh
`UserInputService`. Klaim v1 bahwa "tidak ada pengetahuan per kelas yang baru" tidak bertahan,
dan lebih baik diakui sekarang.

Sesi gesernya hidup hanya selama jari menempel, jadi biayanya nol saat diam. Dua jebakan
koordinat harus ditulis di komentar sejak awal, bukan ditemukan belakangan: `GetMouseLocation`
sudah mengurangi GUI inset sedangkan `input.Position` tidak, dan `AbsoluteSize` bernilai nol
sebelum render pertama.

### 10.2 Siapa yang memiliki lukisan

`Music.Volume` adalah channel `Public` yang retained. Setiap kiriman kembali sebagai publish,
jadi selama menggeser control menerima nilainya sendiri dari seratus milidetik lalu dan mengecat
ulang ke situ. Hasilnya knob yang bergetar mundur di bawah jari.

Aturan yang hilang: **dari `Press` sampai `Release` ditambah satu round-trip, nilai lokal yang
memiliki lukisan.** Publish channel diabaikan selama jendela itu, lalu dijepretkan saat keluar.
Tanpa aturan ini, jawaban apa pun untuk pertanyaan laju menghasilkan slider yang bergetar.

### 10.3 Penolakan itu diam, dan diamnya mahal

`Bridge:Dispatch` tidak mengembalikan apa pun, dan penolakan berhenti di server. Jadi geseran
yang ditolak berarti handler tidak jalan, channel tidak menerbitkan ulang, dan lukisan optimistis
**tidak pernah dikoreksi**. Slider menampilkan nilai yang tidak pernah berlaku, tanpa satu pun
sinyal.

Aturan yang hilang: setelah dilepas, kalau tidak ada publish yang mengonfirmasi dalam beberapa
detik, jepretkan ke `Bridge:Peek(channel)`.

Dan ada gigi tambahan yang mengubah status pembatasan laju dari optimasi jadi keselamatan:
setiap penolakan menambah penghitung penyalahgunaan pemain, dan pada ambangnya pemain dilaporkan
ke hook moderasi. **Throttle yang meleset sedikit mengubah setiap pemain yang menggeser slider
jadi tersangka.**

### 10.4 Laju kirim

Control membaca `RateLimit` dari kontrak perintahnya sendiri. Jalur bacanya sudah publik dan
sudah diketik hari ini, dan `Music.SetVolume` memang menyatakan delapan panggilan per detik.

Tiga hal yang v1 lewatkan dan wajib ikut:

- `RateLimit` itu opsional. Ketika absen, server memakai bawaan di `Constants.Limits`, dan
  control harus memakai bawaan yang sama, bukan menebak.
- Ada **anggaran global per pemain** di seluruh perintah, di atas batas per perintah. Dua slider
  yang digeser bersamaan ditambah tombol yang ditekan bersaing di ember yang sama. Perlu ember
  kirim bersama di sisi client, bukan throttle per control yang saling buta.
- Kiriman final saat dilepas bisa jadi kiriman yang ditolak, padahal itu yang paling penting.
  Throttle-nya harus **menyisakan satu slot** untuk pelepasan.

## 11. API dari sisi kode

```luau
local volume = unrest:Control("VolumeDial")

volume:Get()
volume:Set(0.4)
volume.Changed:Connect(fn)   -- hanya perubahan pengguna, bukan gema channel
volume:Parts()
```

Satu control tidak bisa menggerakkan dua channel. Master volume yang menyetel musik dan efek
sekaligus memakai `Changed` dan dua `Dispatch`, sekitar empat baris. Itu jalan keluar yang
layak, dan disebut di sini supaya tidak dianggap kegagalan.

## 12. Bagaimana dia menyatu dengan yang sudah ada

- **Tag** tidak berubah.
- **Adapter** dipakai ulang untuk memeriksa `CanBind` dan untuk menulis ke part.
- **Akar control tetap diadopsi** sebagai elemen, supaya `Query`, `Role`, `Group`, dan
  `UnrestIgnore` terus bekerja. Tapi `wireCommand` dan `wireChannel` **mundur** ketika
  `UnrestControl` ada. Tanpa aturan ini, akar control hari ini memuntahkan dua peringatan palsu
  di setiap rewire, dan akar berbentuk `TextButton` benar-benar mengirim perintah berpayload nil
  setiap diklik. Satu `if`, dan ini bukan pertanyaan terbuka lagi.
- **Preset: rekomendasi v1 dibalik.** v1 menyebut atribut control sebagai tempat preset paling
  terbayar. Itu salah. `UnrestPreset` adalah salah satu dari tiga atribut yang diwariskan, dan
  ekspansinya per elemen, jadi preset di akar control bocor turun ke Track, Fill, Knob, dan
  Value. Knob yang berupa tombol lalu mendapat `UnrestCommand` dan mengirim perintah cacat tiap
  diklik. Preset control **tidak boleh** dipakai lewat pewarisan, atau `UnrestControl` harus
  memutus rantai pewarisan `UnrestPreset` untuk subtree-nya.
- **Bridge dan kontrak** tidak berubah. Control tidak memberi hak istimewa apa pun.
- **Query** tidak berubah dan tetap jadi jalan keluar.

## 13. Tahapan

| Tahap | Yang dihasilkan |
| --- | --- |
| 1 | Registry, resolusi part, sesi geser, kepemilikan lukisan, rekonsiliasi penolakan, dan `Slider` |
| 2 | `unrest:Control()`, `Controls:Validate()`, tombol lint di plugin |
| 3 | Control kedua, dipilih setelah tahu mana yang benar-benar dibutuhkan |

Hanya Tahap 1 yang layak dikomitmenkan. Dan Tahap 1 harus dibangun melawan bagian 10, bukan
melawan resolusi part: resolusi part akan bekerja di percobaan pertama, tiga hal di bagian 10
tidak.

**Tahap 1 tidak aditif.** Ini harus disadari sebelum mulai. Dia memaksa mengubah apa yang
diterima handler `Press`, membuat `wireCommand` dan `wireChannel` sadar-control, dan memperlebar
`WATCHED`. Ketiganya menyentuh invariant yang dinyatakan mutlak di dokumen lain. Kecil dalam
baris, mahal dalam telaah.

Taksiran kasar: seribu sampai seribu lima ratus baris baru, sekitar seratus tiga puluh baris
suntingan di file yang paling load-bearing.

## 14. Yang tidak diselesaikan

- **Tata letak dan gaya tetap urusanmu.**
- **Satu part tidak bisa dimiliki dua control.** Sebuah `ProgressBar` posisi lagu dan sebuah
  `Slider` seek yang berbagi satu track harus jadi dua instance bertumpuk. Perbaikannya ada,
  `UnrestPart` sebagai string berpembatas, tapi belum dibayar.
- **Perombakan ke bentuk diskrit tidak butuh Controls**, seperti ditulis di bagian 2. Itu bukan
  kegagalan, itu batas yang benar.
- **Animasi di luar cakupan** Tahap 1.
- **Dia menambah satu konsep**, subtree bernama dengan part. v1 menambah dua. Kalau `Slider`
  tidak jelas terbayar, langkah yang jujur adalah membatalkan idenya.

## 15. Pertanyaan terbuka

Yang di v1 sudah terjawab dan dipindahkan ke badan dokumen. Sisanya:

1. **Kepemilikan lukisan, berapa lama jendelanya?** Satu round-trip itu berapa, dan apa yang
   terjadi kalau round-trip-nya tidak pernah datang. Ini yang paling menentukan dari semuanya.
2. **`UnrestValue` sebagai string berpembatas**, atau dua atribut terpisah? Atribut Roblox cuma
   primitif, jadi `"0,100"` adalah kompromi. Dua atribut lebih jelas tapi dua kali kerja
   mengetiknya.
3. **Sesi geser: satu ember kirim bersama untuk seluruh client**, atau per control dengan margin
   besar? Ember bersama lebih benar dan lebih rumit.
4. **Apakah `Toggle` tetap layak dibangun belakangan**, mengingat hari ini sudah bisa dinyatakan
   tanpa Controls sama sekali?

## 16. Status

Proposal v2. Belum ada kode yang ditulis dan belum boleh ditulis sampai diperintahkan.
