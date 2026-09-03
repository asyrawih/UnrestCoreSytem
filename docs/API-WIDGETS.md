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

# API — `Widgets`

Sebuah widget adalah beberapa instance yang baru berarti kalau digabung: slider itu track,
knob, fill, dan label. Framework mengadopsinya satu per satu, dalam urutan yang tidak bisa
ditebak, dan menyerahkannya sendiri-sendiri.

`Widgets` yang mengurus pembukuan itu: mengumpulkan bagian-bagiannya, mengelompokkan dengan
`UnrestGroup`, menunggu sampai lengkap, lalu membereskannya lagi kalau layarnya dibangun ulang.

```luau
local widgets = unrest.Widgets
```

**Client saja.** Widget itu benda di layar, dan server tidak punya layar. Memanggilnya di
server akan **raise**, bukan diam-diam tidak melakukan apa-apa.

---

## Kenapa lapisan ini ada

Ini jawaban untuk masalah yang jadi alasan framework ini dibuat: **mendesain ulang sebuah
kontrol di Studio tidak boleh memaksa menulis ulang kodenya.**

`Each` hanya menyebut *peran* yang dibutuhkannya. Bagian-bagiannya boleh diganti nama,
dipindah induknya, diubah gayanya, atau diganti seluruhnya — handler yang sama tetap
menemukannya.

---

## `Widgets:Each` — satu tabel per widget

```luau
unrest.Widgets:Each({
    Required = { "SliderTrack", "SliderFill", "SliderKnob", "SliderLabel" },
    Optional = { "SliderTooltip" },

    OnReady = function(group: string, parts: Types.WidgetParts, scope: Types.Scope)
        local track = parts.SliderTrack :: Frame
        local knob = parts.SliderKnob :: GuiObject
        -- ...
    end,
})
```

| Field | Tipe | Arti |
| --- | --- | --- |
| `Required` | `{ string }` | Peran yang **wajib** ada. Grup baru jadi widget setelah semuanya diadopsi, dan berhenti jadi widget begitu salah satunya pergi. |
| `Optional` | `{ string }?` | Dikumpulkan ke tabel yang sama tapi tidak pernah menahan panggilan. Yang datang belakangan tinggal muncul di `parts`. |
| `OnReady` | fungsi | Dipanggil sekali per `UnrestGroup` yang lengkap. |

`OnReady` menerima tiga hal:

- **`group`** — nilai `UnrestGroup` yang dipakai bersama oleh bagian-bagiannya.
- **`parts`** — `{ [string]: Instance? }`, dikunci per peran. Peran opsional boleh `nil`,
  makanya tipenya opsional; untuk peran wajib silakan langsung di-cast.
- **`scope`** — cleanup scope. **Taruh semua koneksi widget ini di sana.**

### Scope itu bagian terpenting

Framework menghancurkan `scope` begitu salah satu peran wajib pergi — tag dilepas, instance
dihapus, atau dipindah keluar dari layar pemain. Kalau bagian itu kembali, `OnReady` jalan
lagi dengan scope yang baru.

Tanpa itu, layar yang dibangun ulang akan **memasang kabel dua kali**, dan satu klik memicu
dua handler.

```luau
OnReady = function(group, parts, scope)
    local button = parts.ToggleButton :: GuiButton

    unrest.Scope.add(scope, button.Activated:Connect(function()
        print(group, "ditekan")
    end))
end,
```

`Each` mengembalikan handle dengan `:Destroy()` untuk menghentikan satu resep ini saja. Resep
lain tetap jalan.

### Satu query, bukan satu per peran

Semua panggilan `Each` mendaftar ke **satu** query bersama di atas tag framework. Query
mengawasi setiap elemen yang dipegangnya — sinyal properti, sinyal atribut, ancestry — jadi
N query di atas tag yang sama berarti N set pengawas di instance yang sama. Dua kontrol
dengan tujuh peran berbiaya satu query, bukan tujuh.

### Hanya layar milik pemain

Selagi game jalan, layar yang ditandai itu **ada dua**: template di `StarterGui` dan salinan
milik pemain di `PlayerGui`. Keduanya ada di DataModel dan keduanya diadopsi, jadi query
mengembalikan dua dari segalanya — dan karena keduanya memakai nama grup yang sama, yang
datang duluan merebut grupnya. Kalau itu templatnya, kontrol pemain tidak pernah tersambung
dan **tidak ada apa pun yang kelihatan terjadi**.

`Widgets` mengabaikan apa pun di luar `PlayerGui` pemain. Kamu tidak perlu memikirkannya.

### Peringatan yang akan kamu lihat

- Elemen memegang peran yang diminta tapi tidak punya `UnrestGroup` → tidak ada widget yang
  bisa dimasukinya.
- Dua instance memegang peran yang sama untuk satu grup → yang pertama dipakai, yang kedua
  diabaikan. Beri yang kedua `UnrestGroup` sendiri.

---

## `Widgets:Drag` — tekan, geser, lepas

```luau
unrest.Widgets:Drag(scope, knob, track, function(fraction: number)
    -- selama digeser, fraction 0..1
end, function(fraction: number)
    -- sekali saat dilepas
end)
```

| Argumen | Tipe | Arti |
| --- | --- | --- |
| `scope` | `Types.Scope` | Tempat koneksinya diparkir. Biasanya scope dari `OnReady`. |
| `handle` | `Instance` | Yang ditekan. Harus `GuiObject`, **tidak perlu ditandai atau diadopsi**. |
| `track` | `Instance` | Rel yang diukur. Harus `GuiObject`. |
| `onMove` | `(number) -> ()` | Jalan terus selama geseran. |
| `onCommit` | `((number) -> ())?` | Jalan sekali, di nilai tempat pemain berhenti. |

Mengembalikan scope geseran yang sedang berjalan, untuk pemanggil yang perlu membatalkan
satu geseran tanpa membongkar widgetnya.

**Kenapa helper ini harus ada.** `GuiObject.InputEnded` hanya menyala selama penunjuk masih
di atas instance-nya, dan geseran meninggalkan knob dalam dua puluh piksel pertama. Geseran
yang diakhiri oleh `Release` milik knob sendiri **tidak akan pernah berakhir**.
`UserInputService.InputEnded` menyala di mana pun penunjuknya berada.

**Pisahkan `onMove` dan `onCommit` kalau harganya beda.** Satu geseran memicu `onMove`
ratusan kali dan `onCommit` sekali. Slider volume mau setiap gerakan, karena pemain sedang
mendengarkan. Seek yang memuat ulang hanya mau nilai terakhir.

---

## `Widgets:Destroy`

Membongkar semuanya: semua resep, semua widget yang tersambung, dan query bersamanya.
Jarang dipakai — biasanya kamu ingin `:Destroy()` pada handle dari satu `Each`.

---

## Contoh lengkap

Lihat `src/game-client/Slider.luau` dan `src/game-client/Toggle.luau`. Keduanya ditulis
persis di atas API ini, dan keduanya memakai bentuk yang sama: aksi dikunci per
`UnrestGroup`, jadi menambah kontrol tidak pernah menyunting handler yang sudah ada.

```luau
require(script.Toggle)(unrest, {
    Fullscreen = { Initial = true, OnChange = function(nilai) ... end },
    Notifikasi = { OnChange = function(nilai) ... end },
})
```
