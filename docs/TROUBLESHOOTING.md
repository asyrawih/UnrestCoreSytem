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

**Artinya:** `Bindable` adalah daftar-izin, dengan sengaja. Nilai channel bisa datang dari
server, jadi dia tidak boleh menulis properti sembarangan.

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

**Perbaikannya:** perbaiki ejaannya, atau daftarkan presetnya di `src/game/Presets.luau`.

---

## 3. Tabel gejala

| Gejala | Penyebab | Perbaikan |
| --- | --- | --- |
| Tidak ada yang diadopsi sama sekali | Tidak ada yang membawa tag pada salinan milik client | Beri tag di `StarterGui` lewat **View → Tag Editor**, bukan di `PlayerGui` sesi yang sedang jalan. Ingat tagnya **menurun**: menandai `ScreenGui` sudah cukup untuk semua `GuiObject` di bawahnya |
| Diadopsi, tapi atributnya seperti diabaikan | Atributnya salah eja, atau ada di instance yang salah | Nama atribut **case-sensitive** dan diawali `Unrest`. `UnrestRole`, `UnrestCommand`, `UnrestPayload`, `UnrestChannel`, `UnrestBind`, dan `UnrestFormat` **tidak pernah diwariskan** — ketiganya harus ada di elemennya sendiri |
| `refused (NotClientCallable)` | Kontraknya tidak menulis `AllowClient = true` | Pakai perintah yang memang client-callable, atau tambahkan barisnya di `src/game/Contracts.luau` kalau client memang seharusnya boleh meminta. Kesalahannya sama entah datang dari atribut atau dari kode |
| `refused (UnknownCommand)` | Perintahnya tidak pernah dideklarasikan **di realm ini** | Pastikan **kedua** bootstrap meng-`require(ReplicatedStorage.Game)` sebelum `Unrest:Start()`. Cache ModuleScript terpisah per realm, jadi keduanya harus diberi tahu |
| `refused (ResponseNotAllowed)` | `Invoke` dipakai untuk perintah tanpa `Response = true` | Tambahkan `Response = true` di kontraknya, atau pakai `Dispatch` |
| `refused (WrongRealm)` | Server mencoba men-dispatch perintah `Realm = "Client"` | Server tidak menyuruh client. Terbitkan state di sebuah channel dan biarkan client memutuskan |
| `:Handle(...) was called on the Client, but its contract puts the handler on the Server` | Handler dipasang di realm yang salah | Pindahkan pendaftarannya, atau ubah `Realm` di kontraknya |
| Mengikat `Changed` dari kode melempar error | Kelasnya tidak punya satu properti nilai — `Frame` tidak punya | Ikat `Changed` ke kelas yang punya (`TextLabel`, `TextButton`, `TextBox`, `ImageLabel`, `ScrollingFrame`, `UICorner`, `UIScale`), atau buang handler-nya |
| `Query({ Group = ... })` tidak cocok dengan apa pun | Tidak ada di rantainya yang menyetel `UnrestGroup`, atau penelusurannya menabrak `LayerCollector` sebelum sampai ke sana | Setel `UnrestGroup` di `ScreenGui` tempat elemennya benar-benar tinggal. Mewarisi grup **tidak** mengadopsi instance yang tidak dinaungi tag |
| `sets UnrestChannel but there is nothing to write it into` | Kelasnya tidak punya properti nilai bawaan | Tambahkan `UnrestBind = "<properti>"` |
| Label tetap kosong | Channel-nya menerbitkan `nil` dan tidak ada format | Tambahkan `UnrestFormat` — tidak ada properti Roblox yang menerima `nil`, jadi tanpa format tidak ada yang bisa ditulis |
| Perubahan atribut tidak berpengaruh | Kamu mengubahnya di instance yang tidak dikelola atau sudah dilepas | Mengubah atribut pada elemen yang dikelola menyambungkannya ulang secara langsung; mengubah atribut yang bisa diwariskan pada leluhur menyambungkan ulang setiap keturunan yang dikelola. Tidak ada yang perlu di-restart |
| `Press` menyala, `Release` tidak pernah | Penunjuknya meninggalkan elemen saat masih ditekan | Jangan simpan "sedang ditekan" sebagai state yang harus dibersihkan event berikutnya. Reset di `Removed` |
| `Hover` tidak pernah menyala di HP | `MouseEnter` khusus mouse | Afordansi yang hanya muncul saat hover tidak terlihat di perangkat sentuh. Jangan jadikan hover satu-satunya petunjuk |
| `Press` pada `ProximityPrompt` tidak pernah menyala | `HoldDuration` bernilai 0 | Set `HoldDuration > 0`, atau pakai `Active` |
| `Added` di dalam `:Bind()` tidak menyala | Elemennya sudah tiba lebih dulu | Oper `Added` di panggilan `Query` yang pertama |
| `:UseTransport must be called before :Start()` | Transport dipasang terlambat | Pindahkan `UseTransport` ke antara `require` dan `:Start()` |
| `a system named "X" is already registered` | Dua sistem memakai `Name` yang sama | Nama sistem adalah kunci registry dan harus unik |
| `"X" was registered after startup but depends on "Y"` | Pendaftaran terlambat, dependensinya belum jalan | Daftarkan sebelum `Unrest:Start()`, atau daftarkan dependensinya dulu |

---

## 4. Kalau client tidak bisa mengirim apa pun

Periksa tiga hal ini, berurutan:

1. **Apakah server sudah memanggil `unrest:OpenGateway()`?** Sebelum baris itu jalan, remote-nya
   belum ada. Ini bukan penolakan, ini ketiadaan pintu.
2. **Apakah kedua bootstrap sudah meng-`require(ReplicatedStorage.Game)`?** Kalau client belum,
   penjaga di client menolak mengirim dengan `UnknownCommand`.
3. **Apakah kontraknya menulis `AllowClient = true`?** Kalau tidak, `NotClientCallable`, di
   kedua sisi.

---

## 5. Kalau sesuatu di framework yang salah

Framework melapor lewat dua sinyal yang bisa kamu sambungkan ke sistem log-mu sendiri:

```luau
unrest.Bridge.Rejected:Connect(function(rejection)
    warn(`{rejection.Command}: {rejection.Reason} — {rejection.Detail}`)
end)
```

Dan di sisi server, gerbangnya menyalakan `Rejected` serta `AbuseDetected`. Lihat
[Keamanan Remote](REMOTE-SECURITY.md), bagian 8.
