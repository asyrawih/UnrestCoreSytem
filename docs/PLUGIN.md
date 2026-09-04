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

# Plugin Studio

Mengelola tag `Unrest` dan atribut `Unrest*` lewat panel Properties bawaan Studio berarti
mengetik string yang tidak ada yang memeriksa, di tempat yang tidak memperlihatkan hasilnya.
Plugin ini adalah **panel Properties yang tahu framework**: dia memperlihatkan apa yang akan
disimpulkan runtime tentang instance yang kamu pilih — dikelola atau tidak, lewat adapter apa,
tiap atribut teresolusi jadi apa dan dari lapisan mana — sebelum Play ditekan.

Dua hal yang sengaja **tidak** dibangun, supaya batasnya jelas:

- **Tidak membuat UI.** Tidak ada tombol "buat slider". Skrip benih di `studio/` tetap
  satu-satunya yang membuat instance; plugin bekerja di atas instance yang sudah kamu gambar.
- **Tidak membaca state runtime.** `require` dari plugin menghasilkan salinan modul sendiri,
  bukan singleton yang dijalankan game, jadi plugin tidak bisa melihat `Widgets` yang hidup.
  Untuk itu ada `Widgets:Report()` lewat Command Bar.

---

## Pasang

```
scripts/install-plugin.sh
```

Skrip itu membangun `plugin/default.project.json` ke
`~/Documents/Roblox/Plugins/UnrestPlugin.rbxm`. Studio memuat ulang plugin lokal begitu
filenya berubah, jadi menjalankan skrip ini lagi sambil Studio terbuka adalah seluruh siklus
suntingnya.

Di Windows, foldernya `%LOCALAPPDATA%\Roblox\Plugins`; jalankan baris `rojo build`-nya
langsung, atau setel `ROBLOX_PLUGINS_DIR` sebelum memanggil skrip.

Kalau tidak mau membangun sendiri, `UnrestPlugin.rbxm` juga dilampirkan di setiap
[GitHub Release](https://github.com/asyrawih/UnrestCoreSystem/releases) di samping
`Unrest.rbxm`. Yang satu masuk ke tempat, yang satu masuk ke folder Plugins — jangan tertukar.

Setelah terpasang, toolbar **Unrest** punya satu tombol yang membuka dan menutup panelnya.

---

## Lima panel

Semua bekerja di atas `Selection` Studio dan `StarterGui`, dan **setiap suntingan berjalan di
dalam satu rekaman `ChangeHistoryService`** — satu klik, satu Ctrl+Z.

### Inspector

Untuk instance yang sedang dipilih:

| Baris | Dari mana |
| --- | --- |
| Dikelola? Lewat tag sendiri, cascade dari `X`, atau diblokir `UnrestIgnore` di `Y` | `Selector.isManaged` |
| Adapter dan kemampuannya, satu kalimat | `Adapters:Describe(instance)` |
| Tiap atribut `Unrest*`: nilai teresolusi dan **dari lapisan mana** (`set here` / `from preset "X"` / `inherited from Y`) | `Selector.resolution` + `Selector.attributeIn` |
| Editor per atribut | dropdown untuk `UnrestRole`, `UnrestGroup`, `UnrestWidget`, `UnrestPreset`, `UnrestBind`; kotak teks untuk sisanya; sakelar untuk `UnrestIgnore` |
| Tombol tag / lepas tag | `CollectionService` |

Dropdown-nya tidak pernah mengarang pilihan. Peran datang dari skema yang terdaftar **dan**
dari peran yang sudah dipakai di tempat ini; grup dari grup yang sudah ada; `UnrestWidget` dari
`Schemas.List()`; `UnrestPreset` dari preset yang terdaftar plus manifest; dan `UnrestBind`
hanya menawarkan properti yang adapter instance itu sendiri nyatakan `Bindable`.

Kotak teks yang dikosongkan **menghapus** atributnya, bukan menyimpan `""`, karena framework
membaca string kosong sebagai tidak ada di mana-mana.

### Outline

Pohon yang dikelola, bukan pohon Explorer: setiap akar bertag di bawah `StarterGui` dan semua
yang dijangkau cascade-nya (`Selector.cascadeUnder`), dikelompokkan per `ScreenGui`. Tiap baris
membawa lencana peran, grup, widget, preset, dan atribut wiring yang ada; tanda `^` berarti
nilainya diwarisi, bukan diketik di situ.

Gerbang `UnrestIgnore` dan subtree yang dipangkasnya tampil **redup**, karena lubang yang
dipotongnya justru yang perlu terlihat. Klik satu baris untuk memilihnya di Explorer.

Filter teks mengubah pohonnya jadi daftar datar berisi yang cocok, lengkap dengan jalurnya —
pohon yang difilter selalu berbohong tentang siapa induk siapa.

### Problems

Daftar dari [`Tooling/Lint`](../src/shared/Tooling/Lint.luau): tingkat, kode, instance, dan
kalimatnya. Kalimat itu **sama persis** dengan yang di-`warn` runtime, karena memang string yang
sama. Temuan yang punya `Fix` dapat tombol **Perbaiki**, dan perbaikannya berjalan di dalam
rekaman undo.

Ada tombol **Periksa ulang**. Selain itu pemindaian jalan sendiri: pada seleksi yang berubah,
dan pada `DescendantAdded` / `DescendantRemoving` di `StarterGui`, dengan debounce setengah
detik — `Lint.check` membaca seluruh `StarterGui`, jadi dia tidak boleh jalan per ketikan.

### Widgets

Satu tabel per `UnrestGroup`: akarnya, `UnrestWidget` yang dideklarasikan, peran yang ada,
yang kurang, yang di luar skema, yang ganda, dan yang salah kelas — semuanya dari
`Schemas.check`, fungsi yang sama yang dipakai `Widgets:Report()`.

Dua aksi:

- **jadikan seleksi peran X** — dropdown berisi peran skema grup itu, menyetel `UnrestRole`
  pada instance yang sedang dipilih.
- **pindahkan `UnrestGroup` ke induk bersama** — muncul untuk grup yang setiap bagiannya
  menyetel grupnya sendiri. Grup seperti itu tidak punya akar, jadi tidak ada satu instance pun
  yang boleh membawa `UnrestWidget`-nya. Tombolnya memindahkan atribut itu ke leluhur terdalam
  yang menaungi semuanya.

### Export

Menjalankan `Tooling/Vocab.generate(StarterGui)`, menampilkannya di kotak teks read-only, dan
menuliskannya ke modul kosakata milik tempat ini.

**Sasarannya dicari lewat tag, bukan jalur.** ModuleScript pertama yang bertag `UnrestVocab`
adalah tempat teksnya ditulis — di repo ini `src/game-client/Vocab.luau`, yang mendapat tagnya
dari `Vocab.meta.json` di sebelahnya. Tanpa modul bertag, panelnya bilang begitu dalam satu
kalimat: buat satu ModuleScript di pohon yang di-mount Rojo dan beri tag itu.

Dua kontrol:

- **Tulis ke Vocab** — sekali klik, satu Ctrl+Z (`context.Record`). Kalau yang berubah cuma
  baris tanggal, tidak ada yang ditulis dan panelnya bilang *tidak ada perubahan*; kalau ada,
  panelnya menyebut nama lengkap sasaran dan berapa bita yang masuk.
- **Otomatis** — diingat per instalasi lewat `plugin:GetSetting("UnrestVocabAuto")`. Selagi
  menyala, panelnya menghasilkan ulang satu detik setelah `StarterGui` tenang dan menulis.
  Pemicunya: `DescendantAdded` / `DescendantRemoving`, tag `Unrest` yang dipasang atau dilepas,
  dan `AttributeChanged` pada setiap descendant terkelola untuk `UnrestRole`, `UnrestGroup`,
  `UnrestWidget`, dan `UnrestPreset` — menyunting atribut adalah kasus yang paling sering, dan
  tidak ada satu sinyal pun yang mencakup seluruh pohon untuk itu, jadi koneksinya satu per
  instance dan dirakit ulang setiap kali pohonnya berubah.

**Plugin menulis ke ModuleScript di dalam place, bukan ke disk.** Yang membuatnya mendarat di
berkas adalah **two-way sync** di plugin Rojo; kalau mati, perubahannya tetap ada di place dan
muncul di penampil Changes milik Rojo untuk diterapkan atau disalin tangan. Kalimat itu ada di
panelnya juga.

Kotak read-only tetap ada karena **Studio tidak punya API papan klip untuk plugin**: klik di
dalam kotak, Ctrl+A, Ctrl+C. `studio/ExportVocab.luau` lewat Command Bar atau MCP melakukan hal
yang sama tanpa panel. Ketiga pintu memanggil generator dan penulis yang sama, jadi hasilnya
identik byte per byte.

---

## Yang divalidasi

Tidak ada satu pun aturan validasi di dalam plugin. Semuanya di
[`src/shared/Tooling/Lint.luau`](../src/shared/Tooling/Lint.luau) — `RoleWithoutGroup`,
`DuplicateRole`, `WidgetUnknown`, `WidgetIncomplete`, `WidgetRootIgnored`, `WidgetNoRoot`,
`CommandNotActivatable`, `ChannelNotBindable`, `IgnoreNotBoolean`, `PresetUnknown`,
`GroupDuplicatedAcrossScreens`, `IntentOnContainer`, `GroupNotIdentifier` — dan panel Problems
hanya menggambar apa yang dikembalikan `Lint.check`.

Konsekuensinya yang penting: **menambah aturan di `Lint` memunculkannya di plugin tanpa rilis
plugin baru.**

---

## Prinsip: plugin tidak membawa salinan aturan

| Pengetahuan | Tempat tunggalnya |
| --- | --- |
| Nama atribut, tag, himpunan inheritable | `src/shared/Constants.luau` |
| Cascade, resolusi tiga lapis, peran, grup | `src/shared/Adapters/Selector.luau` |
| Kelas, handler, `Bindable` | `Adapters.new()` |
| Skema widget | `src/shared/Widgets/Schemas.luau` |
| Aturan validasi dan kalimatnya | `src/shared/Tooling/Lint.luau` |
| Generator kosakata | `src/shared/Tooling/Vocab.luau` |
| Tempat berkas kosakata ditulis | ModuleScript bertag `UnrestVocab` |
| Preset dan skema milik game | ModuleScript bertag `UnrestManifest` |

`plugin/src/Framework.luau` adalah satu-satunya file yang tahu di mana benda-benda itu berada.
Dia mencari `ReplicatedStorage.Unrest`, meng-`require` modulnya, membangun `Adapters.new()`,
lalu mendaftarkan isi setiap manifest bertag ke salinan `Presets` dan `Schemas` miliknya —
sehingga dropdown dan Lint melihat nama yang diciptakan game, yang di mode edit belum pernah
didaftarkan siapa pun.

Kalau daftar atribut, tabel kelas, atau aturan cascade pernah muncul di bawah `plugin/`, itu
bug, bukan optimasi.

---

## Batas `require`

Plugin **tidak pernah** meng-`require` `Widgets/init.luau`, `Elements/init.luau`, atau
`Unrest/init.luau`. Dua yang pertama memegang `Players` dan `UserInputService` di puncak file,
dan yang terakhir merakit singleton — ketiganya mengandaikan client yang sudah jalan, dan mode
edit tidak punya satu pun.

Yang boleh dimuat hanyalah lapisan yang murni di waktu require: `Constants`, `Adapters`,
`Adapters/Selector`, `Presets`, `Types`, `Widgets/Schemas`, `Tooling/Lint`, `Tooling/Vocab`.
Ini aturan yang sama dengan yang berlaku untuk `src/shared/Tooling/` sendiri, satu tingkat di
atasnya.

Panahnya searah: `plugin/` boleh membaca framework, dan **tidak ada** file di `src/` yang boleh
tahu plugin ini ada. `plugin/` adalah proyek Rojo sendiri dan, seperti `bench/`, tidak pernah
dipasang di `default.project.json`.

---

## Versi

Plugin membaca `Constants.Version` dari tempat yang dibuka dan membandingkannya dengan satu
konstanta `Framework.MinimumVersion` di `plugin/src/Framework.luau`. Tidak ada pasangan versi
ketiga yang harus dijaga tangan.

Framework yang lebih tua **tidak** membuat plugin gagal. Modul yang tidak ada berarti `nil`,
dan panel yang membutuhkannya menampilkan satu kalimat:

- tanpa `Widgets/Schemas` → panel Widgets kosong dengan pesan perbarui;
- tanpa `Tooling/Lint` → panel Problems begitu juga;
- tanpa `Tooling/Vocab` → panel Export begitu juga;
- tanpa `ReplicatedStorage.Unrest` sama sekali → panelnya membuka dan menampilkan satu kalimat
  bahwa tempat ini tidak memakai Unrest, plus tombol **Muat ulang**. Tidak ada error di Output.

---

## Membangun dan memeriksa

`plugin/` punya sourcemap sendiri, dan sourcemap itu harus berada **di dalam** `plugin/`: rojo
menulis jalurnya relatif terhadap berkas proyek, dan luau-lsp meresolusinya terhadap direktori
kerja.

```
cd plugin
rojo sourcemap default.project.json --output plugin-sourcemap.json
luau-lsp analyze --definitions=/tmp/globalTypes.d.luau \
  --sourcemap=plugin-sourcemap.json $(find src -name '*.luau')
cd ..
selene plugin && stylua --check plugin
rojo build plugin/default.project.json --output UnrestPlugin.rbxm
```

`selene .` dan `stylua --check .` di akar sudah mencakup `plugin/`. CI menjalankan keempatnya
dan mengunggah `UnrestPlugin.rbxm` sebagai artefak; workflow rilis melampirkannya ke GitHub
Release di samping `Unrest.rbxm`.
