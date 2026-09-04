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

# Referensi Atribut

Setiap atribut bersifat opsional. Instance yang cuma punya tag tetap diadopsi dan tetap bisa
di-query; dia sekadar tidak melakukan apa-apa sendiri.

---

## 1. Tabelnya

| Atribut | Tipe | Arti |
| --- | --- | --- |
| `UnrestRole` | string | Nama logis yang dipakai `Descriptor.Role`. Jatuh balik ke `Instance.Name`. |
| `UnrestGroup` | string | Pengelompokan bebas (`"MenuUtama"`, `"Toko"`), dipilih lewat `Descriptor.Group`. |
| `UnrestCommand` | string | Perintah yang dikirim lewat `Bridge:Dispatch` saat elemennya diaktifkan. |
| `UnrestPayload` | nilai atribut apa pun | Payload yang dikirim bersama `UnrestCommand`. |
| `UnrestChannel` | string | Channel yang dilanggani untuk nilai yang ditampilkan elemen ini. |
| `UnrestBind` | string | Properti tujuan penulisan nilai channel. Bawaannya `ValueProperty` milik adapter. |
| `UnrestFormat` | string | Templat yang diterapkan ke nilai channel. `{value}` adalah lubangnya. |
| `UnrestCooldown` | number | Debounce sisi client, dalam detik, antar aktivasi. **Anjuran saja.** |
| `UnrestPreset` | string | Menyebut bundel yang memekar jadi beberapa atribut di atas. |
| `UnrestWidget` | string | Menyebut skema widget yang dimainkan grup ini (`"Slider"`, `"Toggle"`). Ditulis di **akar** grup, bersebelahan dengan `UnrestGroup`. |
| `UnrestIgnore` | boolean | `true` mengeluarkan instance ini dan seluruh subtree-nya dari penurunan tag. Struktural, bukan wiring — dia tidak ikut dalam penggabungan di bagian 4. |

Nama-nama ini ada di `Constants.Attributes`. Pakai konstantanya di kode, jangan string
harfiah.

**Menyunting salah satunya menyambungkan ulang elemen itu saja**, secara langsung, lewat
`GetAttributeChangedSignal`. Mengubah `UnrestFormat` di Studio saat game berjalan akan
mengecat ulang labelnya pada penerbitan berikutnya; tidak ada yang perlu di-restart.

Mengubah atribut yang **bisa diwariskan** pada sebuah leluhur menyambungkan ulang setiap
keturunan yang dikelola. Memindahkan elemen meresolusi ulang dia terhadap leluhur barunya —
juga langsung, juga tanpa restart.

---

## 2. Tombol, tanpa kode

| | |
| --- | --- |
| Tag | `Unrest` |
| `UnrestCommand` | `Music.Play` |
| `UnrestPayload` | `Lobby` |

Mengaktifkannya memanggil `Bridge:Dispatch("Music.Play", "Lobby")`.

> `Music.Play` di sini adalah **perintah milik game contoh** di `src/game`, bukan API
> framework. Framework tidak mendeklarasikan satu perintah pun.

---

## 3. Label yang mengikuti state, tanpa kode

| | |
| --- | --- |
| Tag | `Unrest` |
| `UnrestChannel` | `Music.NowPlaying` |
| `UnrestBind` | `Text` |
| `UnrestFormat` | `Musik: {value}` |

Channel bersifat **ditahan**, jadi labelnya mengecat dirinya dengan benar sedetik setelah
diadopsi — entah musiknya mulai sejam yang lalu atau baru mulai sejam lagi. Urutan berhenti
jadi masalah.

`UnrestBind` boleh dihilangkan kalau kelasnya punya satu nilai yang jelas: `TextLabel`
menulis `Text`, `ImageLabel` menulis `Image`, `ScrollingFrame` menulis `CanvasPosition`.
Bawaan itu adalah `ValueProperty` milik adapter — lihat [Cakupan Adapter](UI-ADAPTERS.md).

Tanpa `UnrestFormat`, nilai yang diterbitkan ditulis mentah. Itulah cara menggerakkan
`Color3`, `UDim2`, atau `boolean` dari sebuah channel. Dengan format, hasilnya **selalu
string**, dan nilai `nil` menjadi kosong, bukan tulisan `nil`.

---

## 4. Resolusi: tiga lapis, yang paling spesifik menang

`UnrestGroup = "MenuUtama"` yang diketik ulang di sembilan tombol adalah sembilan kesempatan
salah ketik. Dua fitur menghapus pengulangan itu tanpa memindahkan satu keputusan pun keluar
dari Studio.

`element.Attributes` adalah gabungan ketiga lapisnya, dari yang paling lemah:

| Lapis | Datang dari | Mengalahkan |
| --- | --- | --- |
| 3. warisan | leluhur terdekat yang menyetel salah satu atribut yang bisa diwariskan | tidak ada |
| 2. preset | bundel yang disebut `UnrestPreset` | warisan |
| 1. elemen | apa yang kamu setel di instance ini | keduanya |

Jadi **preset adalah nilai bawaan, tidak pernah penimpa**, dan leluhur adalah cadangan, bukan
perintah. Menyetel `UnrestPayload` pada satu tombol yang memakai preset `MusicToggle`
mengubah tombol itu dan tidak yang lain.

### `Sources` — "siapa yang menyetel ini?"

`ManagedElement.Sources` mencatat lapis mana yang menang untuk setiap kunci, jadi
pertanyaan itu punya jawaban tanpa harus membuka tiga panel properti:

```luau
local element = unrest.Elements:Get(button)
print(element.Preset)                       --> MusicToggle
print(element.Sources.UnrestCommand.Origin) --> Preset
print(element.Sources.UnrestGroup.Text)     --> inherited from Menu (ScreenGui)

local Elements = require(ReplicatedStorage.Unrest.Elements)
print(Elements.describe(element))
--> UnrestChannel = Music.NowPlaying (from preset "MusicToggle"),
--> UnrestGroup = MainMenu (inherited from Menu (ScreenGui)),
--> UnrestPayload = Dancefloor (set here)
```

---

## 5. `UnrestPreset` — bundelnya

Preset didaftarkan oleh game, bukan oleh framework:

```luau
-- di kode game-mu, sebelum layarnya diadopsi
Presets.Register("MusicToggle", {
    [ATTRIBUTES.Command] = "Music.Play",
    [ATTRIBUTES.Payload] = "Lobby",
    [ATTRIBUTES.Channel] = "Music.NowPlaying",
    [ATTRIBUTES.Bind] = "Text",
    [ATTRIBUTES.Format] = "Musik: {value}",
})
```

Lalu di Studio:

| | |
| --- | --- |
| Tag | `Unrest` |
| `UnrestPreset` | `MusicToggle` |

Satu atribut, bukan lima. Gunanya bukan keringkasan: gunanya adalah **"apa itu tombol musik"
diputuskan sekali, di kode yang bisa ditelaah**, bukan diketik ulang di setiap tombol lalu
perlahan melenceng.

Preset adalah singkatan, bukan hak istimewa. Preset yang menyebut perintah yang tidak ada
handler-nya berakhir persis seperti `UnrestCommand` yang diketik tangan: dispatch-nya jalan dan
tidak ada yang menjawabnya.

Menyebut preset yang tidak ada memberi peringatan dan **tetap mengadopsi** elemennya, dengan
atributnya sendiri saja:

```
[Unrest.Elements] game.Players.You.PlayerGui.Menu.Play resolves UnrestPreset = "MusicTogle"
(set here), which is not a declared preset. Declared presets: DanceButton, DanceStop,
MusicStop, MusicToggle, NowPlayingLabel, VolumeButton. The element was adopted with its own
attributes only -- fix the spelling, or declare it with Presets.Register("MusicTogle", ...).
```

Lihat [API Presets](API-PRESETS.md).

---

## 6. `UnrestWidget` — grup yang menyebut dirinya

Sebuah widget adalah beberapa instance yang baru berarti kalau digabung, dan `UnrestGroup`
yang menyatukannya. `UnrestWidget` menyebut **jenis**-nya:

| | |
| --- | --- |
| Tag | `Unrest` |
| `UnrestGroup` | `Musik` |
| `UnrestWidget` | `Slider` |

Ketiganya di satu instance: **akar** grup, yaitu instance yang menyediakan `UnrestGroup`
untuk bagian-bagiannya. Nama skemanya dibaca dari `Widgets/Schemas.luau`, dan yang membaca
atributnya ada tiga — runtime (`Widgets:Each({ Widget = "Slider" })` dan `Widgets:Report()`),
perkakas Studio, dan generator kosakata. Lihat [API Widgets](API-WIDGETS.md).

Dua aturan, dan keduanya sengaja:

- **Tidak pernah diwariskan.** Dia identitas milik akar itu saja. Kalau menurun, setiap Frame
  di bawah sebuah panel akan mengaku slider.
- **Tidak boleh ada di dalam preset.** `Presets.Register` menolaknya dengan menyebut
  alasannya: preset adalah bundel *wiring* yang dipakai ulang, sedangkan widget adalah satu
  benda di layar. Preset yang membawa `UnrestWidget` akan menamai selusin grup sekaligus
  dengan satu benda yang sama.

Grup yang **setiap** bagiannya menyetel `UnrestGroup`-nya sendiri tidak punya akar bersama,
jadi tidak ada tempat untuk atribut ini. `Widgets:Report()` dan `Widgets:Explain(group)`
mengatakannya; perbaikannya memindahkan grup itu ke wadah bersama.

---

## 7. Warisan — konteks, tidak pernah niat

Persis **tiga** atribut yang diwarisi dari leluhur, dan ketiganya terdaftar di
`Constants.Inheritable`:

| Atribut | Kenapa boleh diwariskan |
| --- | --- |
| `UnrestGroup` | layar mana sebuah elemen berada — setiap elemen di layar itu punya jawaban yang sama |
| `UnrestCooldown` | debounce gaya rumah untuk satu panel tombol |
| `UnrestPreset` | bundel bawaan untuk semua yang ada di bawah satu wadah |

Selebihnya — `UnrestRole`, `UnrestCommand`, `UnrestPayload`, `UnrestChannel`, `UnrestBind`,
`UnrestFormat`, `UnrestWidget` — adalah **niat per elemen dan tidak pernah diwariskan**.
Perintah yang diwariskan akan diam-diam mempersenjatai setiap keturunan sebuah panel dengan
perintah yang sama, dan itu kebalikan dari fitur. `UnrestRole` adalah identitas elemen ini,
jadi dia juga tinggal di tempatnya, dan `UnrestWidget` adalah identitas akar sebuah grup.

### Penelusurannya berhenti di layar

Penelusuran naik dari induk elemennya dan berhenti di **`LayerCollector` pertama**
(`ScreenGui`, `SurfaceGui`, `BillboardGui`), setelah membaca atribut milik `LayerCollector`
itu sendiri.

Satu layar adalah cakupan terluas yang boleh dimiliki sebuah atribut warisan. Service dan
DataModel tidak pernah dibaca sama sekali — `UnrestGroup` di `Players` akan jadi variabel
global, dan variabel global persis hal yang tidak ingin jadi ini.

Setiap leluhur di rantai itu diawasi, bukan hanya yang sekarang memberi nilai: leluhur yang
lebih dekat yang menyetel `UnrestGroup` besok harus menang sedetik setelah dia melakukannya.
Koneksinya menggantung di maid milik elemennya sendiri dan dibongkar-pasang ulang setiap kali
resolusi diulang, jadi elemen yang dipindah cuma memegang koneksi ke leluhur barunya.

> **Penurunan tag melipatgandakan warisan.** `UnrestGroup` di sebuah `ScreenGui` sekarang
> menjangkau setiap `GuiObject` di bawahnya, bukan hanya yang kamu tandai — dan itu memang
> tujuannya. Tapi `UnrestPreset` juga menjangkau mereka, dan preset yang membawa
> `UnrestCommand` akan mempersenjatai seluruhnya.
>
> Jadi: taruh preset yang memekar jadi sebuah perintah pada elemen yang memang punya niat itu,
> dan simpan leluhurnya untuk hal-hal yang benar-benar gaya rumah. Kamu akan dengar kalau
> salah — preset yang mempersenjatai `TextLabel` memberi peringatan bahwa `Active` tidak bisa
> diikat padanya, lengkap dengan nama elemennya.

### Query melihat grup yang diwariskan

`Descriptor.Group` memakai fungsi yang sama persis dengan yang mengisi `element.Attributes`,
yaitu satu fungsi yang menerapkan "milik sendiri > preset > leluhur terdekat". Jadi sebuah
grup tidak akan pernah dilaporkan pada elemen yang tidak bisa ditemukan query-nya.

`UnrestGroup` yang ditulis sekali di sebuah `ScreenGui` sudah cukup untuk membuat
`Unrest:Query({ Group = "MenuUtama" })` memilih semua yang ada di bawahnya — begitu pula
`UnrestPreset` di sana yang bundelnya membawa `UnrestGroup`.

Kehidupan itu berlaku juga untuk penyaringnya: filter `Group` mengawasi `UnrestGroup`
**dan** `UnrestPreset` di setiap leluhur. Mengganti preset di sebuah `ScreenGui` saat game
berjalan memindahkan elemen di bawahnya masuk dan keluar himpunan hasil, persis seperti
menyunting grupnya di sana.

### Satu perbedaan yang disengaja antara dua penelusuran

Penelusuran **warisan** berhenti di `LayerCollector` pertama. Penelusuran **penurunan tag**
tidak.

Alasannya: grup yang bocor melewati sebuah `ScreenGui` akan mulai memilih elemen di layar
yang tidak berhubungan, karena grup adalah konteks ambien. Sementara tag ditaruh pada satu
wadah tertentu dengan sengaja, dan menandai sebuah `Folder` berisi banyak `ScreenGui` adalah
hal yang mungkin memang dimaksudkan seseorang.

Keduanya sama-sama tidak pernah membaca service atau DataModel.

---

## 8. Atribut tidak memberi hak istimewa

`UnrestCommand` lewat **`Bridge:Dispatch` yang sama persis** dengan Luau tulisan tangan, dan
sampai ke handler yang sama. Atribut bukan mekanisme kedua: dari seberang Bridge, layar yang
dirakit di Studio dan layar yang dirakit di kode tidak bisa dibedakan.

Bridge adalah bus di dalam satu mesin. Jadi atribut tidak memberi hak istimewa **apa pun**, dan
pertanyaan keamanannya tidak muncul di lapisan ini: sebuah dispatch tidak menyeberang ke mana
pun, dan siapa yang boleh meminta apa diputuskan oleh kode yang menangani perintahnya — kode
game-mu, di luar framework.

`UnrestCooldown` adalah **debounce sisi client dan tidak lebih**. Dia ada supaya klik ganda
yang tidak sengaja tidak mengirim dua dispatch. Dia tinggal di memori client ini, siapa pun
yang mau menghapusnya bisa, dan **dia bukan batas laju**. Kalau perintahnya berakhir jadi
permintaan ke server, yang membatasinya harus kode yang menerima permintaan itu.
