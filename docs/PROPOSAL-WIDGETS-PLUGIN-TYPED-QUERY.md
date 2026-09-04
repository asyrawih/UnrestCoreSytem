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

# Proposal — Widgets Lanjutan, Plugin Studio, dan Query Bertipe

**Status: masih proposal.** Tidak ada satu pun yang dijelaskan di sini sudah ada di `src/`.
Dokumen ini adalah rancangan untuk tiga hal yang saling mengunci: apa yang harus diperoleh
`Unrest.Widgets` berikutnya, sebuah plugin Roblox Studio untuk mengelola tag dan atribut
framework, dan API `Query` yang bisa diketik editor supaya sintaks selector tidak perlu
dihafal.

Dokumen ini juga **menggantikan sebagian** [Proposal Controls v2](PROPOSAL-CONTROLS.md).
Bagian 1.2 mencatat ide mana dari sana yang masih benar, mana yang gugur, dan kenapa. Yang
tidak disebut di sana tetap berlaku seperti ditulis.

Setiap fakta tentang kode hari ini disertai `file:baris`, supaya klaimnya bisa dicek dan
supaya kalau kodenya bergeser, dokumen ini ketahuan basi.

---

## 0. Ringkasan

Tiga permintaan ini sebenarnya satu masalah yang dilihat dari tiga sisi: **framework tahu
apa itu "Slider", tapi pengetahuannya tercecer** — di `ROLES` milik satu file contoh
(`src/game-client/Example/Slider/init.luau:56`), di kepala desainer yang mengetik atribut di
Studio, dan di string yang harus diketik ulang developer setiap kali menulis query. Usulannya
adalah memindahkan pengetahuan itu ke **satu tempat yang bisa dibaca tiga pembaca**: sebuah
modul skema widget murni-data di framework (`src/shared/Widgets/Schemas.luau`) yang dipakai
runtime untuk merakit dan melaporkan (`Widgets:Report()`), dipakai plugin untuk memvalidasi
layar di Studio, dan dipakai generator untuk menghasilkan `Vocab.luau` — file bertipe yang
membuat `Vocab.Roles.SliderKnob` ter-autocomplete dan `Vocab.Roles.SilderKnob` jadi error
`--!strict`. Plugin tidak membawa salinan aturan apa pun: dia meng-`require` `Constants`,
`Selector`, `Adapters`, dan `Schemas` dari tempat yang sedang dibuka, sehingga tidak bisa
menyimpang dari runtime. Typed builder ditolak, union kelas ditolak, `UnrestControl` diganti
`UnrestWidget`, `UnrestPart` dan `UnrestValue` gugur, dan library control bawaan dipangkas
jadi dua yang sudah terbukti (Slider, Toggle) plus Progress sebagai Slider tanpa input.

---

## 1. Widgets

### 1.1 Yang ada hari ini

`Unrest.Widgets` adalah satu file, `src/shared/Widgets/init.luau`, dan sudah menyelesaikan
pembukuan yang membuat Proposal Controls v2 kelihatan mahal:

- **Satu query bersama** di atas tag (`{ Tag = tag }`, `Widgets/init.luau:367`), semua resep
  `Each` mendaftar ke sana (`:405-413`). Resep menyimpan `Found` (bagian yang terkumpul) dan
  `Live` (scope grup yang sudah lengkap), keduanya dikunci per `UnrestGroup` (`:72-79`).
- **`settle` / `unsettle`** (`:157-182`): grup jadi widget begitu semua `Required` ada, dan
  dibongkar lewat scope-nya begitu satu yang wajib pergi.
- **Pengawas identitas per elemen** (`follow` / `unfollow` / `rekey`, `:261-356`): perubahan
  `UnrestRole`, `Name`, `UnrestGroup`, `UnrestPreset` di elemen maupun di rantai leluhurnya,
  plus `AncestryChanged`, memindahkan elemen antar slot. Hanya perubahan nyata yang
  menggerakkan sesuatu (`:277-280`).
- **Hanya `PlayerGui`** (`screen()`, `:147-154`), supaya templat di `StarterGui` tidak
  merebut grup.
- **`Drag`** (`:471-543`) dibangun di atas `UserInputService.InputChanged/InputEnded`, bukan
  `Press`/`Release`, dengan penjaga lebar nol (`:497-499`). Hanya sumbu X (`:500`, `:516`,
  `:524`).
- **Dua peringatan**: peran tanpa `UnrestGroup` (`:195-199`) dan peran ganda dalam satu grup
  (`:219-224`). Grup yang **tidak pernah lengkap** diam total: `settle` hanya `return`
  (`:161-165`). Ini lubang diagnostik terbesar hari ini, dan
  [Pemecahan Masalah](TROUBLESHOOTING.md) sudah harus menulis "empat pemeriksaan" untuk
  menutupinya secara manual.

Dua konsumennya, `Example/Slider/init.luau` dan `Example/Toggle/init.luau`, memperlihatkan
apa yang belum dipunyai lapisan ini:

- Slider **mulai dari nol dan menerbitkan pada setiap pembangunan ulang**: `paint(0)` di
  `Slider/init.luau:110` dan `Bridge:Publish` di `:105` dipanggil di dalam `paint`. Layar yang
  dibangun ulang mengembalikan volume ke 0 dan menyiarkannya ke seluruh game.
- Toggle sudah punya `Initial` (`Toggle/init.luau:60`, `:91`), tapi state-nya hidup di dalam
  closure `onReady` sehingga ikut hilang saat scope dibongkar.
- Keduanya mengetik daftar peran sebagai string harfiah (`Slider:56`, `Toggle:46-47`), dan
  tidak ada yang memverifikasi bahwa layar di Studio memakai string yang sama.
- Slider menyebut nama channel game (`Volume.{group}`, `Slider:105`). Ini benar untuk kode
  game, dan **menjadi salah** begitu Slider dipindah ke framework (lihat 1.3).

Tipe publiknya ada di `src/shared/Types.luau:155-204`: `WidgetParts`, `WidgetSpec`
(`Required`, `Optional`, `OnReady`), `WidgetHandle` (`Destroy` saja), `WidgetLibrary` (`Each`,
`Drag`, `Destroy`).

### 1.2 Apa yang masih benar dari Proposal Controls v2, dan apa yang gugur

| Ide di v2 | Keputusan | Sebabnya |
| --- | --- | --- |
| `UnrestControl = "Slider"` di akar | **Diterima, diganti nama jadi `UnrestWidget`** | Lapisannya sudah bernama `Widgets`. Dua nama untuk satu benda adalah ongkos konsep tanpa pengembalian. Perannya juga menyempit: identitas dan skema, bukan kepemilikan perilaku (1.4). |
| `UnrestPart` sebagai identitas bagian, terpisah dari `UnrestRole` | **Ditolak** | `Widgets` sudah mengunci bagian lewat `UnrestRole` dan sudah membayar pengawasnya (`Widgets/init.luau:307-346`). Argumen v2 bahwa `roleOf` jatuh ke `Name` (`Selector.luau:66-72`) sehingga Frame dekoratif bernama `Fill` jadi kandidat itu benar, tapi jawabannya bukan atribut kedua: dengan peran yang **panjang dan berawalan** (`SliderFill`, bukan `Fill`) tabrakan itu praktis tidak terjadi, dan `Report()` memperlihatkan kalau terjadi. Satu mekanisme identitas, bukan dua. |
| `UnrestValue` (rentang per bagian) | **Ditunda** | Butuh atribut baru, resolusi per bagian, dan interpolasi. Tidak ada satu pun control di 1.3 yang gagal tanpa ini; semuanya bekerja di pecahan 0..1 dan pemetaan ke rentang tampilan adalah urusan `OnChange` pemanggil atau `UnrestFormat`. Dibayar kalau `TabGroup` benar-benar dibangun. |
| `UnrestChannel` + `UnrestCommand` di akar control | **Diterima, Tahap 5, butuh keputusan** | Ini satu-satunya cara slider bisa "nol kode" seperti tombol. Harganya satu `if` di `wireCommand`/`wireChannel` (`Elements/init.luau:426-522`) dan satu nama di `WATCHED` (`:160-170`), persis seperti v2 §12 tulis. Tetap ditahan sampai Tahap 4 terbukti, karena mengubah invariant Elements. |
| `unrest:Control("VolumeDial")` dengan `Get`/`Set`/`Changed` | **Diterima dalam bentuk lain** | Jadi `ControlHandle` yang dikembalikan `Widgets:Use(name, config):Get(group)` (1.4). Sama isinya, tidak menambah pintu baru di singleton. |
| §10.1 sesi geser tidak boleh di atas `Press`/`Release` | **Sudah selesai** | `Widgets:Drag` adalah jawabannya (`Widgets/init.luau:454-470`). |
| §10.2 kepemilikan lukisan selama menggeser | **Masih benar, mengecil** | Bridge hari ini bus lokal (`Types.luau:123-132`), jadi gema publish sinkron, bukan seratus milidetik. Aturannya tetap: selama jari menempel, nilai lokal yang melukis; nilai channel dijepretkan saat lepas. Dibutuhkan hanya di Tahap 5. |
| §10.3 penolakan diam + penghitung penyalahgunaan, §10.4 `RateLimit` / `Constants.Limits` / ember bersama | **Gugur** | Tidak ada satu pun dari nama-nama itu di `src/` hari ini (`grep RateLimit\|Limits` kosong; `Constants.luau` hanya `Version`, `Tag`, `Attributes`, `Inheritable`). Semuanya milik lapisan jaringan yang sudah dicabut. Ini **drift** yang harus dicatat: bagian 10.3–10.4 v2 menjelaskan kode yang tidak ada. |
| §12 preset bocor ke bagian lewat pewarisan `UnrestPreset` | **Masih benar** | `UnrestPreset` ada di `Constants.Inheritable` (`Constants.luau:98-102`). Aturan yang diambil: `UnrestWidget` **tidak** inheritable, dan preset **tidak boleh** memuat `UnrestWidget` — `Presets.Register` menolaknya (perluasan kecil `Presets.luau:83-91`). |
| §9 `Controls:Validate(screenGui)` | **Diterima, jadi dua** | `Widgets:Report()` untuk runtime dan `Tooling/Lint` untuk Studio (bagian 2), keduanya memakai `Schemas.check` yang sama. |
| Katalog satu entri (`Slider`; `ProgressBar` = Slider tanpa input) | **Diterima, ditambah `Toggle`** | Pertanyaan terbuka v2 nomor 4 dijawab: `Toggle` layak karena **sudah ditulis dan sudah jalan** (`Example/Toggle/init.luau`), jadi memindahkannya ke framework biayanya nol konsep. |

### 1.3 Kandidat, diterima atau ditolak

Kolom "Tempat" menjawab pertanyaan yang diminta: apakah fitur ini milik framework
(`src/shared`) atau milik kode game (`src/game-*`).

| Kandidat | Keputusan | Tempat | Alasan |
| --- | --- | --- | --- |
| Library control bawaan: **Slider, Toggle, Progress** | **Diterima** | framework, `src/shared/Widgets/Controls/` | Keduanya sudah ada dan terbukti; Progress adalah skema Slider dengan `SliderKnob` opsional dan tanpa `Drag`. Syarat mutlak: control bawaan **tidak pernah menyebut nama channel atau perintah** (CONVENTIONS: "Game names do not live there"). Dia melukis, memanggil `OnChange`/`OnCommit`, dan di Tahap 5 membaca atribut akarnya. `Volume.{group}` di `Slider:105` pindah ke config game. |
| **Modal** | **Ditolak** | game, atributnya | Satu Frame dengan `UnrestChannel` + `UnrestBind = "Visible"` sudah modal. Tidak ada beberapa bagian yang saling terkait. |
| **Stepper** | **Ditolak** | game, atributnya | Dua `TextButton` dengan `UnrestCommand` + `UnrestPayload` (`+1`/`-1`) dan satu label ber-`UnrestChannel`. Sama seperti argumen v2 §2 tentang Low/Medium/High. |
| **Tabs / TabGroup** | **Ditunda** | — | Butuh "tombol ini memilih panel itu", yaitu `UnrestValue`. Dibayar bersama, atau tidak sama sekali. |
| **List / Scroll** (isi dari data) | **Ditolak keras** | game | Mengisi daftar berarti meng-clone templat, yaitu framework **membuat UI**. Itu tesis yang dilanggar, bukan fitur yang kurang. `ScrollingFrame` sudah punya adapter dan `Changed` (`CanvasPosition`); sisanya urusan game. |
| **Dropdown** | **Ditunda** | — | Setengahnya List (clone item). Kalau item-nya dibuat di Studio, dia Toggle + Modal yang sudah bisa. |
| **`Initial` / state per grup** | **Diterima** | framework (Controls) | State hidup di **resep**, bukan di closure `OnReady`: `values: { [group]: number }` di control bertahan melewati pembangunan ulang scope. Seed dari `config.Initial`, atau dari `Bridge:Peek(channel)` di Tahap 5. Ini memperbaiki `paint(0)` dan publish-saat-rebuild di `Slider:105-110`. Aturannya: **control menerbitkan hanya perubahan pengguna**, tidak pernah saat mount. |
| **Nilai terikat ke channel secara deklaratif** | **Diterima, Tahap 5, butuh keputusan** | framework | `UnrestChannel`/`UnrestCommand` di akar `UnrestWidget`. Lihat 1.2 dan 6. |
| **Navigasi keyboard / gamepad** | **Ditolak untuk sekarang** | — | Roblox sudah punya `Selectable`, `NextSelectionLeft/Right`, `GuiService.SelectedObject`. Yang belum ada dan nanti mungkin layak: `Widgets:Nudge(handle, track, step)` supaya Slider bisa digerakkan D-pad. Bukan sekarang. |
| **Drag sumbu Y dan 2D** | **Diterima** | framework | `DragOptions = { Axis = "X" \| "Y", Invert = boolean }` pada `Drag`, plus `Drag2D` terpisah yang menyerahkan `Vector2`. Slider vertikal hampir selalu `Invert = true` (bawah = 0). Ukuran S; `fractionAt` (`Widgets/init.luau:489-501`) tinggal diparametrisasi. |
| **`UnrestWidget = "Slider"` di akar** | **Diterima, inti proposal** | framework | Satu atribut di akar menamai skema. Runtime memakainya untuk `Report`, untuk memilih grup mana milik resep mana (`WidgetSpec.Widget`), dan di Tahap 4 untuk mount otomatis control bawaan. Plugin memakainya untuk memvalidasi kelengkapan. **Peran tetap ditulis penuh** (`SliderTrack`, bukan `Track`): peran pendek yang di-namespace oleh widget adalah `UnrestPart` menyamar, dan sudah ditolak di 1.2. |
| **`Widgets:Report()`** | **Diterima** | framework | Datanya sudah ada: `recipe.Found`, `recipe.Live` (`Widgets/init.luau:77-78`). Yang baru hanya menyusunnya, plus **grup yang tidak pernah lengkap dan kenapa** — hal yang hari ini diam. |
| **`Widgets:Get(group)`** | **Diterima sebagai `handle:Get(group)`** | framework | Bagian itu milik resep, bukan milik pustaka: dua resep bisa memegang grup yang sama. Jadi accessor-nya di `WidgetHandle`, ditambah `handle:Groups()`. |
| **`Widgets:Once`** | **Ditolak** | — | `Destroy` dari dalam `OnReady` menghancurkan scope yang baru saja diserahkan (`Live[group]` diisi sebelum `OnReady` dipanggil, `Widgets/init.luau:167-170`), jadi "sekali" tidak punya semantik yang aman. Yang mau sekali pakai `handle:Get(group)` setelah `Each`. |
| **Uji tanpa Studio** | **Diterima sebagian** | repo | Pisahkan yang murni: `Schemas.check(parts, schema)` dan `Tooling/Vocab.generate` bekerja di atas tabel, bukan Instance, sehingga bisa diuji di Luau polos. Perilaku (`Each`, `Drag`, cascade) tetap diuji di Studio lewat skrip `studio/` yang dijalankan MCP. **Tidak** menambah test runner di proposal ini (keputusan terbuka 10). |

### 1.4 Desain API

Semua di bawah ini adalah sketsa tipe, bukan implementasi.

**Konstanta.** Satu nama baru, tidak inheritable:

```luau
-- src/shared/Constants.luau, di Attributes
--- Names the widget schema the subtree under this instance plays: "Slider", "Toggle".
--- Identity for the root only; never inherited, and a preset may not supply it.
Widget = "UnrestWidget",
```

**Skema.** Modul murni-data, tanpa `require` layanan, supaya bisa di-`require` plugin di mode
edit dan diuji di Luau polos:

```luau
-- src/shared/Widgets/Schemas.luau
export type WidgetSchema = {
    Name: string,
    Required: { string },
    Optional: { string }?,
    --- Kelas minimum per peran, diuji dengan :IsA(). Opsional; dipakai Report, Lint, plugin.
    Classes: { [string]: string }?,
}

export type SchemaCheck = {
    Missing: { string },
    Extra: { string },
    WrongClass: { { Role: string, Expected: string, Got: string } },
}

Schemas.Get: (name: string) -> WidgetSchema?
Schemas.List: () -> { string }
--- Mengikuti Presets.Register: game boleh mendaftarkan skemanya sendiri saat startup.
Schemas.Register: (schema: WidgetSchema) -> WidgetSchema
--- Murni: terima peran yang ada (dan kelasnya), kembalikan yang kurang/lebih/salah kelas.
Schemas.check: (present: { [string]: string? }, schema: WidgetSchema) -> SchemaCheck
```

Isi awalnya tiga entri, diturunkan langsung dari yang ada di contoh:

| Skema | Required | Optional | Classes |
| --- | --- | --- | --- |
| `Slider` | `SliderTrack`, `SliderKnob` | `SliderFill`, `SliderLabel` | `SliderTrack: GuiObject`, `SliderKnob: GuiObject` |
| `Progress` | `SliderTrack`, `SliderFill` | `SliderLabel` | — |
| `Toggle` | `ToggleButton`, `ToggleKnob` | `ToggleLabel` | `ToggleButton: GuiButton` |

`Slider` mewajibkan lebih sedikit daripada `ROLES` di `Slider:56` hari ini (empat wajib).
Itu disengaja dan sejalan dengan v2 §7: fill dan label yang absen itu sah dan diam.

**Tipe widget** (`src/shared/Types.luau`, semua perubahan aditif):

```luau
export type WidgetSpec = {
    Required: { string },
    Optional: { string }?,
    --- Bila diisi: hanya grup yang akarnya ber-UnrestWidget = nilai ini yang diterima, dan
    --- Required/Optional boleh dikosongkan karena diambil dari Schemas.Get(nilai ini).
    Widget: string?,
    OnReady: (group: string, parts: WidgetParts, scope: Scope) -> (),
}

export type WidgetHandle = {
    Destroy: (self: WidgetHandle) -> (),
    --- Bagian sebuah grup yang sedang lengkap, atau nil.
    Get: (self: WidgetHandle, group: string) -> WidgetParts?,
    Groups: (self: WidgetHandle) -> { string },
}

export type DragOptions = { Axis: ("X" | "Y")?, Invert: boolean? }

export type WidgetGroupReport = {
    Group: string,
    Root: Instance?,          -- penyedia UnrestGroup terdekat
    Widget: string?,          -- UnrestWidget di akar, kalau ada
    Recipe: string,           -- nama control, atau "Each" ke-N
    Present: { string },
    Missing: { string },
    Duplicates: { { Role: string, Kept: Instance, Ignored: Instance } },
    Live: boolean,
}
export type WidgetReport = {
    Groups: { WidgetGroupReport },
    --- Elemen berperan yang tidak bisa masuk grup mana pun, dan sebabnya.
    Orphans: { { Instance: Instance, Role: string, Reason: string } },
}

export type ControlHandle = {
    Get: (self: ControlHandle) -> any,
    --- Melukis tanpa memanggil OnChange; untuk state yang datang dari luar.
    Set: (self: ControlHandle, value: any) -> (),
    --- Hanya perubahan pengguna, bukan gema Set.
    Changed: Signal<any>,
}
export type Control<Config> = {
    Name: string,
    Schema: WidgetSchema,
    Mount: (unrest: Unrest, group: string, parts: WidgetParts, scope: Scope, config: Config?) -> ControlHandle,
}

export type WidgetLibrary = {
    Each: (self: WidgetLibrary, spec: WidgetSpec) -> WidgetHandle,
    Drag: (self, scope, handle, track, onMove, onCommit?, options: DragOptions?) -> Scope,
    Drag2D: (self, scope, handle, track, onMove: (Vector2) -> (), onCommit: ((Vector2) -> ())?) -> Scope,
    --- Tahap 4. Control terdaftar di-mount otomatis untuk setiap akar ber-UnrestWidget = Name.
    Register: (self: WidgetLibrary, control: Control<any>) -> (),
    --- Tahap 4. Config per grup untuk control terdaftar; handle-nya mengembalikan ControlHandle.
    Use: (self: WidgetLibrary, name: string, config: { [string]: any }?) -> WidgetHandle,
    Report: (self: WidgetLibrary) -> WidgetReport,
    --- Satu kalimat per grup, gaya Elements.describe. Untuk Output dan untuk MCP.
    Explain: (self: WidgetLibrary, group: string) -> string,
    Destroy: (self: WidgetLibrary) -> (),
}
```

**Akar sebuah grup** didefinisikan dari resolusi yang sudah ada, bukan dari aturan baru:
akar adalah penyedia `UnrestGroup` terdekat menurut
`Selector.inheritedProviders(element, { UnrestGroup })` (`Selector.luau:213-225`), atau
elemen itu sendiri kalau dia menyetel grupnya sendiri. Grup yang setiap bagiannya menyetel
`UnrestGroup` masing-masing **tidak punya akar**, sehingga tidak bisa ber-`UnrestWidget`;
`Report` mengatakannya, plugin memperbaikinya dengan satu klik ("pindahkan grup ke induk
bersama"). Pengawasan `UnrestWidget` di rantai leluhur **gratis**: tinggal menambah nama ke
`GROUP_INPUTS` (`Widgets/init.luau:101`) yang sudah dipasang `bindChain` ke setiap leluhur.

**Control bawaan** hidup di `src/shared/Widgets/Controls/Slider.luau` dan `Toggle.luau`,
masing-masing mengekspor `Control<SliderConfig>` / `Control<ToggleConfig>` dan didaftarkan
oleh `Widgets.new`. Config-nya adalah `Actions` yang hari ini ada di contoh, tanpa nama
channel:

```luau
export type SliderConfig = {
    Initial: number?,                       -- pecahan 0..1
    OnChange: ((fraction: number) -> ())?,
    OnCommit: ((fraction: number) -> ())?,
}
```

`src/game-client/Example/Slider/init.luau` menyusut jadi pemanggil `Widgets:Use("Slider",
{...})` yang di dalam `OnChange` memanggil `Bridge:Publish("Volume." .. group, ...)`. Nama
channel tetap di game, tempat yang benar.

**Semantik `Use` dan mount otomatis.** Control terdaftar di-mount untuk setiap grup yang
akarnya ber-`UnrestWidget = control.Name` dan lengkap menurut skema, **dipanggil atau tidak
`Use`**; `Use` hanya memasok config per grup. `Each` polos (tanpa `Widget`) tidak berubah
sama sekali dan tidak pernah bentrok dengan control bawaan, karena control hanya menyentuh
grup yang **mendeklarasikan** dirinya.

### 1.5 File yang tersentuh

| File | Perubahan | Ukuran |
| --- | --- | --- |
| `src/shared/Constants.luau` | `Attributes.Widget` | S |
| `src/shared/Presets.luau` | tolak `UnrestWidget` di dalam preset (`:83-91`) | S |
| `src/shared/Widgets/Schemas.luau` | **baru**, murni data + `check` | S |
| `src/shared/Types.luau` | tipe di 1.4 | S |
| `src/shared/Widgets/init.luau` | `Widget` di spec, akar grup, `Get/Groups`, `Report`, `Explain`, `DragOptions`, `Drag2D`, `Register/Use` | M (Tahap 1) + M (Tahap 4) |
| `src/shared/Widgets/Controls/Slider.luau`, `Toggle.luau` | **baru**, dipindah dari contoh, tanpa nama channel | M |
| `src/game-client/Example/Slider/init.luau`, `Toggle/init.luau` | menyusut jadi config | S |
| `src/shared/Elements/init.luau` | **hanya Tahap 5**: satu `if` di `wireCommand`/`wireChannel`, `UnrestWidget` di `WATCHED` | S, mahal ditelaah |
| `docs/API-WIDGETS.md`, `docs/UI-ATTRIBUTES.md`, `docs/TROUBLESHOOTING.md`, `docs/API-OVERVIEW.md` | atribut baru, `Report`, control bawaan; perbaiki jalur `src/game-client/Slider.luau` yang sudah basi | S |

---

## 2. Plugin Roblox Studio

### 2.1 Tujuan, dan yang sengaja tidak dibangun

Masalahnya: mengelola tag dan atribut `Unrest*` lewat panel Properties Studio berarti
mengetik string yang tidak ada yang memeriksa, di tempat yang tidak memperlihatkan hasilnya.
Plugin ini adalah **panel Properties yang tahu framework**: dia memperlihatkan apa yang
runtime akan simpulkan tentang instance yang dipilih, sebelum Play ditekan.

Yang **tidak** dibangun, supaya cakupannya jelas:

- **Tidak membuat UI.** Plugin tidak punya tombol "buat slider". Skrip benih di `studio/`
  tetap jadi cara membuat contoh; plugin bekerja di atas instance yang sudah ada.
- **Tidak membawa salinan aturan.** Tidak ada daftar atribut, daftar kelas, atau aturan
  cascade di dalam plugin. Semuanya di-`require` dari framework di tempat yang dibuka (2.5).
- **Tidak membaca state runtime.** `require` dari plugin menghasilkan salinan modul sendiri,
  bukan singleton yang dijalankan game, jadi plugin tidak bisa melihat `Widgets` yang hidup.
  Diagnostik runtime adalah `Widgets:Report()` lewat Command Bar atau MCP, bukan plugin.
- **Tidak menyentuh jaringan.** Tidak ada `HttpService`, tidak ada telemetri.

### 2.2 Arsitektur

```
plugin/
  default.project.json        -- proyek Rojo sendiri; TIDAK pernah masuk default.project.json
  src/
    init.server.luau          -- akar Script: toolbar, DockWidget, seleksi, undo
    Framework.luau            -- menemukan ReplicatedStorage.Unrest, feature-detect modul
    Panels/
      Inspector.luau
      Outline.luau
      Problems.luau
      Widgets.luau
      Export.luau
    Ui/                       -- widget plugin sendiri (dibangun kode; ini plugin, bukan game)
```

`Framework.luau` adalah satu-satunya tempat plugin tahu di mana framework berada:

```luau
export type Framework = {
    Version: string,
    Constants: typeof(require(Unrest.Constants)),
    Selector: typeof(require(Unrest.Adapters.Selector)),
    Adapters: Types.AdapterRegistry,           -- Adapters.new(), murni
    Schemas: typeof(require(Unrest.Widgets.Schemas))?,   -- nil pada framework lama
    Lint: typeof(require(Unrest.Tooling.Lint))?,
    Vocab: typeof(require(Unrest.Tooling.Vocab))?,
}
Framework.find: () -> Framework?     -- nil bila tempat ini tidak memakai Unrest
```

Modul yang di-`require` plugin harus **murni di waktu require**: `Constants`, `Selector`
(hanya `CollectionService`, `Selector.luau:51`), `Presets`, `Resolver`, `Types`, `Adapters`,
`Schemas`, `Tooling/*`. Plugin **tidak pernah** meng-`require` `Widgets/init.luau`,
`Elements/init.luau`, atau `Unrest/init.luau`: yang pertama memegang `Players` dan
`UserInputService` di puncak file (`Widgets/init.luau:59-60`), dan yang terakhir merakit
singleton (`init.luau:68-72`). Ini batas yang harus ditulis di header `Tooling/`.

Versi framework yang lebih tua dari yang plugin kenal cukup **mematikan panel** yang
modulnya tidak ada (`Schemas` nil berarti panel Widgets menampilkan "framework ini belum
punya skema; perbarui ke 0.3"), bukan gagal total.

### 2.3 Panel

Satu DockWidget dengan lima tab. Semua bekerja di atas `Selection` dan memakai
`ChangeHistoryService` supaya setiap suntingan bisa di-undo, seperti `studio/BuildUnrestUI.luau`
sudah lakukan.

**Inspector** — untuk instance yang dipilih:

| Baris | Sumbernya |
| --- | --- |
| Dikelola? Lewat tag sendiri, cascade dari `X`, atau diblokir `UnrestIgnore` di `Y` | `Selector.isManaged`, jalan ke atas dengan `HasTag`/`isIgnored` (`Selector.luau:409-430`, `:460-471`) |
| Adapter dan kemampuannya, satu kalimat | `Adapters:Describe(instance)` (`Adapters/init.luau:306-319`) |
| Setiap atribut `Unrest*` yang teresolusi, nilainya, dan **dari mana** (`set here` / `from preset` / `inherited from`) | `Selector.resolution` + `Selector.attributeIn` per nama di `Constants.Attributes` (`Selector.luau:259-352`); teks asalnya sudah dibuat di sana (`:176-193`) |
| Editor per atribut: dropdown peran/grup/widget yang diisi dari nilai yang **sudah ada di tempat ini** dan dari `Schemas`; `UnrestBind` hanya menawarkan `Bindable` adapter-nya | `Adapters:Resolve(instance).Bindable`; pemindaian `StarterGui` |
| Tombol: tag / lepas tag, `UnrestIgnore` on/off | `CollectionService` |

Ini `Elements.describe` (`Elements/init.luau:356-374`) yang dipindah ke mode edit — jawaban
yang sama, dari fungsi yang sama.

**Outline** — pohon yang dikelola, bukan pohon Explorer: setiap akar bertag dan semua yang
dijangkau cascade-nya (`Selector.cascadeUnder`, `Selector.luau:539-578`), dikelompokkan per
`ScreenGui`. Lencana per baris: peran, grup, widget, dan atribut wiring. Gerbang
`UnrestIgnore` dan subtree yang dipangkasnya ditampilkan redup. Filter per grup / peran.
Klik memilih di Explorer.

**Problems** — daftar dari `Tooling/Lint` (2.4), tiap baris: tingkat, instance, kalimat
yang **sama** dengan peringatan runtime, dan tombol perbaikan bila perbaikannya satu
suntingan. Ada tombol "Periksa ulang"; pemindaian otomatis pada `Selection` yang berubah dan
pada `DescendantAdded` di `StarterGui` dengan debounce, karena `Lint` memindai seluruh
`StarterGui`.

**Widgets** — tabel per `UnrestGroup`: widget yang dideklarasikan, peran yang ada, kurang,
lebih, ganda, salah kelas — dari `Schemas.check`. Aksi: "jadikan seleksi peran X" (menyetel
`UnrestRole` pada instance yang dipilih, dengan dropdown peran dari skema) dan "pindahkan
`UnrestGroup` ke induk bersama".

**Export** — menjalankan `Tooling/Vocab.generate(StarterGui)` dan menampilkan hasilnya (2.8).

### 2.4 Validasi

Semua aturan hidup di `src/shared/Tooling/Lint.luau`, murni, dan mengembalikan tabel
temuan; plugin hanya menggambar. Kalimatnya disalin **dari** peringatan runtime, bukan
ditulis ulang, sehingga apa yang plugin katakan di mode edit adalah apa yang Output katakan
saat Play.

```luau
export type Finding = {
    Level: "Error" | "Warning" | "Info",
    Code: string,               -- "WidgetIncomplete", "RoleWithoutGroup", ...
    Instance: Instance,
    Message: string,
    --- Satu suntingan yang memperbaikinya, bila ada. Plugin menjalankannya di ChangeHistory.
    Fix: (() -> ())?,
}
Lint.check: (root: Instance, options: { Schemas: boolean?, Sources: boolean? }?) -> { Finding }
```

| Kode | Tingkat | Aturan | Sumber kebenaran |
| --- | --- | --- | --- |
| `RoleWithoutGroup` | Warning | Peran yang ada di skema mana pun, tapi `groupOf` nil | `Selector.groupOf`; kalimat `Widgets/init.luau:196-197` |
| `DuplicateRole` | Warning | Dua instance dikelola, peran sama, grup sama, `ScreenGui` sama | `Selector.roleOf`, `groupOf`; kalimat `:220-222` |
| `WidgetUnknown` | Warning | `UnrestWidget` menyebut nama yang tidak ada di `Schemas.List()` | `Schemas`; pola kalimat unknown-preset `Elements/init.luau:308-313` |
| `WidgetIncomplete` | Error | Akar ber-`UnrestWidget`, `Schemas.check` melaporkan `Missing` atau `WrongClass` | `Schemas.check` |
| `WidgetRootIgnored` | Error | Akar ber-`UnrestWidget` di dalam subtree `UnrestIgnore` (v2 §9, baris terakhir) | `Selector.isManaged` |
| `WidgetNoRoot` | Warning | Grup yang setiap bagiannya menyetel `UnrestGroup` sendiri | `Selector.inheritedProviders` |
| `CommandNotActivatable` | Warning | `UnrestCommand` teresolusi tapi `Supports(instance, "Active")` false | `Adapters:Supports`; kalimat `COMMAND_HINT` `Elements/init.luau:155-156` |
| `ChannelNotBindable` | Warning | `UnrestChannel` ada tapi `UnrestBind` tidak `Bindable`, atau tidak ada `Bind` dan tidak ada `ValueProperty` | `Adapters:CanBind`; kalimat `Elements/init.luau:470-484` |
| `IgnoreNotBoolean` | Warning | `UnrestIgnore` bernilai string `"true"`; runtime hanya menerima boolean | `Selector.luau:391-393` |
| `PresetUnknown` | Warning | `UnrestPreset` menyebut nama di luar manifest (2.5); dilewati kalau manifest tidak ada | `Presets.List()` setelah manifest didaftarkan |
| `GroupDuplicatedAcrossScreens` | Warning | Grup yang sama di dua `ScreenGui` di `StarterGui`; saat Play yang datang belakangan dibuang | kalimat `Widgets/init.luau:220-222`; catat bahwa gandaan StarterGui/PlayerGui **bukan** ini dan sudah ditangani `:147-154` |
| `IntentOnContainer` | Info | `UnrestCommand`/`UnrestRole` pada instance yang punya anak `GuiObject` bertag-cascade; keduanya tidak diwariskan, kemungkinan salah tempat | `Constants.Inheritable` |
| `GroupNotIdentifier` | Info | Nama grup/peran bukan identifier Luau; `Vocab` akan memakai kurung siku dan autocomplete jadi canggung | `Tooling/Vocab` |
| `RoleUnusedInCode` / `RoleMissingInPlace` | Info, **perkiraan** | Peran di tempat yang tidak muncul di `Source` skrip mana pun sebagai `Vocab.Roles.X` atau `"X"`, dan sebaliknya | pemindaian `Source` (opsi `Sources = true`, mahal, hanya atas permintaan) |

Dua yang terakhir jujur ditandai perkiraan: plugin tidak bisa tahu query mana yang akan
dibuat kode. Setelah `Vocab.luau` dipakai (bagian 3), pemindaian `Vocab.Roles.X` jadi hampir
pasti, dan peran yang hanya muncul sebagai string harfiah adalah temuan tersendiri.

### 2.5 Sumber kebenaran bersama

| Pengetahuan | Tempat tunggalnya | Pembaca |
| --- | --- | --- |
| Nama atribut, tag, himpunan inheritable | `src/shared/Constants.luau` | runtime, Lint, plugin, Vocab |
| Cascade, resolusi tiga lapis, peran, grup | `src/shared/Adapters/Selector.luau` | runtime, Lint, plugin |
| Kelas, handler, `Bindable` | `src/shared/Adapters/Classes/*` lewat `Adapters.new()` | runtime, Lint, plugin |
| Skema widget bawaan | `src/shared/Widgets/Schemas.luau` | runtime (`Report`, mount), Lint, plugin, Vocab |
| Kalimat peringatan | file runtime yang mengeluarkannya | Lint menyalin, bukan menulis ulang |
| **Skema dan preset milik game** | **manifest game** (di bawah) | runtime dan plugin |

Preset dan skema game didaftarkan saat startup (`Presets.Register`, `Presets.luau:75-95`),
jadi di mode edit tabelnya kosong dan plugin buta. Jalan keluarnya memakai mekanisme yang
sudah jadi tesis framework: **satu `ModuleScript` murni-data yang bertag `UnrestManifest`**,
misalnya `src/game-client/Manifest.luau`:

```luau
return table.freeze({
    Presets = { TombolUtama = { UnrestCommand = "Toko.Beli" } },
    Widgets = { { Name = "Dial", Required = { "DialFace", "DialNeedle" } } },
})
```

Bootstrap game meng-`require`-nya dan memanggil `Presets.Register` / `Schemas.Register` per
entri; plugin mencarinya lewat `CollectionService:GetTagged("UnrestManifest")` dan membaca
tabel yang sama. Satu sumber, dua pembaca, tanpa jalur tetap yang harus disepakati.

### 2.6 Build, pasang, dan rilis

- **Proyek Rojo sendiri**: `plugin/default.project.json` dengan `"tree": { "$path": "plugin/src" }`,
  akar `init.server.luau` supaya `.rbxm`-nya adalah satu `Script` (yang dijalankan Studio)
  beserta modul anaknya. Ini proyek keempat di samping `default`, `bench`, `model`, dan
  seperti `bench` **tidak pernah** dipasang ke `default.project.json` — aturan "UI never
  enters the Rojo tree" dan invariant kemurnian model di CI tetap utuh.
- **Pasang lokal**:
  `rojo build plugin/default.project.json --output "$HOME/Documents/Roblox/Plugins/UnrestPlugin.rbxm"`
  (Windows: `%LOCALAPPDATA%\Roblox\Plugins`). Studio memuat ulang plugin lokal saat filenya
  berubah. Satu target `make plugin` atau skrip `scripts/install-plugin.sh` menutupnya.
- **Toolchain**: tidak ada tool baru; `rojo`, `selene`, `stylua`, `luau-lsp` di `rokit.toml`
  sudah cukup. `luau-lsp analyze` untuk `plugin/` memakai definisi `PluginSecurity` yang
  **sudah** dipakai CONVENTIONS (`globalTypes.PluginSecurity.d.luau`), jadi API `plugin:` dan
  `DockWidgetPluginGui` sudah dikenal checker.
- **CI** (`.github/workflows/ci.yml`): `selene .` dan `stylua --check .` sudah mencakup
  `plugin/`; tambah satu langkah `rojo build plugin/default.project.json --output UnrestPlugin.rbxm`
  dan unggah artefak. `analyze` perlu sourcemap kedua dari `plugin/default.project.json`.
- **Rilis** (`release.yml`): lampirkan `UnrestPlugin.rbxm` di GitHub Release di samping
  `Unrest.rbxm`. Creator Store sebagai *Plugin* (bukan Model) adalah jalur kedua, dengan
  syarat akun yang sama seperti README "Creator Store". Wally **tidak** relevan: Wally
  menyalurkan paket ke tempat, bukan plugin ke Studio.
- **Versi**: plugin membaca `Constants.Version` dari tempat, dan menyimpan versi minimum
  framework yang dia kenal di satu konstanta. Tidak menambah pasangan versi ketiga yang harus
  dijaga tangan.

### 2.7 Hubungan dengan `studio/Build*.luau`

Skrip benih tetap ada dan tetap satu-satunya yang **membuat** instance. Dua perubahan kecil:
`BuildSlider*.luau` dan `BuildToggle.luau` menambah `akar:SetAttribute("UnrestWidget", ...)`
supaya hasilnya lolos `WidgetIncomplete`, dan dua skrip baru menyusul: `studio/LintUnrest.luau`
(memanggil `Tooling/Lint.check(StarterGui)` dan mencetak temuan) dan `studio/ExportVocab.luau`
(mencetak `Tooling/Vocab.generate(StarterGui)`). Keduanya lima baris, dan keduanya adalah
pintu MCP: sesi agen bisa menjalankan lint dan ekspor tanpa plugin terpasang. Plugin, Command
Bar, dan MCP memanggil fungsi yang sama.

### 2.8 Ekspor `Vocab.luau`

Generator adalah fungsi murni di framework, bukan di plugin, supaya tiga pintu di 2.7
memakai satu implementasi:

```luau
-- src/shared/Tooling/Vocab.luau
export type Vocabulary = {
    Roles: { [string]: { string } },     -- peran -> daftar jalur instance yang memakainya
    Groups: { [string]: { string } },
    Widgets: { [string]: { string } },
}
Vocab.collect: (root: Instance) -> Vocabulary          -- memakai Selector.roleOf/groupOf, isManaged
Vocab.render: (vocabulary: Vocabulary, stamp: string) -> string   -- murni, bisa diuji tanpa Instance
Vocab.generate: (root: Instance) -> string
```

Yang dihasilkan hanya **Roles, Groups, Widgets** — kosakata UI yang sepenuhnya ditentukan
tempat. **Channel dan perintah tidak dihasilkan**: yang muncul di atribut hanya sebagian
(kode menerbitkan `Volume.Musik` tanpa satu atribut pun), dan union yang tidak lengkap
membuat `--!strict` menolak kode yang benar. Nama channel milik game dan diketik game.

Tujuannya `src/game-client/Vocab.luau`, di sisi game karena isinya nama game
(keputusan terbuka 4). Cara mendarat ke disk adalah masalah yang harus ditulis jujur, karena
plugin Studio **tidak punya akses berkas**:

| Rute | Status | Catatan |
| --- | --- | --- |
| Panel Export menampilkan teks di `TextBox` untuk disalin | pasti jalan | manual, tapi deterministik, jadi diff-nya bersih |
| Plugin menulis `Source` ke `ModuleScript` di jalur yang di-mount Rojo, dan two-way sync plugin Rojo menyalinnya ke disk | jalan **hanya** kalau two-way sync (eksperimental) dinyalakan | perlu diverifikasi di Rojo 7.7.0 |
| MCP: sesi agen menjalankan `studio/ExportVocab.luau`, menulis hasilnya ke disk | jalan hari ini | ini rute yang paling murah untuk repo ini |
| Lune membaca `.rbxl` dan menulis file, bisa jadi langkah CI "Vocab sudah mutakhir" | jalan, tapi menambah tool ke `rokit.toml` dan mengandalkan `.rbxl` yang tidak di-track | ditunda; keputusan terbuka 5 |

### 2.9 File dan direktori baru

| Jalur | Isi |
| --- | --- |
| `plugin/default.project.json`, `plugin/src/**` | plugin (2.2) |
| `src/shared/Tooling/Lint.luau` | aturan 2.4, murni |
| `src/shared/Tooling/Vocab.luau` | generator 2.8, murni |
| `src/shared/Widgets/Schemas.luau` | skema (1.4) |
| `studio/LintUnrest.luau`, `studio/ExportVocab.luau` | pintu Command Bar / MCP |
| `src/game-client/Manifest.luau` (bertag `UnrestManifest`) | preset dan skema game |
| `src/game-client/Vocab.luau` | **dihasilkan**, header "jangan disunting" |
| `docs/PLUGIN.md` | cara pasang dan tiap panel; `CONVENTIONS.md` dapat satu paragraf tentang `plugin/` dan `Tooling/` yang tidak boleh di-`require` runtime |

---

## 3. Query Bertipe

### 3.1 Masalah yang sebenarnya

"Lupa sintaks selector" adalah tiga masalah yang berbeda ongkosnya:

1. **Bentuk tabelnya** — tujuh kunci opsional (`Adapters/Types.luau:411-426`) dan aturan
   "minimal satu dari lima, `Ancestor` wajib tanpa `Tag`" (`Resolver.luau:200-236`). Ini
   **sudah** dilindungi: parameter `Query` bertipe `Types.Descriptor` (`init.luau:131`), jadi
   luau-lsp menawarkan kuncinya di dalam kurung kurawal dan hover memperlihatkan komentar
   `---` tiap field. Yang salah ketik nama kunci ditangkap `Resolver` dengan "did you mean"
   (`Resolver.luau:147-164`, `:186-188`).
2. **Nama handler** — dua belas kunci `Handlers` (`Adapters/Types.luau:107-243`), sudah
   bertipe dan sudah ter-autocomplete.
3. **Nilainya** — `Role = "SliderKnob"`, `Group = "Musik"`, `Selector = "GuiButton"`. Ini
   yang benar-benar belum dilindungi: `string` menerima apa saja, dan `Role = "SilderKnob"`
   adalah query yang diam-diam tidak pernah cocok. **Di sinilah seluruh nilai proposal ini.**

### 3.2 Opsi

| Opsi | Menyelesaikan | Ongkos | Keputusan |
| --- | --- | --- | --- |
| (a) Builder `unrest.Q.tag("Unrest"):role("SliderKnob"):is("GuiButton")` | masalah 1, yang sudah selesai | subsistem baru; tempat **ketiga** yang mengeja field descriptor (setelah `Types` dan skema `Resolver`); `role("SilderKnob")` tetap lolos karena parameternya `string` | **Ditolak** |
| (b) Union literal untuk `Selector` dan nama handler | handler: sudah ada. Kelas: **tidak bisa** — `Selector` sengaja menerima kelas tanpa adapter (`Folder` dengan `Added`/`Removed`, `Adapters/Types.luau:53-55`), dan `"TextButton" \| string` dinormalisasi Luau menjadi `string` sehingga singleton-nya hilang dari autocomplete | drift antara union tulisan tangan dan `Adapters:List()` | **Ditolak untuk kelas**; handler sudah selesai |
| (c) `Vocab.luau` yang dihasilkan: `export type Role = "SliderKnob" \| ...` plus tabel `Vocab.Roles` | masalah 3, untuk peran, grup, widget | generator (2.8) dan satu file di game yang harus disegarkan | **Diterima, rekomendasi utama** |
| (d) `Selector.explain` dan pesan galat | pertanyaan "kenapa instance ini tidak cocok" — masalah keempat yang tidak disebut, dan yang paling sering ditanya di TROUBLESHOOTING | S, murni, di `Selector` | **Diterima sebagai pelengkap** |

### 3.3 Rekomendasi

Dua lapis, keduanya kompatibel dengan tabel polos:

**Lapis 1 — tabel enum, tanpa perubahan framework.** `Vocab.luau` mengekspor tabel beku
yang nilainya bertipe singleton, sehingga `Vocab.Roles.` ter-autocomplete dan
`Vocab.Roles.SilderKnob` adalah error `--!strict` ("Key 'SilderKnob' not found"). Ini
bekerja **hari ini** dengan `Types.Descriptor` apa adanya, karena `"SliderKnob"` adalah
subtipe `string`.

```luau
--!strict
-- DIHASILKAN oleh Tooling/Vocab dari StarterGui pada 2026-09-04. Jangan disunting; ekspor ulang.
export type Role = "SliderFill" | "SliderKnob" | "SliderLabel" | "SliderTrack" | "ToggleButton" | "ToggleKnob" | "ToggleLabel"
export type Group = "Efek" | "Fullscreen" | "Musik" | "Notifikasi"
export type Widget = "Slider" | "Toggle"

local Vocab = {
    Roles = table.freeze({
        --- SliderMulti.Musik.Track (Frame), SliderMulti.Efek.Track (Frame)
        SliderTrack = "SliderTrack" :: "SliderTrack",
        --- SliderMulti.Musik.Track.Knob (TextButton), SliderMulti.Efek.Track.Knob (TextButton)
        SliderKnob = "SliderKnob" :: "SliderKnob",
        -- ...
    }),
    Groups = table.freeze({ Musik = "Musik" :: "Musik", Efek = "Efek" :: "Efek" --[[ ... ]] }),
    Widgets = table.freeze({ Slider = "Slider" :: "Slider", Toggle = "Toggle" :: "Toggle" }),
}
return table.freeze(Vocab)
```

Komentar `---` di atas tiap entri adalah **jalur instance yang memakainya**, sehingga hover
di editor menjawab "peran ini ada di mana di layar" tanpa membuka Studio. Cast `:: "X"`
wajib, karena literal di konstruktor tabel dilebarkan jadi `string`.

**Lapis 2 — generik opsional di framework, aditif.** Untuk yang ingin string harfiah pun
diperiksa:

```luau
-- src/shared/Adapters/Types.luau
export type Descriptor<Role = string, Group = string> = {
    Tag: string?, Selector: string?, Name: string?,
    Role: Role?, Group: Group?,
    Ancestor: Instance?, Recursive: boolean?,
}
-- src/shared/Types.luau
export type WidgetSpec<Role = string> = { Required: { Role }, Optional: { Role }?, Widget: string?, OnReady: ... }
```

`Types.Descriptor` tanpa argumen tetap berarti `Descriptor<string, string>`, jadi semua kode
yang ada tidak berubah; `Query` tetap menerima yang lebar. Kode game yang mau ketat menulis
`local d: Types.Descriptor<Vocab.Role, Vocab.Group> = { Tag = unrest.Tag, Role = "SilderKnob" }`
dan mendapat error di baris itu. Default parameter tipe didukung solver lama, jadi ini aman
di luau-lsp 1.69.0 yang dipin.

**Pelengkap (d).** `Selector.explain(descriptor, instance): string` yang menjalankan tiap
klausa `matches` (`Selector.luau:719-768`) satu per satu dan mengembalikan
`Tag: ok (cascaded from Panel) · Selector: FAIL — Frame is not a GuiButton · Role: ok ("SliderKnob", set here)`.
Dipakai `unrest.Elements:Explain(descriptor, instance)`, oleh plugin (Inspector, "coba
descriptor"), dan oleh MCP.

### 3.4 Yang diketik developer untuk kasus Slider

Hari ini (`Example/Slider/init.luau:56`, `:86-89`):

```luau
local ROLES = { "SliderTrack", "SliderFill", "SliderKnob", "SliderLabel" }
unrest.Widgets:Each({ Required = ROLES, OnReady = function(group, parts, scope) ... end })
```

Setelah Tahap 2 dan 4, kode game yang menulis reaksinya sendiri:

```luau
local Vocab = require(script.Parent.Parent.Vocab)   -- dihasilkan

unrest.Widgets:Use(Vocab.Widgets.Slider, {
    [Vocab.Groups.Musik] = {
        OnChange = function(fraction: number)
            unrest.Bridge:Publish("Volume.Musik", math.round(fraction * 100))
        end,
    },
})
```

Dan query langsung, untuk yang tidak lewat widget:

```luau
unrest:Query({ Tag = unrest.Tag, Role = Vocab.Roles.SliderKnob }, {
    Hover = function(knob) ... end,
})
```

Apa yang luau-lsp tawarkan, urut saat mengetik:

| Kursor di | Yang muncul |
| --- | --- |
| `unrest:Query({ ` | `Tag`, `Selector`, `Name`, `Role`, `Group`, `Ancestor`, `Recursive`, masing-masing dengan komentar `---` dari `Adapters/Types.luau:412-425` |
| `Role = Vocab.Roles.` | `SliderFill`, `SliderKnob`, `SliderLabel`, `SliderTrack`, `ToggleButton`, ... dengan hover berisi jalur instance |
| `Role = Vocab.Roles.Silder` | garis merah: key tidak ada |
| `}, { ` | dua belas handler dengan komentarnya |
| `Widgets:Use(` | `name: string` — dan dengan Lapis 2, `Vocab.Widget` menawarkan `"Slider" \| "Toggle"` |
| `local d: Types.Descriptor<Vocab.Role, Vocab.Group> = { Role = "` | `"SliderFill"`, `"SliderKnob"`, ... sebagai literal |

### 3.5 Kompatibilitas

- `unrest:Query({ Tag = "Unrest", Role = "SliderKnob" })` dengan string harfiah **tetap sah
  selamanya**. Lapis 1 murni tambahan di sisi game; Lapis 2 default ke `string`.
- `Resolver` tidak berubah: validasi runtime tetap memeriksa bentuk, bukan nilai.
- `Selector.parse`, `CompiledSelector`, `describe` tidak berubah.
- `WidgetSpec` lama (`Required` + `OnReady`) tetap diterima; `Widget` opsional.

### 3.6 Batasan tipe Luau yang menentukan rancangan ini

- `keyof<typeof(T)>` akan menghapus kebutuhan mengetik union dua kali, tapi fungsi tipe
  itu **butuh solver baru**, yang di luau-lsp masih opt-in. Karena itu generator menulis
  union literal **dan** tabelnya secara eksplisit.
- `"A" | string` dinormalisasi jadi `string`; tidak ada trik `string & {}` seperti di
  TypeScript. Karena itu (b) untuk kelas ditolak, bukan ditunda.
- Default parameter tipe (`type T<R = string>`) didukung solver lama; Lapis 2 aman.
- `export type` dari file yang dihasilkan bekerja seperti file biasa; `.luaurc` sudah punya
  alias `GameClient` untuk jalur `require` yang stabil.
- Kunci tabel yang bukan identifier (`["Menu Utama"]`) tetap sah tapi autocomplete-nya
  canggung; `Lint` menandainya (`GroupNotIdentifier`).

---

## 4. Urutan pengerjaan

| Tahap | Isi | Tergantung pada | Ukuran |
| --- | --- | --- | --- |
| **0. Kosakata dan skema** | `Constants.Attributes.Widget`; `Presets` menolak `UnrestWidget`; `Widgets/Schemas.luau` (tiga skema + `check`); tipe di `Types.luau`; `docs/UI-ATTRIBUTES.md` | — | S |
| **1. Widgets: identitas dan laporan** | `WidgetSpec.Widget` + akar grup; `UnrestWidget` di `GROUP_INPUTS`; `handle:Get/Groups`; `Report`, `Explain`; `DragOptions` + `Drag2D`; `docs/API-WIDGETS.md` | 0 | M |
| **2. Tooling** | `Tooling/Lint.luau`, `Tooling/Vocab.luau`; `Selector.explain` + `Elements:Explain`; `studio/LintUnrest.luau`, `studio/ExportVocab.luau`; `Manifest.luau` bertag + registrasi di bootstrap; `Vocab.luau` pertama dihasilkan lewat MCP; `Example/*` diganti memakai `Vocab` | 0 (skema), 1 (kalimat `Report` yang disalin Lint) | M |
| **3. Plugin** | `plugin/` dengan lima panel; langkah CI build + artefak; aset rilis; `docs/PLUGIN.md` | 2 | L |
| **4. Control bawaan** | `Widgets/Controls/Slider.luau`, `Toggle.luau`; `Register`/`Use`; state per grup + `Initial`; mount otomatis; `Example/*` menyusut jadi config; `BuildSlider*`/`BuildToggle` menambah `UnrestWidget` | 1 | M |
| **5. Channel/perintah di akar widget** (butuh keputusan 8) | control membaca `UnrestChannel`/`UnrestCommand` dari akar; `if` di `wireCommand`/`wireChannel` + `UnrestWidget` di `WATCHED`; aturan kepemilikan lukisan | 4 | M kecil baris, mahal telaah |
| **6. Generik opsional** | `Descriptor<Role, Group>`, `WidgetSpec<Role>`; `docs/API-ELEMENTS.md` | 2 (baru berguna setelah ada `Vocab`) | S |

Tahap 0–2 adalah inti dan layak dikomitmenkan bersama. Tahap 3 adalah yang paling besar dan
paling terlihat, tapi **tidak** membawa aturan baru: kalau 2 selesai, 3 hanya menggambar.
Tahap 4 boleh berjalan paralel dengan 3. Tahap 5 dan 6 menunggu jawaban.

---

## 5. Uji penerimaan per tahap

Semua uji dijalankan di Studio lewat MCP, dengan layar dari `studio/BuildSliderMulti.luau`
dan `studio/BuildToggle.luau` sebagai benih. Ketiga pemeriksaan CONVENTIONS (`analyze`,
`selene`, `stylua`) harus bersih di tiap tahap.

**Tahap 0.**
- `Schemas.check({ SliderTrack = "Frame", SliderKnob = "TextButton" }, Schemas.Get("Slider"))`
  mengembalikan `Missing = {}`; menghapus `SliderKnob` mengembalikan `Missing = { "SliderKnob" }`.
- `Presets.Register("X", { UnrestWidget = "Slider" })` melempar error yang menyebut alasannya.

**Tahap 1.**
- Bangun `SliderMulti`, hapus `SliderFill` dari `Efek`, Play. `Widgets:Report()` memuat grup
  `Efek` dengan `Missing = { "SliderFill" }` dan `Live = false`, sementara `Musik` `Live = true`.
  **Tidak ada `warn` baru** — laporan, bukan peringatan.
- `Each({ Widget = "Slider", OnReady = ... })` tanpa `Required` menyambungkan `Musik` (akar
  ber-`UnrestWidget = "Slider"`) dan **tidak** menyambungkan grup identik yang akarnya tidak
  ber-`UnrestWidget`.
- Mengubah `UnrestWidget` di akar saat Play memindahkan grup keluar dan masuk resep (scope
  lama dihancurkan, `OnReady` jalan lagi).
- `Drag` dengan `Axis = "Y", Invert = true` pada track vertikal memberi 0 di bawah dan 1 di
  atas; lebar/tinggi nol memberi 0, bukan NaN.
- `handle:Get("Musik").SliderKnob` adalah instance knob; `handle:Get("TidakAda")` nil.

**Tahap 2.**
- `Lint.check(StarterGui)` pada benih yang bersih mengembalikan nol temuan `Error`.
- Setiap baris di tabel 2.4 punya satu benih yang memicunya, dan kalimat temuannya
  **sama persis** dengan `warn` runtime untuk yang punya padanan (bandingkan dengan Output
  saat Play).
- `Vocab.render` dua kali di atas `Vocabulary` yang sama menghasilkan string identik
  (deterministik, terurut).
- `Vocab.luau` yang dihasilkan lolos `luau-lsp analyze`; mengganti satu pemakaian jadi
  `Vocab.Roles.SilderKnob` membuat `analyze` gagal di baris itu.
- `Elements:Explain({ Tag = "Unrest", Selector = "GuiButton" }, track)` menyebut klausa
  `Selector` sebagai yang gagal dan kelas yang sebenarnya.

**Tahap 3.**
- Tempat tanpa `ReplicatedStorage.Unrest`: plugin membuka dan menampilkan satu kalimat,
  tanpa error di Output.
- Memilih `Knob` di `SliderMulti.Musik`: Inspector memperlihatkan "dikelola lewat cascade
  dari `Musik`", `UnrestGroup = Musik (inherited from Musik (Frame))`, adapter
  `TextButton <- GuiButton <- GuiObject <- GuiBase2d`.
- Menghapus `UnrestRole` dari `Fill` di Studio: Problems memuat `WidgetIncomplete` dalam
  satu detik; tombol perbaikannya mengembalikannya dan **Ctrl+Z** membatalkannya.
- Export menampilkan teks yang identik byte-per-byte dengan `studio/ExportVocab.luau`.
- `rojo build plugin/default.project.json` di CI menghasilkan artefak; `analyze` bersih untuk
  `plugin/`.

**Tahap 4.**
- Dengan `Example/Slider` menyusut jadi config, `SliderMulti` bekerja seperti sebelumnya
  **dan** menghapus lalu memasang kembali `ScreenGui` saat Play **mempertahankan** nilai
  tiap slider dan **tidak** menerbitkan apa pun ke `Volume.*` sampai pengguna menggeser.
- Akar ber-`UnrestWidget = "Progress"` tanpa `SliderKnob` melukis dari `handle:Get(group):Set(0.4)`
  dan tidak pernah memasang `Drag`.
- `grep -rn '"Volume\.' src/shared` kosong.

**Tahap 5.**
- Uji A dan B dari [Proposal Controls v2 §3](PROPOSAL-CONTROLS.md), dijalankan apa adanya:
  perombakan kulit tanpa satu baris Luau, dan perombakan dengan perilaku baru yang hanya
  menyentuh Studio.
- Akar `Frame` ber-`UnrestCommand` **tidak** lagi memunculkan peringatan `COMMAND_HINT`;
  akar `TextButton` **tidak** mengirim perintah saat diklik.

---

## 6. Risiko dan keputusan terbuka

**Risiko.**

- **Tahap 5 menyentuh `Elements`**, file paling load-bearing di framework, dan invariant
  "attributes are not a second mechanism" mendapat satu pengecualian yang harus
  didokumentasikan di CONVENTIONS. Kecil dalam baris, bukan dalam telaah.
- **Perilaku luau-lsp** untuk singleton di dalam union dan untuk default parameter tipe
  diklaim di 3.6 dari pengetahuan tentang solver, belum diverifikasi terhadap 1.69.0 di repo
  ini. Uji Tahap 2 yang terakhir adalah verifikasinya; kalau gagal, Lapis 1 tetap berdiri
  sendiri.
- **`Source` scan** untuk `RoleUnusedInCode` bisa lambat di tempat besar; karena itu
  opt-in.
- **Cakupan graph**: `graphify-out` memetakan lapisan dokumen dengan baik (node `Widgets`,
  `Controls (Proposal v2)`, `Widgets:Each`), tapi file Luau hanya punya node tingkat file,
  jadi semua fakta implementasi di dokumen ini dibaca langsung dari sumber. Dua drift
  ditemukan dan dicatat: v2 §10.3–10.4 (bagian 1.2) dan jalur contoh di `API-WIDGETS.md`
  (bagian 1.5).
- **Manifest bertag** bergantung pada game yang disiplin memisahkan data dari kode; game yang
  memanggil `Presets.Register` inline tetap jalan di runtime tapi plugin tidak melihat
  presetnya. Itu degradasi, bukan kegagalan.

**Keputusan yang butuh jawaban.**

1. **Nama atribut: `UnrestWidget`** (rekomendasi, mengikuti nama lapisan) atau
   mempertahankan `UnrestControl` dari v2?
2. **Control bawaan masuk `src/shared/Widgets/Controls/`** dan ikut paket Wally, dengan
   aturan "tanpa nama channel"? Atau tetap di `src/game-client/Example` sebagai contoh saja?
   Rekomendasi: masuk framework; `Toggle` dan `Slider` sudah terbukti.
3. **Penemuan manifest** lewat tag `UnrestManifest` (rekomendasi) atau jalur tetap
   (`ReplicatedStorage.UnrestManifest`)?
4. **Tujuan `Vocab.luau`**: `src/game-client/Vocab.luau` (rekomendasi; peran dan grup adalah
   kosakata UI, client saja) atau `src/game-net/` supaya server ikut melihat nama grup?
5. **Rute ekspor** yang dianggap resmi: MCP + Command Bar (rekomendasi untuk sekarang),
   two-way sync Rojo (perlu verifikasi), atau Lune di `rokit.toml` dengan pemeriksaan CI
   "Vocab mutakhir" (butuh `.rbxl` yang bisa diakses CI)?
6. **Distribusi plugin**: aset GitHub Release saja (rekomendasi awal), atau juga Creator
   Store sebagai Plugin?
7. **Skema `Slider`** mewajibkan dua peran (`SliderTrack`, `SliderKnob`) alih-alih empat
   seperti `ROLES` hari ini. Setuju bahwa fill dan label opsional?
8. **Apakah Tahap 5 diinginkan sama sekali**, mengingat argumen v2 §2 bahwa UI diskrit lebih
   murah lewat atribut yang sudah ada dan hanya slider kontinu yang terbayar?
9. **Jendela kepemilikan lukisan** untuk Tahap 5 (pertanyaan terbuka v2 nomor 1), kini
   dengan Bridge lokal: cukup "sampai `onCommit`", atau tetap perlu satu frame setelahnya?
10. **Uji tanpa Studio**: tetap tanpa test runner (rekomendasi untuk proposal ini), atau
    mulai memasang Lune / Jest-Lua untuk `Schemas.check` dan `Vocab.render` yang sudah
    murni?
11. **`Selector.explain` masuk framework** (rekomendasi, S) atau cukup di `Tooling/`?

---

## 7. Status

Proposal. Belum ada kode yang ditulis dan belum boleh ditulis sampai diperintahkan. Bagian
1.2 mencabut sebagian [Proposal Controls v2](PROPOSAL-CONTROLS.md); dokumen itu tetap
berlaku untuk yang tidak disebut di sana.
