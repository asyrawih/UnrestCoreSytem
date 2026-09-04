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

# Pemecahan Masalah

Pesan galat yang akan kamu lihat, artinya apa, dan cara memperbaikinya.

---

## 1. Prinsipnya: kode melempar error, atribut memperingatkan

Mengikat handler yang tidak didukung sebuah elemen **tidak pernah** gagal diam-diam. Tapi
tingkat keparahannya tergantung siapa yang meminta:

* **Kode yang salah harus berhenti.** Kode yang mengikat handler yang tidak didukung elemennya
  adalah bug, dan dia harus berhenti di baris yang menulisnya.
* **Atribut yang salah tidak boleh menjatuhkan layar.** Atribut adalah data, biasanya diketik
  orang yang tidak sedang melihat jendela Output. Menjatuhkan seluruh menu karena satu atribut
  adalah hasil yang lebih buruk.

Pesannya sama, keparahannya berbeda.

---

## 2. Pesan yang akan kamu lihat

### Handler tidak bisa diikat

```
[Unrest.Adapters] handler "Submit" cannot bind to game.Players.You.PlayerGui.Menu.Title:
a TextLabel resolves to TextLabel <- GuiObject <- GuiBase2d and supports handlers: Changed,
Hover, Press, Release, Unhover -- bindable properties: Active, AnchorPoint, ... Narrow the
query {Tag = "Unrest", is:A("GuiObject")} with a Selector or a Role, or drop that handler.
```

**Artinya:** query-mu memilih sebuah elemen yang kelasnya tidak punya handler itu.

**Perbaikannya:** persempit descriptor-nya dengan `Selector` atau `Role`, atau buang
handler-nya. Pesannya mencantumkan apa yang kelas itu **memang** dukung, jadi kamu tidak perlu
membuka tabel mana pun.

Lihat [Kosakata Handler](UI-HANDLERS.md).

### `UnrestBind` menyebut properti yang tidak bindable

```
[Unrest.Elements] game.Workspace.Door.Prompt sets UnrestBind = "Parent", which is not
bindable: a ProximityPrompt resolves to ProximityPrompt and supports handlers: Active,
Hover, Press, Release, Unhover -- bindable properties: ActionText, ClickablePrompt, ...
Bindable is an allowlist, so a channel value can never write an arbitrary property;
register an adapter that permits it if you need it.
```

**Artinya:** `Bindable` adalah daftar-izin, dengan sengaja. Nilai channel bisa berasal dari mana
saja di dalam proses ini, jadi dia tidak boleh menulis properti sembarangan.

**Perbaikannya:** pakai properti dari tabel bindable kelas itu di
[Cakupan Adapter](UI-ADAPTERS.md), atau daftarkan adapter yang mengizinkannya lewat
[`Adapters:Register`](API-ADAPTERS.md).

### Field descriptor tidak dikenal

```
[Unrest.Resolver] unknown Query descriptor field "Rôle". Did you mean "Role"?
Valid fields: Ancestor, Group, Name, Recursive, Role, Selector, Tag.
```

**Artinya:** `Resolver` memeriksa descriptor, tabel handler, dan definisi adapter saat
runtime — karena type checker Luau hanya melindungi pemanggil yang dirinya sendiri diberi
tipe.

**Perbaikannya:** perbaiki ejaannya. Pesannya menebak yang kamu maksud.

### Preset tidak dideklarasikan

```
[Unrest.Elements] ... resolves UnrestPreset = "MusicTogle" (set here), which is not a
declared preset. Declared presets: DanceButton, DanceStop, MusicStop, MusicToggle,
NowPlayingLabel, VolumeButton. The element was adopted with its own attributes only --
fix the spelling, or declare it with Presets.Register("MusicTogle", ...).
```

**Artinya:** salah ketik pada `UnrestPreset`. Elemennya **tetap diadopsi**, dengan atributnya
sendiri saja.

**Perbaikannya:** perbaiki ejaannya, atau daftarkan presetnya dengan `Presets.Register` di kode
game-mu, sebelum layarnya diadopsi.

### Widget dipanggil di server

```
[Unrest.Widgets] :Each() is client-only -- the server has no screen to find widgets on.
```

**Artinya:** `Unrest.Widgets:Each`, `:Drag`, `:Drag2D`, `:Report` dan `:Explain` **melempar
error** di server. Widget adalah sesuatu di layar, dan server tidak punya layar; diam-diam
tidak melakukan apa-apa cuma akan menyembunyikan kesalahannya sampai jauh belakangan.

**Perbaikannya:** pindahkan panggilannya ke `src/game-client/`. Lihat
[API Widgets](API-WIDGETS.md).

### Sebuah peran tanpa grup

```
[Unrest.Widgets] game.Players.You.PlayerGui.Menu.Knob plays "Knob" but sets no UnrestGroup,
so there is no widget for it to join.
```

**Artinya:** `UnrestGroup` adalah satu-satunya hal yang menyatukan beberapa bagian jadi satu
widget. Tanpa itu, bagian ini tidak punya widget untuk dimasuki, jadi dia diabaikan.

**Perbaikannya:** setel `UnrestGroup` — biasanya sekali saja, di wadah tempat bagian-bagian itu
tinggal, karena `UnrestGroup` diwariskan ke keturunannya.

### Dua instance mengaku peran yang sama

```
[Unrest.Widgets] ...Menu.Slider2.Knob also plays "Knob" for group "Musik", which
...Menu.Slider1.Knob already fills. Ignoring the second one -- give it its own UnrestGroup.
```

**Artinya:** dua bagian dengan peran yang sama di bawah satu `UnrestGroup` adalah kesalahan di
layarnya, bukan penggantian. Yang **pertama** dipertahankan; diam-diam memilih yang belakangan
akan menyambungkan mana pun yang kebetulan ditemukan terakhir.

**Perbaikannya:** beri slider kedua `UnrestGroup`-nya sendiri.

---

## 3. Tabel gejala

| Gejala | Penyebab | Perbaikan |
| --- | --- | --- |
| Tidak ada yang diadopsi sama sekali | Tidak ada yang membawa tag pada salinan milik client | Beri tag di `StarterGui` lewat **View → Tag Editor**, bukan di `PlayerGui` sesi yang sedang jalan. Ingat tagnya **menurun**: menandai `ScreenGui` sudah cukup untuk semua `GuiObject` di bawahnya |
| Diadopsi, tapi atributnya seperti diabaikan | Atributnya salah eja, atau ada di instance yang salah | Nama atribut **case-sensitive** dan diawali `Unrest`. `UnrestRole`, `UnrestCommand`, `UnrestPayload`, `UnrestChannel`, `UnrestBind`, dan `UnrestFormat` **tidak pernah diwariskan** — semuanya harus ada di elemennya sendiri |
| `UnrestCommand` ditekan, tidak ada yang terjadi | Tidak ada yang memanggil `Bridge:Handle` untuk nama itu | Perintah tanpa handler adalah no-op yang **diam**, bukan galat — itu memang rancangannya. Periksa ejaan namanya di kedua sisi |
| Mengikat `Changed` dari kode melempar error | Kelasnya tidak punya satu properti nilai — `Frame` tidak punya | Ikat `Changed` ke kelas yang punya (`TextLabel`, `TextButton`, `TextBox`, `ImageLabel`, `ScrollingFrame`, `UICorner`, `UIScale`), atau buang handler-nya |
| `Query({ Group = ... })` tidak cocok dengan apa pun | Tidak ada di rantainya yang menyetel `UnrestGroup`, atau penelusurannya menabrak `LayerCollector` sebelum sampai ke sana | Setel `UnrestGroup` di `ScreenGui` tempat elemennya benar-benar tinggal. Mewarisi grup **tidak** mengadopsi instance yang tidak dinaungi tag |
| `sets UnrestChannel but there is nothing to write it into` | Kelasnya tidak punya properti nilai bawaan | Tambahkan `UnrestBind = "<properti>"` |
| Label tetap kosong | Channel-nya menerbitkan `nil` dan tidak ada format | Tambahkan `UnrestFormat` — tidak ada properti Roblox yang menerima `nil`, jadi tanpa format tidak ada yang bisa ditulis |
| Perubahan atribut tidak berpengaruh | Kamu mengubahnya di instance yang tidak dikelola atau sudah dilepas | Mengubah atribut pada elemen yang dikelola menyambungkannya ulang secara langsung; mengubah atribut yang bisa diwariskan pada leluhur menyambungkan ulang setiap keturunan yang dikelola. Tidak ada yang perlu di-restart |
| `Press` menyala, `Release` tidak pernah | Penunjuknya meninggalkan elemen saat masih ditekan | Jangan simpan "sedang ditekan" sebagai state yang harus dibersihkan event berikutnya. Reset di `Removed` |
| `Hover` tidak pernah menyala di HP | `MouseEnter` khusus mouse | Afordansi yang hanya muncul saat hover tidak terlihat di perangkat sentuh. Jangan jadikan hover satu-satunya petunjuk |
| `Press` pada `ProximityPrompt` tidak pernah menyala | `HoldDuration` bernilai 0 | Set `HoldDuration > 0`, atau pakai `Active` |
| `Added` di dalam `:Bind()` tidak menyala | Elemennya sudah tiba lebih dulu | Oper `Added` di panggilan `Query` yang pertama |
| `:Each() needs at least one required role` | `Required` kosong | Sebuah grup tidak akan pernah dianggap lengkap kalau tidak ada satu pun peran wajib. Sebutkan minimal satu |
| `Drag needs a GuiObject for its handle` | `handle` atau `track` bukan `GuiObject` | `Drag` membaca `AbsolutePosition` dan `AbsoluteSize` keduanya. Oper `GuiObject`, bukan `UIListLayout` atau `Folder` |
| `Scythe.add: scope #3 has already been destroyed` | Scope-nya sudah dibongkar | Scope adalah **handle integer**, bukan objek: sesudah `Scope.destroy` handle itu mati, dan handle yang sudah didaur ulang melapor `stale handle`. Jangan simpan scope milik widget setelah `OnReady`-nya dibongkar — pakai scope baru yang diberikan saat widget itu tersambung lagi |
| `:Bind called on a destroyed query` | `QueryHandle` sudah di-`Destroy` | Buat query baru; handle yang sudah dibongkar tidak bisa dipakai lagi |
| `a system named "X" is already registered` | Dua sistem memakai `Name` yang sama | Nama sistem adalah kunci registry dan harus unik |
| `"X" was registered after startup but depends on "Y"` | Pendaftaran terlambat, dependensinya belum jalan | Daftarkan sebelum `Unrest:Start()`, atau daftarkan dependensinya dulu |

---

## 4. Kalau widget tidak pernah tersambung

**Tanya framework-nya dulu.** Dia sudah memegang jawabannya; keempat pemeriksaan di bawah
adalah cara mencarinya dengan tangan.

```luau
print(unrest.Widgets:Explain("Musik"))
--> [Unrest.Widgets] group "Musik" is not a complete Slider: missing SliderFill.

local laporan = unrest.Widgets:Report()
-- laporan.Groups  : satu entri per (resep, grup) — Root, Widget, Present, Missing,
--                   Duplicates, Live
-- laporan.Orphans : elemen berperan yang tidak bisa masuk grup mana pun, dan sebabnya
```

Keduanya **tidak mencetak apa pun sendiri** dan tidak menambah peringatan baru — laporan,
bukan omelan. Keduanya client saja, sama seperti `Each`. Lihat
[API Widgets](API-WIDGETS.md).

Kalimat `no recipe has seen a group "..."` berarti grupnya salah eja, atau bagian-bagiannya
belum diadopsi sama sekali. Kalimat `has no shared root` berarti setiap bagian menyetel
`UnrestGroup`-nya sendiri: itu tetap tersambung untuk `Each` polos, tapi tidak ada tempat
untuk `UnrestWidget`.

`OnReady` baru dipanggil ketika **setiap** peran di `Required` sudah hadir untuk satu grup.
Kalau masih perlu ditelusuri sendiri, periksa empat hal ini, berurutan:

1. **Apakah semuanya di bawah `PlayerGui` pemain ini?** `Widgets` sengaja mengabaikan apa pun
   yang bukan keturunan `PlayerGui`. Layar bertag ada dua kali saat game jalan — cetakannya di
   `StarterGui` dan salinan milik pemain — dan kalau keduanya dihitung, cetakannya bisa merebut
   nama grupnya lebih dulu dan kontrol pemainnya tidak pernah tersambung.
2. **Apakah setiap bagian benar-benar diadopsi?** Peran dibaca dari elemen yang sudah diadopsi,
   jadi bagian yang tidak dinaungi tag — atau yang tertahan `UnrestIgnore` — tidak akan pernah
   terhitung.
3. **Apakah semuanya berbagi satu `UnrestGroup`?** Bagian tanpa grup memberi peringatan dan
   diabaikan; bagian dengan grup yang berbeda membentuk widget lain yang tidak pernah lengkap.
4. **Apakah `UnrestRole` (atau nama instance-nya) benar-benar sama dengan peran yang kamu
   sebut?** Peran jatuh balik ke `Instance.Name` kalau `UnrestRole` tidak ada, dan
   perbandingannya persis.

---

## 5. Framework tidak punya saluran galat sendiri

Tidak ada sinyal galat untuk disambungkan. Framework melapor ke jendela Output saja, dan setiap
pesan diawali modul yang mengeluarkannya — `[Unrest.Adapters]`, `[Unrest.Elements]`,
`[Unrest.Query]`, `[Unrest.Resolver]`, `[Unrest.Core]`, `[Unrest.Widgets]`. Menyaring Output
dengan `[Unrest.` memisahkan laporan framework dari laporan game-mu.
