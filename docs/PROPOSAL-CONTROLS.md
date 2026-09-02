# Proposal — Controls

**Status: baru proposal. Belum ada yang diimplementasikan. Jangan dibangun sebelum diperintahkan.**

## 1. Masalahnya

> "Tujuan gua bikin framework itu adalah ketika gua desain UI, padahal core system-nya sama
> aja. Jadi gua butuh satu hal yang mudah ketika gua nge-switch UI. Semisal gua bikin slider,
> ketika gua rombak UI-nya itu bakal berubah lagi implementasinya. Jadi gua butuh High API
> untuk ini."

Framework ini sudah menjaga agar perombakan UI tidak menyentuh *core*. Sistem menerbitkan
channel dan menangani perintah, dan mereka tidak pernah tahu rupa sebuah tombol. Yang belum
terlindungi adalah lapisan di antaranya.

Slider itu bukan satu elemen. Dia adalah sebuah Frame yang menentukan sumbu, sebuah knob yang
digeser, sebuah fill yang mengikuti, dan sebuah label yang melaporkan. Empat instance yang baru
berarti "slider" kalau ada yang tahu hubungan di antara mereka.

Hari ini pengetahuan itu harus tinggal di dalam skrip, ditulis untuk satu susunan pohon
tertentu:

```luau
local track = panel.Volume.Track
local knob = track.Knob
knob.InputBegan:Connect(function(input) ... end)
-- dan belasan baris lagi yang menghitung pecahan dari AbsolutePosition
```

Rombak desainnya, knob dipindah ke dalam fill, track diputar, label digeser ke sudut, dan
setiap baris di atas jadi salah. Core-nya selamat dari perombakan; lemnya tidak.

## 2. Kenapa yang sudah ada belum cukup

| Bagian | Yang ditangani | Kenapa belum cukup |
| --- | --- | --- |
| Tag dan adapter | satu instance, event-nya, properti yang boleh ditulis | slider itu empat instance yang harus saling berhubungan |
| `UnrestCommand` / `UnrestChannel` | satu elemen ke satu perintah atau channel | tidak bisa menyatakan "geser yang ini, diukur terhadap yang itu" |
| `Unrest:Query` | *menemukan* instance tanpa jalur yang dipaku | perilakunya tetap lu tulis sendiri, per layar |
| Preset | memampatkan atribut yang berulang | dia bundel atribut, bukan perilaku |

`Query` sudah menyelesaikan separuh masalah: dia menemukan sesuatu lewat peran, bukan lewat
jalur. Yang belum ada adalah **perilakunya ditulis sekali oleh framework, bukan sekali per
layar.** Itulah High API yang lu minta.

## 3. Uji penerimaan

Semua di bawah ini dinilai terhadap satu skenario:

> Bangun `MenuV1` di Studio dengan sebuah slider. Rilis. Belakangan bangun `MenuV2` dari nol,
> tata letak berbeda, kelas berbeda, slider vertikal menggantikan yang horizontal. Hapus
> `MenuV1`, pasang `MenuV2`, tekan Play.
>
> **Nol baris Luau berubah. Tidak ada sistem, bootstrap, atau kontrak yang disentuh.**

Kalau sebuah rancangan tidak bisa lolos itu, rancangannya salah.

## 4. Modelnya

Tiga gagasan, dari yang paling besar.

**Control adalah perilaku bernama di atas sebuah subtree.** `UnrestControl = "Slider"` pada
sebuah Frame berarti "framework yang memiliki perilaku subtree ini, dan perilakunya adalah
slider". Framework yang menyediakan penggeserannya, hitungannya, pelukisannya, dan
pengirimannya.

**Part adalah instance yang memainkan peran bernama di dalam subtree itu.** Control menemukan
part-nya lewat peran, tidak pernah lewat jalur. Pindahkan part-nya, ganti nama instance-nya,
tanam tiga tingkat lebih dalam, selama perannya masih dinyatakan, control tetap menemukannya.

**Part diwajibkan punya kemampuan, bukan kelas.** Knob harus bisa melaporkan tekan dan lepas.
Itu pertanyaan yang sudah bisa dijawab adapter registry lewat `Supports`, untuk setiap kelas
yang dia kenal. Jadi knob boleh `TextButton`, boleh `ImageButton`, boleh apa saja yang
adapter-nya menyatakan `Press`. Fill butuh `Size` yang boleh ditulis, dan itu `CanBind`.
Control menyatakan apa yang dia butuhkan, lalu model kemampuan yang sudah ada yang memutuskan
kelas mana yang memenuhi.

Gagasan ketiga inilah yang membuat perombakan aman. Control yang menuntut `ImageButton` akan
patah begitu desainer lebih suka `TextButton`.

## 5. Permukaan atribut

Di akar control:

| Atribut | Artinya |
| --- | --- |
| `UnrestControl` | nama control-nya, misal `"Slider"`. Menandai subtree-nya. |
| `UnrestChannel` | channel tempat control membaca nilainya. Retained, jadi lukisannya benar sejak frame pertama. |
| `UnrestCommand` | perintah yang dikirim ketika pengguna mengubah nilainya. |
| `UnrestMin` / `UnrestMax` | rentang nilai. Bawaannya `0` dan `1`. |
| `UnrestStep` | kelipatan. Bawaannya `0`, artinya kontinu. |
| `UnrestFormat` | format untuk part `Value`, misal `"{value}%"`. |

Di setiap part, satu atribut:

| Atribut | Artinya |
| --- | --- |
| `UnrestPart` | peran yang dimainkan instance ini di dalam control-nya, misal `"Track"`. |

`UnrestPart` sengaja **bukan** `UnrestRole`. Role itu identitas di seluruh DataModel dan itulah
yang diseleksi `Query`; part itu posisi di dalam satu control. Menumpangkan dua makna pada satu
atribut akan membuat knob bernama `Knob` di dua slider berbeda saling bertabrakan di sebuah
query, dan membuat resolusi control bergantung pada keunikan global yang tidak bisa dia jamin.

## 6. Contoh nyata

### V1, horizontal

```
Volume (Frame)          UnrestControl = "Slider"
                        UnrestChannel = "Music.Volume"
                        UnrestCommand = "Music.SetVolume"
                        UnrestFormat  = "Volume {value}%"
  Track (Frame)         UnrestPart = "Track"
    Fill (Frame)        UnrestPart = "Fill"
    Knob (ImageButton)  UnrestPart = "Knob"
  Readout (TextLabel)   UnrestPart = "Value"
```

Satu tag di sebuah ancestor, empat atribut `UnrestPart`, empat atribut control. Tanpa kode.

### V2, hasil perombakan

Vertikal. Knob-nya sekarang `TextButton`. Fill-nya `CanvasGroup`. Readout-nya pindah ke dalam
track. Nama instance-nya diganti menyesuaikan desain baru.

```
VolumeDial (Frame)      UnrestControl = "Slider"
                        UnrestChannel = "Music.Volume"
                        UnrestCommand = "Music.SetVolume"
                        UnrestFormat  = "Volume {value}%"
  Column (Frame)        UnrestPart = "Track"
    Level (CanvasGroup) UnrestPart = "Fill"
    Grip (TextButton)   UnrestPart = "Knob"
    Number (TextLabel)  UnrestPart = "Value"
```

Kelas berbeda, nama berbeda, pohon berbeda, sumbu berbeda. **Keempat atribut control-nya sama
persis dan tidak ada Luau yang berubah.** Itulah seluruh isi proposal ini dalam satu diff.

Orientasi disimpulkan dari `AbsoluteSize` milik Track, lebih tinggi daripada lebar berarti
vertikal, dengan `UnrestOrientation` tersedia untuk track yang persegi, di mana penyimpulan
jadi untung-untungan.

## 7. Katalog bawaan

Masing-masing datang dengan kontrak part. `wajib` berarti control menolak jalan tanpanya.

| Control | Part | Kemampuan yang dibutuhkan tiap part |
| --- | --- | --- |
| `Slider` | Track `wajib`, Knob, Fill, Value | Track: GuiObject apa pun. Knob: `Press`. Fill: `Size` yang boleh ditulis. Value: properti teks yang boleh ditulis. |
| `Toggle` | Button `wajib`, On, Off, Value | Button: `Active`. On/Off: `Visible` yang boleh ditulis. |
| `Stepper` | Increment `wajib`, Decrement `wajib`, Value | tombol: `Active`. Value: teks yang boleh ditulis. |
| `ProgressBar` | Track `wajib`, Fill `wajib`, Value | seperti Slider, tanpa bagian input. |
| `TabGroup` | Tab `wajib` (banyak), Panel (banyak, dipasangkan lewat kunci) | Tab: `Active`. Panel: `Visible` yang boleh ditulis. |

`ProgressBar` itu `Slider` tanpa input, dan mengirim keduanya membuat pembedaannya eksplisit,
bukan bergantung pada apakah lu ingat memasang knob atau tidak.

## 8. Resolusi dan keaktifan

Resolusi part mengikuti aturan yang sudah dua kali ditegakkan di codebase ini: **satu
definisi, dipakai semua pihak yang butuh jawabannya.** `Selector.ancestorChain` adalah
presedennya. `Elements` meresolusi dengan itu dan `Query` mengawasi rantai yang dikembalikannya,
sehingga keduanya tidak mungkin berbeda pendapat.

- Control meresolusi part dengan memindai subtree-nya sendiri untuk `UnrestPart`, terdekat
  lebih dulu.
- Subtree milik control bersarang dikecualikan dari pemindaian induknya. Slider di dalam panel
  tab adalah milik slider itu.
- Dua instance yang mengaku part yang sama adalah peringatan, dan yang terdekat menang. Memilih
  salah satu diam-diam adalah cara sebuah perombakan patah seminggu kemudian.
- Part diawasi secara langsung. Part yang ditambah, dihapus, diganti nama, atau dipindah induk
  akan meresolusi ulang control-nya, karena justru itu yang terjadi saat orang sedang mendesain
  dengan game berjalan.

## 9. Apa yang terjadi kalau salah

Konvensi yang sudah dipakai codebase ini adalah **kode melempar error, atribut memperingatkan**,
dan itu berlaku di sini tanpa perubahan. Control dinyatakan di Studio oleh orang yang tidak
sedang melihat output window, jadi control yang rusak tidak boleh menjatuhkan layar.

| Keadaan | Perilaku |
| --- | --- |
| Part wajib tidak ada | peringatkan sekali, sebutkan control-nya, part yang hilang, dan subtree-nya. Control diam. |
| Part opsional tidak ada | diam saja. Slider tanpa label Value ya slider tanpa label. |
| Part tidak mampu melakukan yang dibutuhkan | peringatkan, sebutkan instance-nya, kelasnya, dan kelas mana yang memenuhi. Memakai ulang `Describe` milik adapter registry. |
| Nama control tidak dikenal | peringatkan, sebutkan daftar control yang terdaftar. |
| Part hilang saat runtime | wajib: kembali diam dan peringatkan. Opsional: berhenti menggerakkannya. |

Ditambah sebuah validator, `Controls:Validate(screenGui)`, yang mengembalikan laporan alih-alih
peringatan. Jadi sebuah perombakan bisa diperiksa sebelum menekan Play, dan nanti bisa
disambungkan ke tombol di plugin Studio.

## 10. Pembatasan laju, dan kenapa kontraknya sudah tahu jawabannya

Slider yang digeser menghasilkan input tiap frame. Mengirim semuanya akan menghabiskan jatah
rate limit pemain dalam waktu jauh di bawah satu detik, dan server mulai menolak. Framework
berkelahi dengan lapisan keamanannya sendiri.

Perbaikannya sudah ada di codebase. `Music.SetVolume` menyatakan `RateLimit = { Count = 8,
Window = 1 }` di `Net/Contracts.luau`. Sebuah control bisa **membaca kontrak perintahnya
sendiri** lalu menyesuaikan lajunya ke situ, bukan menyimpan angka ajaib yang lama-lama
melenceng dari server.

Bentuk yang diusulkan:

- lukis lokal dengan laju penuh, supaya penggeserannya terasa langsung;
- kirim mengikuti laju kontrak, dikurangi margin;
- selalu kirim satu nilai final saat dilepas, supaya keadaan otoritatif sama dengan yang
  ditinggalkan pemain.

Ini layak ditegaskan: artinya perilaku jaringan sebuah control diturunkan dari deklarasi yang
sama dengan yang ditegakkan server, dan keduanya tidak mungkin melenceng.

## 11. API dari sisi kode

Control bersifat deklaratif lebih dulu, tapi kode harus tetap bisa menjangkau satu control
tanpa tahu rupanya.

```luau
local volume = unrest:Control("VolumeDial")   -- lewat UnrestRole akarnya, atau namanya

volume:Get()                 -- nilai saat ini
volume:Set(0.4)              -- lukis dan kirim, seolah pemain yang melakukannya
volume.Changed:Connect(fn)   -- menyala saat perubahan dari pengguna, bukan gema channel
volume:Parts()               -- part yang teresolusi, untuk kasus langka yang membutuhkannya
```

`Changed` yang hanya menyala pada perubahan pengguna itu penting. Control yang menyala oleh
gema channel-nya sendiri akan berputar begitu ada yang berlangganan lalu menerbitkan ulang.

Mendaftarkan control buatan sendiri mencerminkan `Adapters:Register`:

```luau
unrest.Controls:Register({
    Name = "RadialDial",
    Parts = {
        Ring = { Required = true },
        Needle = { Required = true, Needs = "Press" },
        Value = { Bindable = "Text" },
    },
    Attach = function(control) ... end,   -- mengembalikan fungsi pembongkarnya
})
```

Control buatan sendiri harus semurah control bawaan untuk ditulis. Kalau tidak, setiap desain
yang tidak masuk katalog akan jatuh kembali ke lem tulisan tangan, dan proposal ini gagal.

## 12. Bagaimana dia menyatu dengan yang sudah ada

- **Tag** tidak berubah. Akar control harus berada di dalam subtree yang terkelola, dan tag
  berjenjang sudah mencakup semua di bawahnya.
- **Adapter** dipakai ulang untuk memeriksa kemampuan dan untuk menggerakkan part. Tidak ada
  pengetahuan per kelas yang baru.
- **Atribut dan pewarisan**: `UnrestControl` itu niat per elemen, jadi dia **tidak** diwariskan.
  `UnrestFormat` di akar control berlaku untuk part Value, dan penumpangan makna kecil itu
  perlu disebut terang-terangan.
- **Preset**: sebuah preset boleh menyatakan atribut control, sehingga
  `UnrestPreset = "VolumeSlider"` bisa membawa channel, perintah, rentang, dan format sekaligus.
  Di sinilah preset paling terbayar.
- **Bridge dan kontrak** tidak berubah. Control mengirim perintah yang sama lewat gerbang yang
  sama. **Control tidak memberi hak istimewa apa pun**, persis seperti atribut.
- **Query** tidak berubah dan tetap jadi jalan keluar untuk perilaku yang tidak bisa dinyatakan
  control mana pun.

## 13. Tahapan implementasi

| Tahap | Yang dihasilkan | Yang dibuktikan |
| --- | --- | --- |
| 1 | Registry control, resolusi part, keaktifan, perilaku saat salah, dan `Slider` | modelnya bekerja pada kasus umum tersulit |
| 2 | `Toggle`, `Stepper`, `ProgressBar` | mesinnya menyamaratakan dan control baru jadi murah |
| 3 | `unrest:Control()`, `Controls:Validate()`, tombol lint di plugin | alur kerja perombakan, bukan cuma runtime-nya |
| 4 | `TabGroup`, panduan menulis control sendiri | keterluasan di luar katalog |

Hanya Tahap 1 yang layak dikomitmenkan sekarang. Kalau slider-nya tidak selamat dari perombakan
sungguhan, tahap 2 sampai 4 dibangun di atas pasir.

## 14. Yang tidak diselesaikan proposal ini

Jujur soal batasnya, supaya proposal ini tidak dijual berlebihan:

- **Tata letak dan gaya tetap urusan lu.** Control menggerakkan perilaku; dia tidak pernah
  menyetel warna, radius sudut, atau posisi yang bukan bagian dari nilai yang dia wakili.
- **Desain yang tidak punya padanan part tidak tercakup.** Slider yang nilainya dinyatakan
  sebagai rona warna alih-alih panjang tidak punya `Fill`, dan butuh control buatan sendiri.
  Katalognya itu lantai, bukan langit-langit.
- **Animasi di luar cakupan** Tahap 1. Control menyetel nilai; menghaluskannya adalah urusan
  terpisah, dan menyatukannya terlalu dini akan mengikat dua hal yang berubah dengan laju
  berbeda.
- **Dia menambah konsep.** Tag, atribut, preset, dan sekarang control dan part. Taruhannya,
  satu control menghapus lebih banyak lem daripada biaya konsepnya. Kalau slider-nya tidak
  jelas terbayar, langkah yang jujur adalah membatalkan idenya, bukan mengirim empat control
  sisanya.

## 15. Pertanyaan terbuka

Ini mengubah rancangannya, dan keputusannya di lu:

1. **`UnrestPart` sebagai atribut terpisah, atau menumpang `UnrestRole` yang dibatasi ke
   subtree?** Proposal ini memilih terpisah. Menumpang berarti satu konsep lebih sedikit, tapi
   mengikat resolusi control pada keunikan role secara global.
2. **Apakah akar control juga boleh diadopsi sebagai elemen biasa?** Kalau boleh, `UnrestCommand`
   dan `UnrestControl` bisa duduk di satu instance dengan urutan menang yang tidak jelas.
3. **Orientasi disimpulkan dari track, atau selalu dinyatakan?** Penyimpulan membuat perombakan
   jalan tanpa disentuh; penyataan tidak pernah mengejutkan.
4. **Pengiriman dibatasi lajunya selama digeser, atau hanya saat dilepas?** Dibatasi lebih
   responsif untuk keadaan bersama; hanya saat dilepas lebih murah dan tidak pernah separuh
   diterapkan.
5. **Apakah `Slider` control pertama yang tepat**, atau `Toggle` lebih murah untuk membuktikan
   modelnya?

## 16. Status

Proposal. Belum ada kode yang ditulis dan belum boleh ditulis sampai lu bilang.
