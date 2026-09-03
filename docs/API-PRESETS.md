# API — `Presets`

Preset adalah **bundel atribut wiring yang punya nama**.

```luau
local Presets = require(ReplicatedStorage.Unrest.Presets)
```

Perhatikan: modul ini dipanggil dengan **titik**, bukan titik dua. Dia bukan objek dengan
metode, tapi modul dengan fungsi.

Kodenya ada di `src/shared/Presets.luau`.

---

## Untuk apa

Di Studio, desainer menulis satu atribut:

```
UnrestPreset = "MusicToggle"
```

dan `ElementManager` memekarkannya jadi lima atribut yang diwakili bundel itu.

Gunanya bukan sekadar ringkas. Gunanya: **"apa itu tombol musik" diputuskan sekali, di kode,
yang bisa ditelaah** — bukan diketik ulang di setiap tombol lalu perlahan melenceng satu sama
lain.

---

## Framework tidak membawa satu preset pun

Tabelnya kosong sejak awal, dan itu disengaja. Preset menyebut nama perintah atau channel,
dan nama itu milik game, bukan milik framework.

Game mengisinya dengan `Presets.Register` saat startup, dan framework tidak perlu tahu apa
yang masuk. Lihat [Modul Bersama Game](GAME-MODULE.md).

---

## Fungsi

### `Presets.Register(name: string, preset: Preset): Preset`

Mendaftarkan preset. Mengembalikan bundel yang kamu berikan.

```luau
local Constants = require(ReplicatedStorage.Unrest.Constants)
local ATTRIBUTES = Constants.Attributes

Presets.Register("MusicToggle", {
    [ATTRIBUTES.Command] = "Music.Play",
    [ATTRIBUTES.Payload] = "Lobby",
    [ATTRIBUTES.Channel] = "Music.NowPlaying",
    [ATTRIBUTES.Bind] = "Text",
    [ATTRIBUTES.Format] = "Musik: {value}",
})
```

**Melempar error** kalau: `name` bukan string tidak kosong; `preset` bukan tabel; atau ada
kunci yang **tidak diawali `Unrest`**. Pemeriksaan kunci itu yang menangkap salah ketik
seperti `Comand` sebelum dia berubah jadi tombol yang diam-diam tidak melakukan apa-apa.

Pakai `Constants.Attributes` untuk kuncinya, bukan string harfiah. Sekali dieja, sekali bisa
salah.

**Mendaftarkan nama yang sudah ada diizinkan, dan itu disengaja.** Game yang ingin salah satu
presetnya berarti hal lain harus bisa menyatakannya di satu tempat. Ini kebalikan dari
`Core:Register`, yang melempar error pada nama sistem yang terpakai dua kali — nama sistem
adalah kunci registry, sementara nama preset cuma singkatan yang boleh ditulis ulang.

### `Presets.Get(name: string): Preset?`

Bundel atribut bernama itu, atau `nil`.

```luau
local bundle = Presets.Get("MusicToggle")
```

### `Presets.List(): { string }`

Nama preset yang terdaftar, **terurut**. Ini yang muncul di pesan peringatan saat sebuah
`UnrestPreset` salah eja.

```luau
print(table.concat(Presets.List(), ", "))
```

---

## `Preset`

```luau
export type Preset = { [string]: any }
```

Peta dari nama atribut `Unrest*` ke nilainya. Nilainya harus berupa nilai atribut Roblox yang
sah — jadi primitif saja, sesuai rancangan Roblox.

---

## Preset adalah nilai bawaan, bukan penimpa

Urutan menangnya, paling spesifik dulu:

```
atribut milik elemen sendiri  >  presetnya  >  atribut leluhur terdekat yang bisa diwariskan
```

Jadi menyetel `UnrestPayload = "Dancefloor"` pada satu tombol yang memakai `MusicToggle`
membuat tombol **itu saja** memutar Dancefloor, sementara sisanya tetap memutar Lobby.

Itulah cara memodelkan "sembilan tombol yang sama, satu hal yang berbeda": taruh yang sama di
preset, taruh yang berbeda di elemennya.

---

## Preset adalah singkatan, bukan hak istimewa

Preset yang menyebut perintah yang tidak ada handler-nya berakhir persis seperti
`UnrestCommand` yang diketik tangan: dispatch-nya jalan di bus lokal dan tidak ada yang
menjawabnya. Mendaftarkan preset tidak mengubah kode framework dan tidak memberi izin apa pun —
yang dilakukannya cuma mengisi beberapa atribut yang bisa saja diketik satu per satu.

---

## Kalau namanya salah eja

Elemennya **tetap diadopsi**, dengan atributnya sendiri saja, dan kamu dapat peringatan yang
menyebutkan setiap preset yang benar-benar ada:

```
[Unrest.Elements] game.Players.You.PlayerGui.Menu.Play resolves UnrestPreset = "MusicTogle"
(set here), which is not a declared preset. Declared presets: DanceButton, DanceStop,
MusicStop, MusicToggle, NowPlayingLabel, VolumeButton. The element was adopted with its own
attributes only -- fix the spelling, or declare it with Presets.Register("MusicTogle", ...).
```

---

## `UnrestPreset` diwariskan — hati-hati

`UnrestPreset` adalah salah satu dari tiga atribut yang **diwariskan** dari leluhur, dan
karena tag juga menurun, preset di sebuah `ScreenGui` menjangkau **setiap** `GuiObject` di
bawahnya.

Kalau preset itu membawa `UnrestCommand`, kamu baru saja mempersenjatai seluruh isi layar.

Jadi: preset yang memekar jadi sebuah perintah sebaiknya ditaruh di elemen yang memang punya
niat itu. Simpan leluhurnya untuk hal-hal yang benar-benar gaya rumah.

Kamu akan tahu kalau salah — preset yang mempersenjatai `TextLabel` memberi peringatan bahwa
`Active` tidak bisa diikat padanya, lengkap dengan nama elemennya.

Lihat [Referensi Atribut](UI-ATTRIBUTES.md) untuk aturan pewarisan selengkapnya.
