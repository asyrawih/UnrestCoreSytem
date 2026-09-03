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

# Arsitektur

Framework Model/View/Controller untuk Roblox, dibangun di atas dua aturan.

**Framework tidak membuat UI.** Setiap elemen dibuat tangan di Roblox Studio. Menandai sebuah
instance dengan `Unrest` adalah seluruh pendaftarannya: dia diadopsi, adapter diresolusi untuk
`ClassName`-nya, atribut `Unrest*`-nya disambungkan, dan dia jadi terlihat oleh
`Unrest:Query`. Mencabut tagnya melepasnya. Tidak ada komponen, tidak ada `Mount`, dan tidak
ada apa pun di `ReplicatedStorage` yang menggambar tombol.

**Bridge adalah bus lokal.** `Publish`/`Subscribe`/`Peek` ke satu arah, `Dispatch`/`Handle` ke
arah sebaliknya, semuanya di dalam satu mesin. Tidak ada remote di framework ini, tidak ada
argumen `Player` di mana pun, dan tidak ada lapisan jaringan sama sekali. Framework ini
abstraksi UI, dan cuma itu.

```
   Core (Model)              Bridge (Controller)              View
  ┌──────────────┐          ┌───────────────────┐      ┌──────────────────┐
  │  System milik│          │ Publish/Subscribe │      │  UI dibuat di    │
  │  game        │  ──────► │ Peek              │ ───► │  Studio, ditandai│
  │              │          │ Dispatch/Handle   │      │  `Unrest`        │
  └──────────────┘          └───────────────────┘      └──────────────────┘
   pemilik state                bus lokal                       ▲
                                                                │
                                                        CollectionService
                                                         adopsi + adapter
```

Core tidak pernah menyentuh Instance. UI yang diadopsi tidak pernah memanggil sebuah System.
Semuanya menyeberang di Bridge.

---

## 1. Tata letak: siapa memiliki apa

| Folder di disk | Muncul di DataModel sebagai | Punya siapa |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Unrest` | framework |
| `Packages` | `ReplicatedStorage.Packages` | dependensi Wally |
| `src/game-net` | `ReplicatedStorage.GameNet` | game, dibaca kedua realm |
| `src/game-server` | `ServerScriptService.Game` | game, server |
| `src/game-client` | `StarterPlayer.StarterPlayerScripts.Game` | game, client |

Itu **seluruh** isi `default.project.json`. Tidak ada mount lain, dan khususnya tidak ada
`StarterGui`: UI tidak pernah masuk pohon Rojo, karena framework yang mengadopsi UI tidak boleh
ikut membuatnya.

`Unrest` dan kode game **bersebelahan**, bukan bersarang. Itu yang membuat aturan berikut bisa
ditegakkan hanya dengan membaca `require`-nya:

> **Kode game meng-`require` framework. Framework tidak pernah meng-`require` kode game.**

Tidak ada satu berkas pun di `src/shared` yang boleh menyebut `ReplicatedStorage.GameNet` atau
`ServerScriptService.Game`. Kalau ada, sesuatu yang seharusnya ada di sisi game sudah bocor ke
framework.

---

## 2. Kontrak antar lapis

| Lapis | Boleh bergantung pada | Tidak pernah |
| --- | --- | --- |
| `Primitives` | tidak apa-apa | — |
| `Util` (Signal, Scope, Slots, Resolver) | Primitives | state game |
| `Core` | Util | Instance, UI, layar pemain |
| `Bridge` | Util, Primitives | tahu tombol itu apa |
| `Adapters` | Primitives, Constants | logika game |
| `Elements` | Adapters, Bridge | memanggil sistem langsung |
| `Widgets` | Elements, Adapters/Selector, Scope | logika game |

Semuanya tinggal di `ReplicatedStorage.Unrest` dan direplikasi. `Elements` dan `Widgets` ada
juga di server, tapi keduanya khusus client saat runtime: `Elements` tidak mengadopsi apa pun
di sana, dan `Widgets` melempar error kalau dipanggil.

Dua batas modul menanggung beban.

**Kosakata framework hidup sekali, di `Constants.luau`** — tagnya, nama-nama atributnya, dan
himpunan yang bisa diwariskan. **Nama milik game tidak tinggal di sana.** Nama channel dan nama
perintah adalah milik game, ditulis di sebelah kode yang menanganinya, dan framework tidak
pernah mengejanya satu pun.

**Sistem tinggal di sisi game.** Registry `Core` adalah mesin bersama, tapi sistem yang memegang
state tinggal di `src/game-server/`. `Core` sendiri tidak tahu apa-apa soal isinya: `System`
adalah titik perluasannya dan `Core:Register` adalah pintunya.

---

## 3. Adopsi — bagaimana UI Studio masuk

Desainer membangun antarmuka seperti biasa. Satu-satunya tindakan yang menghadap framework
adalah menambahkan tag `Unrest`. Saat diadopsi:

1. **Adapter diresolusi.** Registry memilih adapter paling spesifik yang di-`:IsA()` instance
   itu, lalu meratakan rantai `Extends`-nya, jadi `TextButton` mewarisi semua yang
   dideklarasikan `GuiButton` dan `GuiObject`. Hasilnya di-cache per `ClassName`.
2. **Atribut disambungkan.** Atribut `Unrest*` berubah jadi perilaku yang hidup, dan
   tersambung ulang saat nilainya berubah.
3. **Elemennya jadi bisa di-query.** Setiap `Unrest:Query` yang descriptor-nya sekarang cocok
   langsung mengambilnya — query adalah ikatan hidup, bukan pemindaian sekali jalan.

**Adopsinya khusus client.** `ScreenGui` bertag memang ada juga di server, tapi mengikat
event-nya di sana akan tidak berguna sekaligus menyesatkan: server tidak punya layar, dan tidak
ada pemain yang pernah menekan apa pun di sana.

### Satu aturan, satu pembukuan

Tag itu **menurun**: menandai sebuah wadah mengelola wadah itu dan setiap `GuiObject` di
bawahnya, sampai tertahan `UnrestIgnore`. Aturannya tinggal di `Adapters/Selector.luau` sebagai
predikat murni tanpa state — `isManaged`, `cascadeUnder`, `isGate`, `gatesAbove`, `isPresent`.
Pembukuan yang membuat jawaban-jawaban itu tetap hidup — akar bertag, satu `DescendantAdded`
per akar, satu pengawas `UnrestIgnore` per gerbang, dan sapuan ulang saat sebuah tag atau
sebuah `UnrestIgnore` disunting — tinggal di `Adapters/Cascade.luau`.

`Elements` dan `Query` masing-masing menyerahkan empat callback ke pembukuan itu (`Cover`,
`Uncover`, `Tracks`, `Covered`) dan tidak lebih. Mengadopsi versus sekadar mengamati adalah
satu-satunya hal yang masih boleh mereka bedakan. Dulu ini dua salinan yang ~74% identik, dan
satu pertanyaan yang dijawab di dua tempat adalah bentuk setiap bug serius di repo ini. Jangan
menambah salinan ketiga, dan jangan memindahkan pembukuannya ke dalam `Selector`: state di sana
akan mencabut satu-satunya hal yang membuat modul itu bisa dipercaya.

Satu jebakan yang harus diingat siapa pun yang membaca tag langsung: **tag hidup lebih lama dari
instance-nya.** `Destroy()` mengeluarkan instance dari `CollectionService:GetTagged` tapi
meninggalkan tagnya, jadi `HasTag` menjawab `true` selamanya sesudah itu. Karena itu
`Selector.isManaged` bertanya `IsDescendantOf(game)` lebih dulu.

Selengkapnya di [Adopsi dan Tag](UI-ADOPTION.md) dan [Cakupan Adapter](UI-ADAPTERS.md).

---

## 4. Bridge

| Arah | API | Bentuk |
| --- | --- | --- |
| Core → UI | `Publish` / `Subscribe` / `Peek` | ditahan, jadi pelanggan yang telat tetap dapat nilai sekarang |
| UI → Core | `Dispatch` | kirim dan lupakan, tidak pernah yield |
| mana pun | `Handle` | memasang handler untuk sebuah nama perintah; beberapa handler boleh mendengar nama yang sama |

Seluruh permukaannya: `Context`, `Publish`, `Subscribe`, `Peek`, `Dispatch`, `Handle`,
`Destroy`. Tidak ada yang lain.

Penahanan itulah yang membuat urutan adopsi tidak relevan: elemen yang ditandai tiga puluh
detik setelah sebuah nilai diterbitkan tetap merender state sekarang di frame pertamanya.

`Dispatch` selalu lokal. Tidak ada argumen sumber di `CommandHandler`, karena pemanggilnya ada
di sisi tumpukan panggilan yang sama. Perintah tanpa handler adalah no-op yang diam, bukan
galat.

Selengkapnya di [API Bridge](API-BRIDGE.md).

---

## 5. Framework tidak punya lapisan jaringan

Ini keputusan, bukan kelalaian. Framework mengurus satu batas — antara logika dan layar — dan
batas mesin bukan batas itu. Game yang butuh remote memilikinya sendiri, di luar framework, dan
menyambungkannya ke Bridge dalam satu baris.

Begitulah repo ini melakukannya. `src/game-net/init.luau` adalah namespace ByteNet milik game
di `ReplicatedStorage.GameNet`, satu paket per pesan, dibaca kedua realm supaya id paketnya
sepakat. Lalu:

* **turun** — `src/game-client/Shop.luau` mendengarkan paket dan memanggil `bridge:Publish`,
  jadi label bertag melukis dirinya dari channel;
* **naik** — `src/game-server/init.server.luau` mendengarkan paket dan memanggil
  `unrest.Bridge:Dispatch`, dengan `player` yang diisi Roblox sebagai argumen kedua ByteNet.

Konsekuensi yang harus dipegang: **identitas dan otoritas urusan kode game itu.** Batas
tepercaya yang terakhir adalah `listen` milik game, tempat `player` datang dari Roblox dan tidak
pernah dari isi pesan. Framework tidak melihat satu pun dari itu — dari sisi Bridge, sebuah
`Dispatch` yang lahir dari paket dan sebuah `Dispatch` yang lahir dari klik tidak bisa
dibedakan.

---

## 6. Siklus hidup sistem

1. `Init(unrest)` untuk setiap sistem, sesuai urutan dependensi.
2. `Start()` untuk setiap sistem, dalam urutan yang sama.
3. `Destroy()` dalam urutan terbalik saat dimatikan.

Kait pembongkarannya `Destroy`, bukan `Stop`, supaya tidak pernah bentrok dengan kata kerja
domain: `MusicSystem:Stop()` menghentikan musiknya, `MusicSystem:Destroy()` memensiunkan
sistemnya.

`Dependencies` adalah cara urutan dinyatakan. Tabel sistem harus menulis field itu walau
kosong (`{} :: { string }`) supaya type checker strict mencocokkannya secara struktural.

Selengkapnya di [API Core](API-CORE.md).

---

## 7. Bootstrap

Di server, tiga langkah, dan urutannya membawa makna:

```luau
-- src/game-server/init.server.luau
local GameNet = require(ReplicatedStorage.GameNet)
local Unrest = require(ReplicatedStorage.Unrest)

Unrest:Register(require(script.Systems.Dompet))   -- 1. daftarkan sistem
Unrest:Register(require(script.Systems.Toko))

local unrest = Unrest:Start()                     -- 2. Init lalu Start setiap sistem

GameNet.packets.Beli.listen(function(data, player) -- 3. baru dengarkan paketnya
    unrest.Bridge:Dispatch("Toko.Beli", { Player = player, Item = data.Barang })
end)
```

Handler muncul saat `Init` dan `Start` berjalan, yaitu di langkah 2. Memasang pendengar paket
**terakhir** berarti permintaan paling awal yang bisa dikirim pemain pun sudah pasti menemukan
seluruh handler terpasang. Kalau dibalik, ada jendela waktu di mana pesan sudah bisa tiba dan
belum ada yang bisa menjawabnya.

Di client lebih pendek — start, lalu muat fiturnya:

```luau
-- src/game-client/init.client.luau
local unrest = require(ReplicatedStorage.Unrest):Start()

require(script.Shop)(unrest)
```

Urutan memuat fitur tidak penting. Setiap fitur mengikat lewat `Unrest:Query`, dan ikatan itu
hidup: elemen yang ditandai belakangan, bahkan saat game sedang jalan, tetap terjaring.

`Start()` sendiri hanya melakukan dua hal: menyalakan adopsi kalau konteksnya client, lalu
menjalankan `core:Start`. Memanggilnya dua kali mengembalikan singleton yang sama.

---

## 8. Catatan type checker saat memperluas

Tiga pola yang dipaksakan checker strict:

- Tabel sistem harus menulis `Dependencies` walau kosong, atau dia tidak akan cocok dengan
  `Types.System` secara struktural.
- Field state butuh tipe eksplisit di literal tabel awalnya: `_sound = nil :: Sound?`.
- Sebuah metode harus didefinisikan sebelum metode yang memanggilnya, karena tipe `self`
  tumbuh seiring berkasnya dibaca.

---

## 9. Peta berkas

```
src/shared/               ReplicatedStorage.Unrest — direplikasi, anggap setiap client membacanya
  init.luau               composition root; singleton-nya
  Primitives.luau         tipe Signal/Scope/Connection, nol require
  Types.luau              permukaan tipe publik, meng-export ulang yang lain
  Constants.luau          tag, nama atribut, himpunan yang bisa diwariskan
  Presets.luau            bundel atribut bernama; kosong sampai game mengisinya
  Util/Signal.luau        sinyal ringan
  Util/Scope.luau         re-export Scythe; satu-satunya berkas yang menyebut jalurnya
  Util/Slots.luau         daftar handler yang aman disunting saat sedang dijalani
  Util/Resolver.luau      pemeriksaan bentuk saat runtime, dengan tebakan salah ketik
  Core/init.luau          registry sistem dan siklus hidupnya
  Bridge/init.luau        publish/subscribe dan dispatch/handle, lokal
  Adapters/init.luau      registry adapter dan pengikatan handler
  Adapters/Selector.luau  predikat murni: dikelola, menurun, gerbang, hadir; resolusi atribut
  Adapters/Cascade.luau   pembukuan yang menjaga jawaban Selector tetap hidup
  Adapters/Query.luau     mesin query; ikatan hidup, bukan pemindaian
  Adapters/Types.luau     tipe lapisan adopsi
  Adapters/Classes/       pengetahuan per kelas: Buttons, Common, Frames, GuiBase,
                          Interaction, LayerCollectors, Text, UIComponents
  Elements/init.luau      adopsi UI Studio bertag (khusus client saat runtime)
  Widgets/init.luau       kontrol banyak bagian: `Each` dan `Drag`

src/game-net/             ReplicatedStorage.GameNet — punya game, dibaca kedua realm
  init.luau               namespace ByteNet: satu paket per pesan

src/game-server/          ServerScriptService.Game — punya game, server
  init.server.luau        bootstrap server; pendengar paket dipasang terakhir
  Systems/Dompet.luau     state per pemain
  Systems/Toko.luau       aturan pembelian

src/game-client/          StarterPlayer.StarterPlayerScripts.Game — punya game, client
  init.client.luau        bootstrap client
  Shop.luau               paket ⇄ channel, dan tombol beli
  Slider.luau             slider di atas `Widgets`
  Toggle.luau             sakelar di atas `Widgets`
```

Framework punya **satu** dependensi pihak ketiga, `synttx/scythe`, dan dia di-`require` di
tepat satu berkas (`Util/Scope.luau`). ByteNet ada di `Packages/` untuk kode game; framework
tidak menyentuhnya.
