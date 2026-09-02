# Kosakata Handler

Handler adalah dua belas kata kerja yang sama, apa pun kelas di bawahnya. Sepuluh di antaranya
adalah event yang dideklarasikan sebuah adapter; dua sisanya menggambarkan **query**-nya,
bukan elemennya.

Setiap handler dipanggil sebagai `(element, value)`, dan `value` bernilai `nil` untuk semua
kecuali dua — jadi `function(element) end` adalah bentuk yang normal.

---

## 1. Dari mana setiap handler berasal

Adapter menumpuk mengikuti hierarki kelas, jadi handler yang dideklarasikan di `GuiObject`
milik **setiap** `GuiObject`, dan yang dideklarasikan di `GuiButton` milik kedua kelas tombol.

Handler yang muncul di lebih dari satu baris adalah **event Roblox yang berbeda per keluarga
kelas**, sengaja diberi satu nama supaya satu query bisa memilih "semua yang bisa diaktifkan
di ruangan ini".

| Handler | Dideklarasikan di | Event Roblox | Menjangkau | `value` |
| --- | --- | --- | --- | --- |
| `Active` | `GuiButton` | `Activated` | `TextButton`, `ImageButton` | nil |
| `Active` | `ClickDetector` | `MouseClick` | `ClickDetector` | nil — Player-nya dibuang |
| `Active` | `ProximityPrompt` | `Triggered` | `ProximityPrompt` | nil — Player-nya dibuang |
| `Secondary` | `GuiButton` | `MouseButton2Click` | `TextButton`, `ImageButton` | nil |
| `Secondary` | `ClickDetector` | `RightMouseClick` | `ClickDetector` | nil |
| `Press` | `GuiObject` | `InputBegan`, disaring ke MouseButton1 / Touch | setiap `GuiObject` | nil |
| `Press` | `ProximityPrompt` | `PromptButtonHoldBegan` | `ProximityPrompt` | nil |
| `Release` | `GuiObject` | `InputEnded`, saringan yang sama | setiap `GuiObject` | nil |
| `Release` | `ProximityPrompt` | `PromptButtonHoldEnded` | `ProximityPrompt` | nil |
| `Hover` | `GuiObject` | `MouseEnter` | setiap `GuiObject` | nil |
| `Hover` | `ClickDetector` | `MouseHoverEnter` | `ClickDetector` | nil — Player-nya dibuang |
| `Hover` | `ProximityPrompt` | `PromptShown` | `ProximityPrompt` | nil — jenis input dibuang |
| `Unhover` | `GuiObject` | `MouseLeave` | setiap `GuiObject` | nil |
| `Unhover` | `ClickDetector` | `MouseHoverLeave` | `ClickDetector` | nil |
| `Unhover` | `ProximityPrompt` | `PromptHidden` | `ProximityPrompt` | nil |
| `Focus` | `TextBox` | `Focused` | `TextBox` saja | nil |
| `Blur` | `TextBox` | `FocusLost` | `TextBox` saja | nil |
| `Submit` | `TextBox` | `FocusLost` **dengan Enter ditekan** | `TextBox` saja | `Text` yang dikomit, sebuah string |
| `Changed` | *disintesis dari `ValueProperty`* | `GetPropertyChangedSignal(ValueProperty)` | setiap kelas yang punya `ValueProperty` | nilai properti itu sekarang |
| `Added` | *siklus hidup query* | — | setiap instance, punya adapter atau tidak | nil |
| `Removed` | *siklus hidup query* | — | setiap instance, punya adapter atau tidak | nil |

**Argumen yang dibawa event Roblox tidak diteruskan** kecuali tabel di atas menyebutnya.
`ClickDetector.MouseClick` menerima sebuah `Player` dan `ProximityPrompt.PromptShown`
menerima sebuah jenis input; adapter membuang keduanya, karena adopsi hanya terjadi di client
dan jawabannya akan selalu pemain yang sama.

---

## 2. Tabel yang sama, dilihat per kelas

`Added` dan `Removed` dihilangkan karena setiap baris punya keduanya — termasuk `Folder` atau
`Part` yang tidak punya adapter sama sekali. Itulah sebabnya query yang cuma membawa dua
handler itu bisa memilih apa saja.

| Kelas | Handler |
| --- | --- |
| `Frame`, `ViewportFrame` | `Hover`, `Unhover`, `Press`, `Release` |
| `TextLabel`, `ImageLabel`, `ScrollingFrame`, `CanvasGroup`, `VideoFrame` | keempat itu, ditambah `Changed` |
| `TextButton`, `ImageButton` | keempat itu, ditambah `Active`, `Secondary`, `Changed` |
| `TextBox` | keempat itu, ditambah `Focus`, `Blur`, `Submit`, `Changed` |
| `ScreenGui`, `SurfaceGui`, `BillboardGui` | `Changed` *(Enabled)* saja — `LayerCollector` bukan `GuiObject` |
| `UICorner`, `UIScale` | `Changed` saja |
| setiap `UI*` lainnya | tidak ada |
| `ClickDetector` | `Active`, `Secondary`, `Hover`, `Unhover` — **tanpa** `Press`/`Release`, **tanpa** `Changed` |
| `ProximityPrompt` | `Active`, `Hover`, `Unhover`, `Press`, `Release` — **tanpa** `Secondary`, **tanpa** `Changed` |

---

## 3. Kode melempar error; atribut cuma memperingatkan

Mengikat handler yang tidak didukung sebuah elemen tidak pernah gagal diam-diam. Tapi
tingkat keparahannya tergantung siapa yang meminta.

* **Kode melempar error.** `Unrest:Query(…, { Submit = … })` terhadap sebuah `Frame`
  **throw**. Kode yang mengikat handler yang tidak didukung elemennya adalah bug, dan dia
  harus berhenti di baris yang menulisnya — bukan berubah jadi tombol yang diam-diam tidak
  pernah bekerja.
* **Atribut memberi peringatan.** Kesalahan yang sama yang dibuat di Studio —
  `UnrestCommand` pada sebuah `TextLabel` — memberi peringatan, menyebutkan elemennya,
  menyebutkan perbaikannya, dan membiarkan sisa layarnya tetap berdiri. Atribut adalah data,
  biasanya diketik oleh orang yang tidak sedang melihat jendela Output, dan menjatuhkan
  seluruh menu karena satu atribut adalah hasil yang lebih buruk.

Perhatikan di sisi mana kamu berdiri: **persis satu handler yang bisa diminta lewat atribut.**
`UnrestCommand` menyambungkan `Active`, dan tidak ada `UnrestHover` atau `UnrestSubmit`. Jadi
jalur peringatan itu hanya pernah menyangkut `UnrestCommand` pada kelas yang tidak bisa
diaktifkan; setiap nama lain di halaman ini hanya bisa dari kode, dan karena itu selalu
melempar error.

---

## 4. Tiga jebakan yang melintasi seluruh tabel

Baca tiga ini sebelum catatan per-handler. Ketiganya berlaku di mana-mana.

### 4.1 Setiap pasangan masuk/keluar bisa kehilangan bagian keluarnya

`Press`/`Release`, `Hover`/`Unhover`, dan `Focus`/`Blur` terlihat simetris, dan **tidak satu
pun dijamin simetris**.

Kasus terburuknya `Press`/`Release` pada sebuah `GuiObject`. **`InputEnded` hanya menyala
selama penunjuk masih berada di atas instance itu.** Tekan tombol, seret keluar dari
tombolnya, lalu lepas — `Press` menyala dan `Release` tidak akan pernah menyala.

Empat penyebab, satu bentuk kegagalan yang sama:

| Penyebab | Yang hilang |
| --- | --- |
| penunjuk meninggalkan elemen saat masih ditekan | `Release` |
| sebuah channel menulis `Visible = false` pada elemen yang sedang di-hover atau ditekan | `Unhover`, `Release` |
| elemennya dilepas di tengah gestur — tagnya dicabut, `UnrestIgnore` dicentang, dipindah keluar | semua handler sekaligus; koneksinya dibongkar di tempat |
| elemennya di-`Destroy()` di tengah gestur | sama |

Adapter **tidak akan** memperbaiki ini untukmu, dan itu disengaja: menambalnya berarti
menyambungkan `UserInputService` atas nama elemennya, dan pendengar input global bukan sesuatu
yang boleh dibeli diam-diam oleh sebuah tag.

> **Jangan pernah menyimpan "sedang ditekan" atau "sedang di-hover" sebagai state yang harus
> dibersihkan event berikutnya.** Gerakkan visualnya dari event masuknya saja, atau reset di
> `Removed` — dan `Removed` adalah satu-satunya kepergian yang dijamin framework, persis
> sekali, untuk setiap penyebab di tabel itu.

### 4.2 `Changed` disintesis, tidak pernah ditulis tangan

`Changed` tidak ditulis tangan di adapter mana pun. Registry **membuatnya** dari
`ValueProperty` milik adapter, jadi sebuah kelas punya `Changed` persis ketika dia punya satu
nilai yang jelas.

| Punya `ValueProperty`, jadi punya `Changed` | Propertinya |
| --- | --- |
| `TextLabel`, `TextButton`, `TextBox` | `Text` |
| `ImageLabel`, `ImageButton` | `Image` |
| `ScrollingFrame` | `CanvasPosition` |
| `CanvasGroup` | `GroupTransparency` |
| `VideoFrame` | `Video` |
| `LayerCollector` — jadi `ScreenGui`, `SurfaceGui`, `BillboardGui` | `Enabled` |
| `UICorner` | `CornerRadius` |
| `UIScale` | `Scale` |

Selebihnya menolak `Changed` dengan berisik, dan penolakannya justru bagian yang disengaja:
`Frame` dan `ViewportFrame` tidak punya satu nilai, `UIListLayout` punya sembilan dan memilih
salah satunya cuma lemparan koin yang menyamar jadi event, dan `ClickDetector` /
`ProximityPrompt` tidak punya sama sekali.

`ValueProperty` rata mengikuti rantai `Extends` seperti yang lain dan **tidak bisa
dibatalkan** — itu sebabnya `ScreenGui` melaporkan `Enabled` tanpa menyebutnya sendiri.

Tiga hal lagi tentang nilai yang dilaporkannya:

* Itu nilai properti **sekarang**, dibaca ulang saat sinyalnya menyala, karena
  `GetPropertyChangedSignal` tidak membawa payload. Dua penulisan di frame yang sama bisa
  melaporkan nilai yang belakangan dua kali, dan tidak pernah ada nilai sebelumnya untuk
  dibandingkan.
* Dia juga menyala untuk penulisan **yang dilakukan framework sendiri**. `UnrestBind` bawaannya
  adalah properti yang persis diawasi `Changed`, jadi elemen yang sekaligus mengikuti channel
  dan menangani `Changed` akan mendengar pengecatan ulangnya sendiri — dan `Changed` yang
  mengirim dispatch kembali ke channel itu adalah lingkaran tak berujung.
* Pada `TextBox` dia menyala **per ketukan tombol**. Itulah yang dihindari `Submit`.

### 4.3 `Active` berarti dua hal yang tidak berhubungan

`Active` adalah **nama handler** pada `GuiButton`, dan sekaligus **nama properti bindable**
pada `GuiBase2d`.

```luau
adapters:Supports(label, "Active")   --> false — TextLabel tidak bisa diaktifkan
adapters:CanBind(label, "Active")    --> true  — tapi properti Active-nya boleh ditulis
```

Dua pertanyaan, satu string, jawaban berlawanan. Ini juga sebabnya pesan `Describe` bisa
mencantumkan `Active` di bawah *properti bindable* untuk elemen yang tidak mendukung *handler*
`Active` — terbaca seperti kontradiksi, padahal bukan.

Keduanya juga saling memengaruhi. `Activated` tidak menyala selama properti `Active` bernilai
false, jadi channel yang terikat ke `Active` bisa **membungkam** handler `Active` — sementara
`Press` dan `Release` tetap menyala, karena keduanya `InputBegan`/`InputEnded` dan tidak
peduli pada properti itu. `Modal` pada tombol lain melakukan hal yang sama, dari instance yang
sama sekali berbeda.

---

## 5. Catatan per handler

### `Active`

Aktivasi utama — komitnya. `GuiButton.Activated`, `ClickDetector.MouseClick`,
`ProximityPrompt.Triggered`.

`Activated` dipilih daripada `MouseButton1Click` dengan sengaja: dia sudah melipat mouse,
sentuh, dan gamepad jadi satu event, dan sudah menghormati `Modal` dan properti `Active` —
yang juga jadi jebakannya, karena keduanya bisa membungkamnya tanpa memutus apa pun.

Ini **satu-satunya handler yang bisa diminta sebuah atribut** (lewat `UnrestCommand`), dan
karena itu satu-satunya yang kegagalannya berupa peringatan, bukan error.

### `Secondary`

Aktivasi sekunder: `GuiButton.MouseButton2Click`, `ClickDetector.RightMouseClick`.

**Khusus mouse**, di setiap kelas yang punya. Dia sekadar tidak pernah menyala di layar sentuh
atau gamepad — dan itu perilaku yang jujur, bukan celah. Jadi klik kanan **tidak boleh** jadi
satu-satunya jalan menuju sebuah aksi.

`ProximityPrompt` tidak punya tombol kedua sama sekali: mengikat `Secondary` padanya melempar
error.

### `Press`

Penunjuk turun. Pada `GuiObject` mana pun, `InputBegan` disaring ke MouseButton1 dan Touch —
input keyboard dan gamepad yang diarahkan ke elemen sengaja **tidak** dianggap tekanan. Pada
`ProximityPrompt`, `PromptButtonHoldBegan`.

Dua jebakan. `Press` menjangkau **setiap** `GuiObject`, termasuk `Frame` dan `TextLabel`,
karena dia dideklarasikan di `GuiObject` — jadi dia terikat dengan senang hati ke benda yang
tidak punya alasan untuk ditekan.

Dan pada sebuah prompt, event hold hanya ada kalau `HoldDuration > 0`. Dengan bawaan nol,
`Press` dan `Release` **tidak pernah menyala sekali pun**, sementara `Active` menyala normal.
`HoldDuration` bersifat bindable, jadi sebuah channel bisa mematikan pasangan ini dari server.

### `Release`

Penunjuk naik: `GuiObject.InputEnded` dengan saringan yang sama, atau
`ProximityPrompt.PromptButtonHoldEnded`. Lihat jebakan 4.1 — ini yang paling sering hilang.

### `Hover`

Penunjuk atau perhatian tiba. `GuiObject.MouseEnter`, `ClickDetector.MouseHoverEnter`,
`ProximityPrompt.PromptShown`.

**Ketiganya bukan event yang sama memakai satu nama.**

* `MouseEnter` khusus mouse, jadi tidak pernah menyala di perangkat sentuh. Afordansi yang
  hanya muncul saat hover **tidak terlihat sama sekali di HP**.
* `MouseHoverEnter` menyala untuk part 3D di bawah kursor, dan menyerahkan sebuah `Player`
  yang dibuang binder-nya.
* `PromptShown` sama sekali bukan event penunjuk. Dia menyala saat prompt-nya jadi terlihat —
  yaitu kedekatan dan garis pandang — dan menyala lagi setiap kali pemain berjalan masuk
  kembali ke jangkauan.

Jadi kalau kamu mau `Hover` berarti "sedang ditunjuk", itu benar untuk dua yang pertama dan
salah untuk yang ketiga.

### `Unhover`

Pasangannya: `GuiObject.MouseLeave`, `ClickDetector.MouseHoverLeave`,
`ProximityPrompt.PromptHidden`.

Tidak dijamin, dengan cara yang sama seperti `Release`. `MouseLeave` menyala saat penunjuknya
bergerak keluar; dia **tidak** menyala saat elemennya disembunyikan, dihancurkan, atau
dipindahkan dari bawah kursor yang diam. `Visible` bersifat bindable, jadi channel yang
menyembunyikan elemen yang sedang di-hover meninggalkan state hover-nya tetap menyala.

### `Focus`

Fokus keyboard didapat: `TextBox.Focused`. `TextBox` adalah satu-satunya kelas di framework
yang punya `Focus`/`Blur`/`Submit`, jadi mengikat salah satunya di tempat lain melempar error.

### `Blur`

Fokus keyboard hilang: `TextBox.FocusLost`, tanpa syarat.

**Setiap komit juga sebuah blur**, jadi menekan Enter menyalakan `Blur` **dan** `Submit` dari
dua koneksi terpisah ke sinyal yang sama. **Urutan relatif keduanya tidak terdefinisi** —
koneksinya dibuat sambil meng-iterasi tabel hash — jadi tidak satu pun boleh mengasumsikan
yang lain sudah berjalan.

Pakai `Blur` untuk "kotaknya tidak sedang disunting lagi" dan `Submit` untuk nilainya.

### `Submit`

Nilai yang dikomit: `TextBox.FocusLost` dengan `enterPressed` bernilai true. `value` adalah
`Text` milik `TextBox` pada saat itu, sebuah string.

Mengklik ke tempat lain **bukan** komit, dan menekan Escape juga bukan — keduanya menyalakan
`Blur` saja. Ini satu dari dua handler yang `value`-nya benar-benar berisi sesuatu.

### `Changed`

Lihat jebakan 4.2.

### `Added`

Elemennya mulai cocok dengan descriptor. Bukan event adapter: ini siklus hidup query-nya
sendiri, didukung setiap instance termasuk yang tidak punya adapter.

**Dia menyala untuk elemen yang sudah cocok saat query dibuat** — secara sinkron, di dalam
panggilan `Unrest:Query`, **sebelum** handle-nya dikembalikan:

```luau
local handle
handle = unrest:Query({ Tag = "Unrest" }, {
    Added = function(element)
        print(handle)   --> nil, untuk setiap elemen yang sudah ada duluan
    end,
})
```

`QueryHandle:Bind` adalah asimetri yang perlu diperhatikan: menggabungkan `Added` belakangan
akan mengikat ulang setiap elemen tapi **tidak menyalakan `Added`** untuk satu pun, karena
mereka semua sudah tiba. Kalau kamu membutuhkannya untuk himpunan yang sudah ada, oper dia di
panggilan `Query` yang pertama.

### `Removed`

Elemennya berhenti cocok: tagnya dicabut, `UnrestIgnore` dicentang, dinamai ulang, dipindah,
dihancurkan, atau query-nya sendiri di-`Destroy()`.

**Persis sekali per kepergian**, dan ini satu-satunya jaminan di seluruh tabel handler —
itulah sebabnya di sinilah tempat yang benar untuk membatalkan apa pun yang ditinggalkan
handler interaksi.

Dia berjalan **setelah** koneksi event elemennya dibongkar, jadi elemennya sudah pasif saat
itu. Dan kalau penyebabnya `Destroying`, instance-nya sedang dalam perjalanan keluar:
bersihkan sekarang juga, jangan menunda ke frame berikutnya di mana sudah tidak ada apa-apa
untuk dibersihkan.

---

## Selanjutnya

* **[Cakupan Adapter](UI-ADAPTERS.md)** — tabel per kelas: event apa dan properti bindable apa.
* **[API Elements & Query](API-ELEMENTS.md)** — cara mengoper handler ini.
* **[Pemecahan Masalah](TROUBLESHOOTING.md)** — pesan galat saat sebuah ikatan ditolak.
