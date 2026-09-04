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
| `Required` | `{ string }?` | Peran yang **wajib** ada. Grup baru jadi widget setelah semuanya diadopsi, dan berhenti jadi widget begitu salah satunya pergi. Boleh dikosongkan **hanya** kalau `Widget` diisi. |
| `Optional` | `{ string }?` | Dikumpulkan ke tabel yang sama tapi tidak pernah menahan panggilan. Yang datang belakangan tinggal muncul di `parts`. |
| `Widget` | `string?` | Nama skema di `Widgets/Schemas.luau` (`"Slider"`, `"Progress"`, `"Toggle"`, atau milikmu sendiri). Lihat di bawah. |
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

`Each` mengembalikan handle dengan tiga hal:

| Anggota | Arti |
| --- | --- |
| `handle:Destroy()` | Menghentikan satu resep ini saja. Resep lain tetap jalan. |
| `handle:Get(group)` | `parts` milik grup yang **sedang** tersambung, atau `nil`. Grup yang baru setengah terkumpul bukan widget, jadi jawabannya `nil` — bukan tabel setengah jadi. |
| `handle:Groups()` | Nama grup yang sedang tersambung, terurut. |

```luau
local slider = unrest.Widgets:Each({ Widget = "Slider", OnReady = ... })

local parts = slider:Get("Musik")
if parts ~= nil then
    (parts.SliderKnob :: GuiObject).Visible = false
end
```

`Get` adalah jawaban untuk "aku cuma butuh sekali": ambil bagiannya setelah `Each`, jangan
menghancurkan scope dari dalam `OnReady`-nya sendiri.

### `Widget` — grup yang menyebut dirinya

`UnrestWidget` di **akar** sebuah grup menyebut skema yang dimainkan grup itu:

```luau
akar:SetAttribute("UnrestGroup", "Musik")
akar:SetAttribute("UnrestWidget", "Slider")
```

```luau
unrest.Widgets:Each({
    Widget = "Slider", -- Required/Optional diambil dari Schemas.Get("Slider")
    OnReady = function(group, parts, scope) ... end,
})
```

- `Required` dan `Optional` diambil dari skemanya. Menulisnya sendiri di spec **menang**;
  `Widget` lalu tinggal jadi penyaring grup.
- Resep itu **hanya** memegang grup yang akarnya ber-`UnrestWidget = "Slider"`. Grup lain
  dengan peran yang persis sama tidak disentuhnya.
- Nama skema yang tidak terdaftar **raise**, sambil menyebut yang terdaftar. Diam di sini
  berarti resep yang tidak pernah memegang apa pun.
- `Each` polos (tanpa `Widget`) tidak berubah sedikit pun: dia tidak pernah melihat akar, jadi
  resep polos dan resep ber-`Widget` boleh memegang grup yang sama tanpa saling tahu.

Menyunting `UnrestWidget` di akar **saat game jalan** memindahkan grupnya keluar-masuk resep:
scope lamanya dihancurkan dan `OnReady` jalan lagi di resep yang baru.

### Akar sebuah grup

Semua bagian sebuah grup membaca `UnrestGroup` dari **satu** tempat: leluhur terdekat yang
menyetelnya, atau bagian itu sendiri kalau dia menyetel miliknya sendiri. Instance itulah
**akar** grup, dan cuma di sana `UnrestWidget` dibaca. Aturannya sama persis dengan resolusi
atribut biasa — punya sendiri, lalu preset (dicatat di instance tempat nama presetnya
diketik), lalu leluhur terdekat.

Grup yang **setiap** bagiannya menyetel `UnrestGroup`-nya sendiri tidak punya akar bersama.
Itu sah dan tetap tersambung untuk `Each` polos, tapi tidak ada tempat untuk `UnrestWidget`.
`Report` dan `Explain` mengatakannya; perbaikannya memindahkan grup ke wadah bersama.

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

### Mengikuti perubahan role dan group

Query bersama hanya menyeleksi tag, jadi ia **tidak** mengumumkan ulang elemen yang
`UnrestRole` atau `UnrestGroup`-nya diubah — elemen itu masih membawa tag, dan bagi query
tidak ada yang terjadi. Padahal widget dikunci persis oleh dua hal itu.

Karena itu `Widgets` memasang satu pengawas kecil per elemen di query: `UnrestRole`, `Name`
(pengganti role kalau atributnya kosong), `UnrestGroup`, `UnrestPreset` dan `UnrestWidget` di
elemen dan di setiap leluhurnya, plus `AncestryChanged`. Begitu jawabannya berubah, elemen
keluar dari slot lamanya (widget yang mewajibkannya dibongkar) lalu ditawarkan lagi ke setiap
resep dengan role, group, dan widget barunya (widget yang kini lengkap dipasang).

Hanya perubahan **nyata** yang menggerakkan sesuatu. Mengganti nama elemen yang role-nya
sudah diset lewat atribut tidak membongkar apa pun. Pengawasnya dibayar sekali per elemen,
berapa pun `Each` yang terdaftar.

### Peringatan yang akan kamu lihat

- Elemen memegang peran yang diminta tapi tidak punya `UnrestGroup` → tidak ada widget yang
  bisa dimasukinya.
- Dua instance memegang peran yang sama untuk satu grup → yang pertama dipakai, yang kedua
  diabaikan. Beri yang kedua `UnrestGroup` sendiri.

---

## Control bawaan — `Register` dan `Use`

Framework membawa tiga control yang **dia sendiri** yang menjalankannya:
**`Slider`**, **`Progress`**, dan **`Toggle`**. Akar yang membawa `UnrestGroup` dan
`UnrestWidget = "Slider"` sudah jadi slider yang jalan — dilukis, digeser, dan diingat
nilainya — **tanpa satu baris Luau pun**.

```luau
akar:SetAttribute("UnrestGroup", "Musik")
akar:SetAttribute("UnrestWidget", "Slider")
```

### Mount otomatis, bukan mount kalau diminta

Control yang terdaftar di-mount untuk **setiap** grup yang akarnya ber-`UnrestWidget` sama
dengan namanya dan yang peran wajibnya lengkap — **dipanggil atau tidak `Use`**. Apa yang
dimainkan sebuah grup itu diucapkan di Studio; `Use` cuma memasok config.

Di dalam, sebuah control adalah **satu `Each` biasa** dengan `Widget` diisi namanya. Tidak ada
pembukuan kedua: control dan resep tulisan tangan hanya beda siapa yang menulisnya. Dua-duanya
boleh memegang grup yang sama tanpa saling tahu.

### `Widgets:Use(name, config?)`

```luau
local sliders = unrest.Widgets:Use("Slider", {
    Musik = {
        Initial = 0.4,
        OnChange = function(fraction: number)
            unrest.Bridge:Publish("Volume.Musik", math.round(fraction * 100))
        end,
    },

    Efek = {
        OnCommit = function(fraction: number)
            print("efek disetel ke", fraction)
        end,
    },
})
```

`config` dikunci per `UnrestGroup`. Grup yang tidak disebut **tetap** di-mount dan tetap jalan;
dia cuma tidak bereaksi ke apa pun, karena tidak ada yang bilang nilainya berarti apa.

| Anggota | Arti |
| --- | --- |
| `handle:Get(group)` | `ControlHandle` yang sedang menjalankan grup itu, atau `nil`. |
| `handle:Groups()` | Grup yang sedang dijalankan control ini, terurut. |
| `handle:Destroy()` | Membuang config yang dipasok panggilan ini. **Tidak** meng-unmount apa pun — yang menentukan mount itu `UnrestWidget` di akar, bukan siapa yang minta. |

Memanggil `Use` dua kali untuk control yang sama **mengganti** config-nya, bukan menambahkan:
itu config milik control, bukan langganan. Grup yang sudah ter-mount di-mount ulang ke config
yang baru — tanpa terlihat, karena nilainya diingat melintasi mount ulang, `OnChange` tidak
dipanggil untuknya, dan tidak ada yang diterbitkan.

`Use(name)` **tanpa** config hanya mengembalikan handle: config yang berlaku tidak diganti dan
tidak ada yang di-mount ulang. Itu cara meminta `Get` tanpa memutus geseran yang sedang
berjalan.

### `ControlHandle` — satu control yang sedang jalan

```luau
local musik = sliders:Get("Musik")
if musik ~= nil then
    musik:Set(0.75)          -- melukis, tidak memanggil OnChange
    print(musik:Get())       -- 0.75
    musik.Changed:Connect(function(value)
        print("digeser ke", value)
    end)
end
```

| Anggota | Arti |
| --- | --- |
| `handle:Get()` | Nilainya sekarang. |
| `handle:Set(value)` | Melukis **tanpa** memanggil `OnChange` dan tanpa menyalakan `Changed`. Untuk nilai yang datang dari luar. |
| `handle.Changed` | `Signal<any>`. **Hanya** perubahan pengguna: tidak pernah saat mount, tidak pernah sebagai gema `Set`. |
| `handle.Committed` | `Signal<any>?`. Menyala sekali saat gerakan selesai, dengan nilai yang disepakati: geseran dilepas, switch ditekan. `nil` pada control tanpa gerakan (`Progress`). |

### State per grup — kenapa layar yang dibangun ulang tidak melompat ke nol

Nilai sebuah grup hidup di **pendaftaran control**, bukan di dalam scope mount-nya. Scope mati
setiap kali salah satu peran wajib pergi — `ScreenGui` diganti, satu bagian dilepas tag-nya —
dan kalau nilainya ikut mati bersamanya, kontrol yang kembali akan melukis nol dan (dulu)
menerbitkannya sebagai kalau pemain baru saja menggesernya ke sana.

Aturannya satu kalimat: **control memanggil `OnChange`/`OnCommit` hanya untuk gerakan pemain,
tidak pernah saat mount.**

- `Initial` dibaca **sekali**, pada mount pertama sebuah grup. Sesudah itu nilai terakhirlah
  yang menang.
- Nilai itu di-snapshot saat scope-nya turun, jadi yang terekam bukan cuma hasil geseran tapi
  juga hasil `Set` dari game.
- Mount berikutnya melukis nilai itu lewat `Set`, yang diam.

### Framework tidak pernah mengeja nama

Control bawaan **tidak pernah** memanggil `Bridge:Publish` dan tidak pernah `Dispatch`. Itu
bukan kelalaian: nama channel dan perintah milik game, dan framework tidak boleh mengejanya
(lihat CONVENTIONS). Makanya `Mount` dikasih **library widget**, bukan singleton `Unrest` —
tidak ada bus dalam jangkauannya untuk diterbiti.

Satu-satunya nama yang dirutekan framework adalah nama yang **diketik desainer** di
`UnrestChannel`/`UnrestCommand` pada akar widget — sama persis dengan `UnrestCommand` pada
sebuah tombol, dan tetap bukan nama yang dieja framework. Lihat
[Channel dan perintah di akar](#channel-dan-perintah-di-akar--slider-tanpa-luau).

`OnChange` dan `OnCommit` adalah pintu keluarnya. Di kode game, di sanalah sebuah geseran
jadi `Volume.<group>`:

```luau
unrest.Widgets:Use(Vocab.Widgets.Slider, {
    [Vocab.Groups.Musik] = {
        OnChange = function(fraction: number)
            unrest.Bridge:Publish("Volume.Musik", math.round(fraction * 100))
        end,
    },
})
```

### `Widgets:Register(control)` — control buatan sendiri

```luau
unrest.Widgets:Register({
    Name = "Stepper",
    Schema = MySchema,
    Mount = function(widgets, group, parts, scope, config)
        -- ...
        return { Get = ..., Set = ..., Changed = signal }
    end,
})
```

| Field | Arti |
| --- | --- |
| `Name` | Nama yang dicari di `UnrestWidget`, dan nama skemanya. |
| `Schema` | `WidgetSchema`-nya. `Schema.Name` harus sama dengan `Name`. Kalau belum ada yang terdaftar dengan nama itu, ini yang didaftarkan — tapi tidak pernah **mengganti** yang sudah ada. |
| `Mount` | `(widgets, group, parts, scope, config) -> ControlHandle`. Dipanggil sekali per grup per perakitan, di atas scope yang mati bersama widget-nya. |

`Committed` boleh dikosongkan. Kalau ada, dia yang dipakai framework sebagai "gerakan
selesai" saat akarnya membawa `UnrestChannel`/`UnrestCommand`; kalau tidak ada, setiap
`Changed` dianggap sudah selesai seketika.

- Mendaftar nama yang sama dua kali **mengganti**, sama seperti `Schemas.Register` dan
  `Presets.Register`. Yang sedang dijalankannya diturunkan lalu dinaikkan lagi di atas control
  baru, pada nilai terakhirnya.
- Mendaftar **sesudah** grupnya sudah ada di layar tetap men-mount grup itu: resepnya memutar
  ulang query yang sudah terbuka.
- Client saja, sama seperti `Each` dan `Use`.

### `Progress` — slider yang tidak bisa disentuh

Skema `Progress` mewajibkan `SliderTrack` dan `SliderFill` dan **tidak pernah** menyebut knob,
jadi control-nya tidak pernah memasang `Drag`. Lukisannya sama persis dengan Slider (dibagi
lewat `Controls/SliderPaint.luau`), nilainya cuma pernah datang dari luar:

```luau
local bar = unrest.Widgets:Use("Progress", { Muat = { Initial = 0 } })
local muat = bar:Get("Muat")
if muat ~= nil then
    muat:Set(0.4)
end
```

`Changed` ada dan tidak pernah menyala, karena tidak ada yang bisa mendorong sebuah progress
bar; `Committed` bahkan tidak ada, karena tidak ada gerakan yang bisa selesai.

---

## Channel dan perintah di akar — slider tanpa Luau

Tombol sudah bisa dideklarasikan seluruhnya di Studio sejak awal: satu tag, satu
`UnrestCommand`. Slider tidak, karena nilainya bukan satu properti melainkan sebuah gerakan
dengan awal dan akhir. Dua atribut di **akar** widget menutup jarak itu:

| | |
| --- | --- |
| Tag | `Unrest` |
| `UnrestGroup` | `Musik` |
| `UnrestWidget` | `Slider` |
| `UnrestChannel` | `Volume.Musik` |

Tidak ada `Use`, tidak ada `Each`, tidak ada satu baris Luau pun di sisi game. Yang digeser
pemain sampai ke `Bridge`, dan apa pun yang diterbitkan ke `Volume.Musik` dari mana pun
melukis slider-nya. `studio/BuildSliderMulti.luau` dan `studio/BuildToggle.luau` adalah benih
layarnya.

### Siapa yang membaca atribut itu

`Elements` **tidak**. Sebuah instance yang menyetel `UnrestWidget` adalah akar widget, dan
`Elements` melewati `UnrestCommand` dan `UnrestChannel` di situ — keduanya milik control yang
di-mount `Widgets` di akar itu. Konsekuensi yang langsung terasa: akar `Frame`
ber-`UnrestCommand` tidak lagi memunculkan peringatan "kelas ini tidak bisa diaktifkan", dan
akar `TextButton` tidak mengirim perintah saat diklik — dia mengirimnya saat gerakannya
selesai. Satu predikat menjawabnya di tiga tempat (`Selector.isWidgetRoot`): runtime `Elements`,
runtime `Widgets`, dan lint Studio.

Bagian-bagian **di bawah** akar tidak terpengaruh sama sekali. `UnrestChannel` pada sebuah
`SliderLabel` tetap menulis `Text`-nya seperti biasa.

### Jendela kepemilikan lukisan

| Saat | Yang melukis |
| --- | --- |
| Mount | Nilai dari `Bridge:Peek(channel)` kalau ada; kalau tidak, nilai terakhir grup itu atau `Initial`. Diam — tidak ada yang diterbitkan. |
| Gerakan berlangsung | **Gerakan itu**. Nilai yang datang di channel diabaikan, dari `Changed` pertama sampai commit. |
| Commit (lepas / tekan) | Control menerbitkan **sekali** `Bridge:Publish(channel, nilai)`, lalu mengikuti channel lagi. `UnrestCommand`, kalau ada, di-`Dispatch` di saat yang sama dengan nilai itu sebagai payload. |
| Idle | Channel. Setiap `Publish` melukis. |

Aturan jendelanya satu kalimat: **selama jari menempel, jari yang menang.** Knob yang melompat
ke nilai yang diterbitkan sistem lain di tengah geseran akan berkelahi dengan tangan yang
memegangnya.

Bus-nya sinkron, jadi `Publish` milik control itu sendiri kembali ke langganannya sendiri
sebelum panggilannya selesai. Gema itu dikenali dari **nilainya sama dengan yang baru saja
dikirim** dan diabaikan — tidak perlu menunggu satu frame, tidak ada flag yang harus
dibersihkan belakangan.

Control tanpa `Committed` (control buatan sendiri yang gerakannya tidak punya akhir terpisah)
diperlakukan seperti gerakan yang selesai seketika: `Changed` langsung menerbitkan.

### Menyunting akar saat game jalan

Mengetik, mengubah, atau menghapus `UnrestChannel`/`UnrestCommand` di akar **langsung
berlaku**, sama seperti atribut lain: routing-nya dibangun ulang di tempat, tanpa membongkar
control-nya dan tanpa mengubah nilainya. Satu batasannya: yang diawasi adalah kedua atribut
itu **di akar itu sendiri**. Channel yang datang lewat `UnrestPreset` baru terbaca pada mount
berikutnya.

### Nilai yang tidak bisa dipakai control

Channel adalah data yang diterbitkan kode lain, dan control menentukan apa yang bisa
dipegangnya — `Toggle` melempar error untuk apa pun selain boolean. Karena wiring-nya diketik
di Studio, aturan "kode melempar error, atribut memperingatkan" berlaku: nilainya diabaikan
dan satu peringatan menyebut grup, channel, dan tipenya.

```
[Unrest.Widgets] group "Fullscreen" could not take the number published on "Toggle.Fullscreen": ...
```

### Kalau kamu tetap mau menulis Luau

`Use` tetap jalan berdampingan. `OnChange`/`OnCommit` dipanggil seperti biasa untuk grup yang
akarnya juga punya channel — yang satu tidak menggantikan yang lain. Yang perlu diperhatikan
cuma satu: kalau `OnCommit` kamu sendiri juga `Publish` ke channel yang sama, nilainya
diterbitkan dua kali.

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
| `options` | `Types.DragOptions?` | Sumbu dan arahnya. Lihat di bawah. |

Mengembalikan scope geseran yang sedang berjalan, untuk pemanggil yang perlu membatalkan
satu geseran tanpa membongkar widgetnya.

`track` yang lebarnya masih `0` (sebelum layout pass pertama) menghasilkan `0`, bukan NaN.

### `DragOptions` — sumbu dan arah

| Field | Bawaan | Arti |
| --- | --- | --- |
| `Axis` | `"X"` | `"X"` atau `"Y"`. Sumbu yang diukur; sumbu yang lain diabaikan. |
| `Invert` | `false` | `true` membalik jawabannya jadi `1 - fraction`. |

```luau
-- Slider tegak: bawah = 0, atas = 1.
unrest.Widgets:Drag(scope, knob, track, onMove, onCommit, { Axis = "Y", Invert = true })
```

Slider tegak hampir selalu `Invert = true`, karena track diukur ke bawah sementara volume
tidak. Ukuran nol pada sumbu yang dipilih tetap menghasilkan `0`, **juga** saat `Invert`:
ukuran nol itu ketiadaan, bukan salah satu ujung.

> **Sumbu `Y` menuntut `ScreenGui.IgnoreGuiInset = true`.** Posisi input mentah dan
> `AbsolutePosition` baru sejajar dengan itu; tanpanya ada selisih setinggi topbar yang cuma
> kelihatan kadang-kadang. Ketiga skrip benih di `studio/` menyetelnya.

### `Widgets:Drag2D` — geseran dua sumbu

```luau
unrest.Widgets:Drag2D(scope, knob, pad, function(position: Vector2)
    -- selama digeser, X dan Y masing-masing 0..1
end, function(position: Vector2)
    -- sekali saat dilepas
end)
```

Mesin geserannya sama persis — satu tekan, `UserInputService` yang mengikuti ke mana pun
penunjuknya pergi, satu scope per geseran — yang berbeda cuma arti sebuah titik. Untuk
sesuatu yang nilainya sebuah **tempat**, bukan sebuah **kadar**: pad, kotak warna, penanda
minimap. Sumbu yang ukurannya nol menyumbang `0` pada sumbu itu saja.

**Kenapa helper ini harus ada.** `GuiObject.InputEnded` hanya menyala selama penunjuk masih
di atas instance-nya, dan geseran meninggalkan knob dalam dua puluh piksel pertama. Geseran
yang diakhiri oleh `Release` milik knob sendiri **tidak akan pernah berakhir**.
`UserInputService.InputEnded` menyala di mana pun penunjuknya berada.

**Pisahkan `onMove` dan `onCommit` kalau harganya beda.** Satu geseran memicu `onMove`
ratusan kali dan `onCommit` sekali. Slider volume mau setiap gerakan, karena pemain sedang
mendengarkan. Seek yang memuat ulang hanya mau nilai terakhir.

---

## `Widgets:Report` — kenapa widgetku tidak tersambung

```luau
local laporan = unrest.Widgets:Report()
```

Laporan, **bukan peringatan**: tidak ada satu pun barisnya yang dicetak. Datanya sudah ada di
pembukuan resep; yang baru cuma menyusunnya, plus hal yang selama ini didiamkan — grup yang
tidak pernah lengkap, dan sebabnya.

`Report().Groups` berisi satu entri per pasangan (resep, grup):

| Field | Arti |
| --- | --- |
| `Group` | Nilai `UnrestGroup`-nya. |
| `Root` | Akar grup, atau `nil` kalau setiap bagian menyetel grupnya sendiri. |
| `Widget` | `UnrestWidget` di akar, kalau ada. |
| `Channel` | `UnrestChannel` di akar, kalau ada: ke mana nilainya diterbitkan saat commit, dan channel yang diikuti saat idle. |
| `Command` | `UnrestCommand` di akar, kalau ada: yang di-`Dispatch` saat commit. |
| `Recipe` | Nama resep: `Widget`-nya, atau `"Each #N"` — N adalah urutan pendaftaran `Each`, tetap sama sepanjang umur library. |
| `Present` | Peran yang sedang dipegang, terurut. |
| `Missing` | Peran wajib yang belum ada, terurut. |
| `Duplicates` | `{ Role, Kept, Ignored }` — instance kedua yang diabaikan karena perannya sudah terisi. |
| `Live` | `true` kalau `OnReady` grup ini sedang berjalan. |

`Report().Orphans` berisi elemen yang memegang peran yang diminta sebuah resep tapi tidak bisa
masuk grup mana pun, dengan `Reason` apa adanya: kalimat yang sama dengan peringatan "peran
tanpa grup", `outside PlayerGui`, atau `root plays X, recipe wants Y`.

Urutannya tetap: resep sesuai urutan pendaftaran, grup terurut nama, setiap daftar peran
terurut. Dua panggilan atas layar yang sama menghasilkan teks yang sama.

---

## `Widgets:Explain` — satu grup, satu kalimat

```luau
print(unrest.Widgets:Explain("Musik"))
```

Satu baris per resep yang mengenal grup itu:

```
[Unrest.Widgets] group "Musik" is a complete Slider and is wired.
[Unrest.Widgets] group "Musik" follows the channel "Volume.Musik" and publishes to it on commit.
[Unrest.Widgets] group "Efek" is not a complete Slider: missing SliderFill.
[Unrest.Widgets] group "Efek" is not a complete Slider: SliderKnob is a Frame, needs a GuiObject.
[Unrest.Widgets] group "Efek" has no shared root: every part sets its own UnrestGroup, so it cannot carry UnrestWidget.
[Unrest.Widgets] no recipe has seen a group "Efekk".
```

Baris channel/perintah muncul kalau akar grup itu membawa `UnrestChannel` atau
`UnrestCommand` — jawaban untuk "kenapa geseranku tidak sampai ke mana-mana", yang ditulis di
instance yang jarang dilihat orang.

Kalimat kelasnya cuma muncul untuk resep ber-`Widget`, karena kelas adalah urusan skema;
runtime merakit lewat peran dan tidak pernah menolak bagian karena kelasnya — justru itu yang
membuat kalimatnya berguna. Kalimat-kalimat ini juga yang akan dipakai lint di Studio, supaya
temuan saat mendesain dan Output saat Play tidak menceritakan satu layar dengan dua cara.

Keduanya **client saja**, sama seperti `Each`.

---

## `Widgets:Destroy`

Membongkar semuanya: semua resep, semua widget yang tersambung, dan query bersamanya.
Jarang dipakai — biasanya kamu ingin `:Destroy()` pada handle dari satu `Each`.

Control-nya **tetap terdaftar** — mendaftar itu fakta tentang library, bukan tentang sebuah
layar — tapi semua yang mereka jalankan ikut hilang, termasuk nilai per grup dan config dari
`Use`. Panggilan berikutnya ke library membangun resepnya lagi dari nol.

---

## Contoh lengkap

Sebuah fitur game yang memakai dua control bawaan sekaligus. Bentuknya selalu sama: aksi
dikunci per `UnrestGroup`, jadi menambah kontrol di Studio tidak pernah menyunting handler
yang sudah ada, dan nama channel tetap di sini, di kode game.

```luau
local Vocab = require(script.Parent.Vocab) -- dihasilkan Tooling/Vocab dari place

return function(unrest: Types.Unrest): ()
    unrest.Widgets:Use(Vocab.Widgets.Slider, {
        [Vocab.Groups.Musik] = {
            Initial = 0.5,
            OnChange = function(fraction: number)
                unrest.Bridge:Publish("Volume.Musik", math.round(fraction * 100))
            end,
        },
        [Vocab.Groups.Efek] = {
            OnCommit = function(fraction: number)
                unrest.Bridge:Publish("Volume.Efek", math.round(fraction * 100))
            end,
        },
    })

    unrest.Widgets:Use(Vocab.Widgets.Toggle, {
        [Vocab.Groups.Fullscreen] = {
            Initial = true,
            OnChange = function(nilai: boolean)
                unrest.Bridge:Publish("Toggle.Fullscreen", nilai)
            end,
        },
        [Vocab.Groups.Notifikasi] = {
            OnChange = function(nilai: boolean)
                unrest.Bridge:Publish("Toggle.Notifikasi", nilai)
            end,
        },
    })
end
```

Slider yang grupnya tidak disebut tetap di-mount dan tetap bisa digeser; dia hanya tidak
menerbitkan apa pun, karena tidak ada yang bilang nilainya berarti apa. Benih layarnya ada di
`studio/BuildSliderMulti.luau` dan `studio/BuildToggle.luau`.

---

## `WidgetSpec<Vocab.Role>` — nama peran yang diperiksa

`WidgetSpec` punya satu parameter tipe opsional, `Role`, yang bawaannya `string`. Ditulis
tanpa argumen, artinya persis seperti sebelumnya, dan `Widgets:Each` tetap menerima bentuk
bawaan itu. Yang mau nama perannya diperiksa terhadap union `Vocab.Role` mengisinya:

```luau
local REQUIRED: { Vocab.Role } = { "SliderTrack", "SliderKnob" }
local OPTIONAL: { Vocab.Role } = { "SliderFill", "SliderLabel" }

local SLIDER: Types.WidgetSpec<Vocab.Role> = {
    Required = REQUIRED,
    Optional = OPTIONAL,
    OnReady = function(group, parts, scope) end,
}
```

`"SilderKnob"` di salah satu daftar itu adalah error `--!strict` di baris deklarasinya —
persis mekanisme yang sama dengan
[`Descriptor<Role, Group>`](API-ELEMENTS.md#descriptorrole-group--kalau-kamu-sudah-punya-vocab).

Satu batasan yang harus diketahui sebelum memakainya: **daftar bertipe sempit tidak muat ke
`Each` apa adanya.** Indexer tabel di Luau bersifat invarian, jadi `{ Vocab.Role }` bukan
`{ string }` — bukan subtipe, bukan supertipe — dan itu berlaku sejak sebelum parameter tipe
ini ada. Yang lebar diminta lagi saat menyerahkannya:

```luau
unrest.Widgets:Each({
    Required = { table.unpack(REQUIRED) },
    Optional = { table.unpack(OPTIONAL) },
    OnReady = SLIDER.OnReady,
})
```

Karena itu bentuk generiknya paling berguna untuk **tabel spec yang kamu simpan sendiri** —
satu modul konfigurasi yang mengeja peran untuk beberapa layar — dan bukan untuk pemanggilan
`Each` sekali pakai. Untuk yang sekali pakai, `Vocab.Roles.SliderKnob` sebagai nilai sudah
menangkap salah ketik tanpa satu pun parameter tipe. `Vocab.luau` sendiri dihasilkan ulang
oleh [plugin Studio](PLUGIN.md) atau `studio/ExportVocab.luau` setiap kali kosakata layar
berubah.
