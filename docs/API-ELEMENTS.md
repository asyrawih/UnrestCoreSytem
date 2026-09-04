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

# API — `Elements` dan `Query`

`ElementManager` memiliki adopsi: dia mengawasi tag framework, memilih adapter per elemen,
menyambungkan atribut deklaratif, dan menjawab query.

```luau
local elements = unrest.Elements
```

**Client saja.** Di server objeknya ada, tapi tidak mengadopsi apa pun. Kode server tidak
boleh percaya pada peristiwa UI: otoritasnya adalah kontrak perintah, bukan tombol yang
mengirimnya.

Definisi tipenya ada di `src/shared/Adapters/Types.luau`, di-`export` ulang lewat
`src/shared/Types.luau`.

---

## `Unrest:Query` — yang paling sering kamu pakai

```luau
local handle = unrest:Query({
    Tag = unrest.Tag,
    Selector = "GuiButton",   -- is:A("GuiButton") -- TextButton dan ImageButton
    Role = "ToggleMenu",
}, {
    Active = function(element)
        if unrest.Bridge:Peek("Music.NowPlaying") == nil then
            unrest:Dispatch("Music.Play", "Lobby")
        else
            unrest:Dispatch("Music.Stop", nil)
        end
    end,
})
```

Ini jalan pintas untuk `unrest.Elements:Query(descriptor, handlers)`. Keduanya identik.

Query adalah **ikatan hidup**, bukan pemindaian sekali jalan. Buat sebelum elemennya ada, dan
elemen yang ditandai sepuluh menit lagi akan terikat sepuluh menit lagi. Umurnya milikmu:
panggil `:Destroy()` saat layar yang dilayaninya pergi.

---

## `Descriptor` — cara memilih elemen

```luau
export type Descriptor = {
    Tag: string?,
    Selector: string?,
    Name: string?,
    Role: string?,
    Group: string?,
    Ancestor: Instance?,
    Recursive: boolean?,
}
```

| Field | Tipe | Arti |
| --- | --- | --- |
| `Tag` | `string?` | Tag CollectionService. `"Unrest"` **menurun** ke anak-anaknya; tag lain apa pun bersifat persis. |
| `Selector` | `string?` | `ClassName` yang diuji dengan `:IsA()`. Kelas abstrak boleh: `"GuiButton"`, `"GuiObject"`. |
| `Name` | `string?` | `Instance.Name` persis. Dievaluasi ulang saat elemennya dinamai ulang. |
| `Role` | `string?` | Atribut `UnrestRole`, **jatuh balik ke `Instance.Name`**. Dievaluasi ulang secara hidup. |
| `Group` | `string?` | Atribut `UnrestGroup`. Tidak punya fallback. Dievaluasi ulang secara hidup. |
| `Ancestor` | `Instance?` | Akar pencarian. **Wajib** kalau tidak ada `Tag`. |
| `Recursive` | `boolean?` | Menelusuri keturunan, bukan hanya anak langsung. Bawaannya `true`. |

**Aturannya:** minimal satu dari `Tag` / `Selector` / `Name` / `Role` / `Group` harus ada,
dan descriptor tanpa `Tag` **wajib** membawa `Ancestor`. Query tanpa tag dan tanpa akar
harus menyusuri seluruh DataModel, dan itu tidak akan pernah jadi bawaan yang diam-diam.

### Pilih `Role`, jangan `Name`

`Name` adalah hal yang diganti desainer sore hari setelah kamu rilis. `UnrestRole` adalah
kontrak yang mereka set sengaja.

Dan karena `Role` jatuh balik ke nama, tombol yang cuma bernama `ToggleMenu` **sudah** cocok
hari ini tanpa satu atribut pun — lalu tetap cocok setelah seseorang menamainya ulang jadi
`Btn_04_final` dan mengisi `UnrestRole = "ToggleMenu"`.

### `Tag = "Unrest"` memilih yang **dikelola**, bukan yang ditandai

Tombol yang diadopsi lewat penurunan tag adalah tombol yang ditemukan query ini. Ada satu
definisi "dikelola" di seluruh kode ini, dan adopsi maupun query sama-sama memakainya. Kalau
query mengambil dari daftar tag mentah, elemen yang diadopsi lewat penurunan akan tetap
diadopsi, tetap tersambung, tapi tidak terlihat oleh query yang mencarinya — dan itu lebih
buruk daripada tidak mengadopsinya sama sekali.

**Hanya tag milik framework yang menurun.** `Tag = "Highlighted"` tetap berarti persis
instance yang membawa tag itu. Tag asing adalah label, bukan pendaftaran.

---

## `QueryHandle` — hasil yang hidup

```luau
export type QueryHandle = {
    Selector: CompiledSelector,
    ElementAdded: Signal<Instance>,
    ElementRemoved: Signal<Instance>,
    Elements: (self: QueryHandle) -> { Instance },
    Count: (self: QueryHandle) -> number,
    Each: (self: QueryHandle, visitor: ElementHandler) -> QueryHandle,
    Bind: (self: QueryHandle, handlers: Handlers) -> QueryHandle,
    Destroy: (self: QueryHandle) -> (),
}
```

### `handle:Elements(): { Instance }`

Salinan snapshot dari elemen yang sekarang cocok. Aman kamu ubah-ubah.

```luau
print(#handle:Elements())
```

### `handle:Count(): number`

Berapa banyak elemen yang sekarang cocok.

### `handle:Each(visitor: ElementHandler): QueryHandle`

Mengunjungi elemen yang sekarang ada. **Bisa dirantai.** Iterasinya di atas snapshot, jadi
aman kalau himpunannya berubah di tengah jalan.

```luau
handle:Each(function(element)
    (element :: TextButton).BackgroundTransparency = 0.5
end)
```

`value` selalu `nil` di dalam `Each`.

### `handle:Bind(handlers: Handlers): QueryHandle`

Menggabungkan handler tambahan dan **membangun ulang** koneksi setiap elemen. Bisa dirantai.

```luau
handle:Bind({ Hover = function(element) end })
```

**Atomik.** Setiap elemen yang sekarang dipegang query ditanya dulu apakah dia sanggup
memenuhi tabel gabungannya. Kalau ada satu yang tidak sanggup, `Bind` melempar error tanpa
mengubah apa pun — tidak tabel handler-nya, tidak satu ikatan pun.

Karena koneksinya dibangun ulang, mengganti `Active` tidak akan pernah meninggalkan yang lama
masih tersambung.

**Jebakan:** menggabungkan `Added` di sini **membangun ulang** setiap elemen tapi **tidak
menyalakan `Added`** untuk satu pun, karena mereka semua sudah tiba lebih dulu. Kalau kamu
butuh `Added` untuk himpunan yang sudah ada, oper dia di panggilan `Query` yang pertama.

### `handle:Destroy(): ()`

Melepas semuanya, dan menyalakan `Removed` untuk setiap elemen yang sedang ada.

```luau
handle:Destroy()
```

### `handle.ElementAdded` / `handle.ElementRemoved`

`Signal<Instance>`. Alternatif dari handler `Added`/`Removed` kalau kamu lebih suka bentuk
sinyal.

### `handle.Selector: CompiledSelector`

Descriptor setelah divalidasi dan diisi nilai bawaannya. Field `Text` di dalamnya adalah
bentuk yang bisa dibaca manusia, misalnya `{Tag = "Unrest", is:A("TextButton")}`, dan itulah
yang muncul di pesan galat.

---

## `Handlers` — dua belas kata kerja

Nama handler yang bisa kamu oper ke `Query` dan `Bind`:

`Active`, `Secondary`, `Press`, `Release`, `Hover`, `Unhover`, `Focus`, `Blur`, `Submit`,
`Changed`, `Added`, `Removed`.

Setiap handler dipanggil sebagai `(element, value)`, dan `value` bernilai `nil` untuk semua
kecuali dua — jadi `function(element) end` adalah bentuk yang normal.

Sepuluh di antaranya adalah event yang dideklarasikan sebuah adapter. `Added` dan `Removed`
menggambarkan siklus hidup **query**-nya, bukan elemennya, jadi setiap instance punya
keduanya — termasuk `Folder` atau `Part` yang tidak punya adapter sama sekali.

Penjelasan satu per satu, jebakannya, dan kelas mana mendukung apa: lihat
[Kosakata Handler](UI-HANDLERS.md).

> **Kode melempar error; atribut cuma memperingatkan.** `Query(…, { Submit = … })` terhadap
> sebuah `Frame` melempar error. Kesalahan yang sama yang diketik sebagai atribut di Studio
> hanya memberi peringatan.

---

## `ElementManager` — permukaan lengkapnya

Kamu jarang butuh ini; `Unrest:Query` sudah menutup hampir semua kasus. Tapi kalau butuh:

### `Elements:Start(): ()`

Mulai mengawasi tag dan mengadopsi yang sudah ada. Idempoten. Dipanggil oleh `Unrest:Start()`
di client.

### `Elements:Adopt(instance: Instance): ManagedElement?`

Mengadopsi satu instance langsung, bertag atau tidak. Mengembalikan `nil` — dengan peringatan
— kalau tidak ada adapter yang cocok.

### `Elements:Release(instance: Instance): ()`

Melepas satu instance, memutus semua koneksinya.

### `Elements:Get(instance: Instance): ManagedElement?`

Yang framework tahu tentang instance itu, atau `nil` kalau tidak dikelola.

### `Elements:All(): { ManagedElement }`

Setiap elemen yang sedang dikelola.

### `Elements:Query(descriptor, handlers?): QueryHandle`

Sama dengan `Unrest:Query`.

### `Elements:Explain(descriptor: Descriptor, instance: Instance): string`

Kenapa satu instance cocok — atau tidak cocok — dengan sebuah descriptor, klausa per klausa,
dalam urutan yang sama dengan predikatnya.

```luau
print(unrest.Elements:Explain({ Tag = unrest.Tag, Selector = "GuiButton", Role = "SliderKnob" }, track))
--> Tag: ok (cascaded from Musik) · Selector: FAIL — Frame is not a GuiButton · Role: ok ("SliderKnob", set here)
```

Query yang kosong cuma bilang "tidak ada yang cocok". Ini bilang **klausa mana** yang menolak,
dan instance-nya sebenarnya apa: kelasnya, dari mana tag-nya menurun, peran mana yang
sebenarnya dia mainkan dan di mana peran itu diketik. Itu selisih antara membaca layar dan
menebaknya.

Kalimatnya dibangun `Selector.explain`, yang menjalankan ulang klausa `Selector.matches` satu
per satu — jadi penjelasan tidak bisa bilang `ok` untuk klausa yang sebenarnya menolak.
Descriptor mentah pun boleh: `parse` dipanggil di dalam, dengan validasi yang sama.

Dipakai panel Inspector di plugin Studio dan sesi agen lewat MCP; di kode game dia paling
berguna sebagai satu `print` saat sebuah query yang kelihatan benar mengembalikan nol elemen.

### `Elements:Destroy(): ()`

Merobohkan manajernya.

### `ManagedAdded` / `ManagedRemoved`

`Signal<ManagedElement>`. Menyala saat adopsi dan pelepasan.

---

## `ManagedElement` — apa yang framework tahu

```luau
export type ManagedElement = {
    Instance: Instance,
    Adapter: ResolvedAdapter,
    Role: string,
    Group: string?,
    Attributes: { [string]: any },
    Preset: string?,
    Sources: { [string]: AttributeSource },
    Released: Signal<ManagedElement>,
}
```

| Field | Arti |
| --- | --- |
| `Instance` | Instance-nya sendiri. |
| `Adapter` | Adapter yang sudah diratakan untuk kelasnya. |
| `Role` | `UnrestRole`, jatuh balik ke `Instance.Name`. **Tidak pernah diwariskan.** |
| `Group` | `UnrestGroup` milik sendiri, atau milik leluhur terdekat. |
| `Attributes` | Atribut `Unrest*` setelah resolusi. Sisa framework membaca ini dan tidak yang lain. |
| `Preset` | Nama preset yang memekar ke `Attributes`, kalau ada dan berhasil. |
| `Sources` | Asal-usul setiap kunci `Attributes`. |
| `Released` | Menyala saat elemen ini dilepas. |

### `Sources` — "siapa yang menyetel ini?"

Setiap entri berisi `Origin` (`"Own"`, `"Preset"`, atau `"Inherited"`), `Preset?`,
`Ancestor?`, dan `Text` — satu frasa yang bisa dibaca.

```luau
local element = unrest.Elements:Get(button)
print(element.Preset)                       --> MusicToggle
print(element.Sources.UnrestCommand.Origin) --> Preset
print(element.Sources.UnrestGroup.Text)     --> inherited from Menu (ScreenGui)
```

Ada juga fungsi bantu yang merangkum semuanya jadi satu baris. Perhatikan bahwa dia dipanggil
dengan **titik**, dari modulnya, bukan dari manajernya:

```luau
local Elements = require(ReplicatedStorage.Unrest.Elements)
print(Elements.describe(element))
--> UnrestChannel = Music.NowPlaying (from preset "MusicToggle"),
--> UnrestGroup = MainMenu (inherited from Menu (ScreenGui)),
--> UnrestPayload = Dancefloor (set here)
```

---

## Kenapa ini bukan pemindaian

Setiap query memelihara dua himpunan.

**Watched** adalah setiap kandidat yang bisa dihasilkan sumbernya. Masing-masing membawa maid
kecil berisi koneksi `Destroying` plus **persis** pengawasan yang dibutuhkan descriptor
ini — filter `Name` atau `Role` mendapat pengawasan nama, filter `Role` atau `Group` mendapat
pengawasan atribut, filter yang cuma menyebut kelas tidak mendapat keduanya.

**Bound** adalah bagian yang sekarang cocok, masing-masing dengan maid berisi koneksi
handler-nya.

Jadi sebuah elemen boleh masuk dan keluar himpunan hasil berkali-kali seumur hidupnya, dan
`Removed` menyala persis sekali per kepergian.

Query yang bersumber dari tag framework membayar tambahan: satu `DescendantAdded` per akar
bertag, satu pengawasan `UnrestIgnore` per gerbang, dan — per kandidat — satu
`AncestryChanged` dan satu pengawasan `UnrestIgnore`. Dua suntingan itulah yang bisa
memindahkan elemen masuk atau keluar **cakupan**, bukan sekadar keluar dari filternya.
Descriptor yang menyebut tag lain, atau membawa `Ancestor`, tidak membayar itu sama sekali.
