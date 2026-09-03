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

# API — `AdapterRegistry`

Framework tidak membuat UI. Setiap elemen yang disentuhnya dibuat tangan di Studio. Jadi
harus ada cara framework **belajar apa yang bisa dilakukan sebuah kelas Roblox** — event apa
yang ada padanya, dan properti apa yang aman ditulis dari sebuah channel.

Itulah adapter.

```luau
local adapters = unrest.Adapters
```

Definisi tipenya ada di `src/shared/Adapters/Types.luau`.

---

## Adapter menumpuk mengikuti hierarki kelas

Adapter disusun lewat `Extends`, mengikuti hierarki kelas Roblox sendiri:

```
GuiBase2d  →  GuiObject  →  GuiButton  →  TextButton
```

Jadi kelas baru biasanya cuma perlu mendeklarasikan segelintir hal yang **dia tambahkan**.
`TextButton` mewarisi semua yang dideklarasikan `GuiButton` dan `GuiObject`.

Resolusi memilih adapter terdaftar yang **paling spesifik** yang di-`:IsA()` oleh instance
itu, meratakan rantai `Extends`-nya (yang turunan menang), lalu menyimpan hasilnya di cache
per `ClassName`.

Bahkan tanpa mendaftarkan apa pun, kelas yang tidak dikenal tetap teresolusi dengan berguna:
registry memilih leluhur paling spesifik yang **memang** dia kenal. `UIDragDetector` tanpa
adapter sendiri teresolusi ke `UIComponent`, dan subclass `GuiObject` baru mendapat seluruh
kosakata penunjuk secara gratis.

---

## `Adapter` — yang kamu tulis

```luau
export type Adapter = {
    ClassName: string,
    Extends: string?,
    Events: { [string]: EventBinder }?,
    Bindable: { [string]: boolean }?,
    ValueProperty: string?,
}
```

| Field | Arti |
| --- | --- |
| `ClassName` | `ClassName` Roblox yang diajarkan adapter ini. |
| `Extends` | Adapter dasar yang ditumpanginya. Biasanya superclass-nya. |
| `Events` | Nama handler → cara menyambungkannya. Digabung dengan rantai `Extends`; yang turunan menang. |
| `Bindable` | **Daftar-izin** properti yang boleh disasar `UnrestBind`. |
| `ValueProperty` | Properti yang diawasi `Changed`, yang jadi bawaan `UnrestBind`, dan yang dilaporkan `Submit`. |

**Adapter bisa mengganti binder yang diwarisinya, tapi tidak pernah menghapusnya.** Subclass
`GuiObject` mendapat `Press` entah menekannya berarti sesuatu atau tidak.

`ValueProperty` juga rata mengikuti rantai `Extends` dan **tidak bisa dibatalkan**. Itu
sebabnya kelas tanpa satu nilai yang jelas harus mewarisi dari kelas yang juga tidak
punya — dan itu sebabnya `Frame` mewarisi `GuiObject` lalu diam, bukan memilih satu properti
untuk dianggap "nilai"-nya.

### `EventBinder`

```luau
export type EventBinder = (element: Instance, invoke: (value: any) -> ()) -> RBXScriptConnection?
```

Menghubungkan satu nama handler ke satu event Roblox pada satu kelas. Mengembalikan `nil`
berarti elemen itu ternyata tidak mendukungnya walau kelasnya begitu.

Binder yang mengembalikan koneksi otomatis diparkir di maid elemennya, jadi kamu tidak perlu
memikirkan pembongkarannya.

Binder juga yang menentukan `value` sebuah handler. **Setiap binder bawaan kecuali dua
mengoper `nil`** — disengaja, karena meneruskan apa pun argumen yang kebetulan dibawa event
Roblox akan membuat `value` berarti hal berbeda di tiap kelas. Yang dua itu: `TextBox`
meneruskan teks yang dikomit ke `Submit`, dan `Changed` yang disintesis meneruskan properti
yang diawasi.

---

## Metode

### `Adapters:Register(adapter: Adapter): Adapter`

Mendaftarkan adapter, **menggantikan** adapter mana pun untuk `ClassName` yang sama.

```luau
unrest.Adapters:Register({
    ClassName = "UIDragDetector",
    Extends = "UIComponent",
    Events = {
        Press = function(element, invoke)
            return (element :: UIDragDetector).DragStart:Connect(function()
                invoke(nil)
            end)
        end,
    },
    Bindable = { Enabled = true, DragStyle = true },
})
```

Pendaftaran membatalkan cache resolusi, jadi efeknya langsung — termasuk untuk elemen yang
sudah diadopsi, saat mereka diresolusi berikutnya.

**Jebakan: daftarkan basisnya lebih dulu.** Kalau `Extends` menyebut adapter yang belum
terdaftar, rantainya memberi peringatan dan berhenti pendek.

### `Adapters:Resolve(instance: Instance): ResolvedAdapter?`

Adapter terdaftar paling spesifik yang di-`:IsA()` instance itu, sudah diratakan. Hasilnya
di-cache.

```luau
local resolved = unrest.Adapters:Resolve(button)
print(table.concat(resolved.Chain, " <- ")) --> TextButton <- GuiButton <- GuiObject
```

`ResolvedAdapter` berisi `ClassName`, `Chain` (paling spesifik dulu), `Events`, `Bindable`,
dan `ValueProperty?`.

### `Adapters:Supports(instance: Instance, handler: string): boolean`

Apakah adapter instance itu bisa mengikat nama handler tersebut.

```luau
unrest.Adapters:Supports(button, "Active")  --> true
unrest.Adapters:Supports(label, "Active")   --> false
```

Selalu `true` untuk `Added` dan `Removed` — itu siklus hidup query, milik setiap instance,
dan adapter-nya bahkan tidak diresolusi untuk keduanya.

### `Adapters:CanBind(instance: Instance, property: string): boolean`

Apakah nilai channel boleh ditulis ke properti itu pada instance ini.

```luau
unrest.Adapters:CanBind(label, "Text")    --> true
unrest.Adapters:CanBind(label, "Parent")  --> false
```

### Jebakan besar: `"Active"` berarti dua hal berbeda

`Active` adalah **nama handler** pada `GuiButton`, dan sekaligus **nama properti bindable**
pada `GuiBase2d`. Jadi:

```luau
adapters:Supports(label, "Active")   --> false — TextLabel tidak bisa diaktifkan
adapters:CanBind(label, "Active")    --> true  — tapi properti Active-nya boleh ditulis
```

Dua pertanyaan, satu string, jawaban berlawanan. Ini juga sebabnya pesan `Describe` bisa
mencantumkan `Active` di bawah *properti bindable* untuk elemen yang tidak mendukung
*handler* `Active` — kelihatan seperti kontradiksi, padahal bukan.

Keduanya juga saling memengaruhi. `Activated` tidak menyala selama properti `Active` bernilai
false, jadi channel yang terikat ke `Active` bisa membungkam handler `Active` — sementara
`Press` dan `Release` tetap menyala, karena keduanya `InputBegan`/`InputEnded` dan tidak
peduli pada properti itu.

### `Adapters:Describe(instance: Instance): string`

Satu kalimat yang menyebutkan adapter mana yang dipakai instance itu dan semua yang bisa
dilakukannya.

```luau
print(unrest.Adapters:Describe(label))
--> a TextLabel resolves to TextLabel <- GuiObject <- GuiBase2d and supports handlers:
--> Changed, Hover, Press, Release, Unhover -- bindable properties: Active, AnchorPoint, ...
```

Ini ditulis sekali di sini, bukan di setiap tempat yang melempar error, supaya pesan
"tidak bisa mengikat itu di sini" selalu bisa langsung ditindaklanjuti.

### `Adapters:List(): { string }`

Nama-nama `ClassName` yang punya adapter terdaftar.

---

## `AdapterAdded: Signal<Adapter>`

Menyala setiap kali sebuah adapter didaftarkan.

---

## `Bindable` adalah daftar-izin, dan itu disengaja

Nilai channel bisa datang dari server. Kalau `UnrestBind` menerima nama properti apa saja,
sebuah string yang diterbitkan cuma berjarak satu atribut dari menulis `Parent`, `Adornee`,
atau `CurrentCamera` pada instance sembarangan.

Jadi setiap adapter mendaftar **dengan tangan** properti mana yang boleh ditulis nilai
channel. Sisanya ditolak dengan peringatan yang menyebutkan elemennya, kelasnya, dan apa yang
kelas itu **memang** dukung.

Tabel cakupan lengkapnya — properti apa yang bindable di kelas apa — ada di
[Cakupan Adapter](UI-ADAPTERS.md).
