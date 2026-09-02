# Referensi UI

> Framework tidak membuat UI. Dia mengelola UI yang sudah kamu buat.

Tidak ada `Mount`, tidak ada pustaka komponen, dan tidak ada satu jalur kode pun di dalam
Unrest yang membangun sebuah `GuiObject`. Setiap elemen yang disentuh framework dibuat tangan
di Roblox Studio.

Yang framework sediakan adalah separuh yang lain: dia mempelajari instance-mu itu **apa**,
menyambungkannya ke state framework, dan menjaga sambungan itu tetap hidup saat instance-nya
datang dan pergi.

---

## Halaman-halamannya

Referensi ini dulu satu halaman panjang. Sekarang dipecah mengikuti batas topiknya, supaya
kamu bisa langsung ke bagian yang kamu butuhkan.

| Halaman | Jawab pertanyaan |
| --- | --- |
| **[Adopsi dan Tag](UI-ADOPTION.md)** | Bagaimana sebuah instance masuk ke framework? Kenapa menandai wadahnya saja sudah cukup? Bagaimana cara keluar lagi? |
| **[Referensi Atribut](UI-ATTRIBUTES.md)** | Atribut `Unrest*` apa saja yang ada, dan apa artinya? Preset itu apa? Apa yang diwariskan dari leluhur? |
| **[Kosakata Handler](UI-HANDLERS.md)** | Dua belas kata kerja itu apa saja? Kelasku mendukung yang mana? Jebakannya di mana? |
| **[Cakupan Adapter](UI-ADAPTERS.md)** | Kelas ini punya event apa dan properti bindable apa? Tabel lengkap per kelas. |

Dua halaman lain yang berdekatan:

* **[API Elements & Query](API-ELEMENTS.md)** — pengikatan lewat kode: `Unrest:Query`,
  `Descriptor`, `QueryHandle`.
* **[Pemecahan Masalah](TROUBLESHOOTING.md)** — pesan galat yang akan kamu lihat, dan
  artinya.

---

## Ringkasan satu halaman

Kalau kamu cuma butuh mengingat kembali:

**Pendaftarannya satu tag.** Beri tag `Unrest` pada sebuah instance dan sejak detik itu: satu
adapter diresolusi untuk `ClassName`-nya, atribut `Unrest*`-nya dibaca dan disambungkan, dan
dia jadi terlihat oleh `Unrest:Query`. Cabut tagnya dan semuanya dilepas, dalam satu langkah,
tanpa sisa.

**Tagnya menurun.** Menandai sebuah wadah mengelola wadah itu **dan setiap `GuiObject` di
bawahnya**. Satu layar didaftarkan dengan satu tag, bukan empat puluh.

**Atributnya opsional.** Instance yang cuma punya tag tetap diadopsi dan tetap bisa
di-query; dia cuma tidak melakukan apa-apa sendiri.

**Adopsinya khusus client.** `ScreenGui` bertag memang ada juga di server, tapi mengikat
event-nya di sana akan menyesatkan: peristiwa UI adalah **permintaan**, dan otoritasnya
adalah kontrak perintah yang dituju permintaan itu, bukan tombolnya.

**Atribut tidak memberi hak istimewa.** `UnrestCommand` lewat `Bridge:Dispatch` yang sama
dengan Luau tulisan tangan. Kontraknya yang memutuskan.

**Kode melempar error; atribut cuma memperingatkan.** Kode yang mengikat handler yang tidak
didukung elemennya adalah bug, dan harus berhenti di baris yang menulisnya. Kesalahan yang
sama sebagai atribut cuma memberi peringatan, menyebutkan elemennya dan perbaikannya, lalu
membiarkan sisa layarnya tetap berdiri.

---

## Peta sumber

Kalau kamu perlu membaca kodenya sendiri:

| Berkas | Perannya |
| --- | --- |
| `src/shared/Adapters/init.luau` | `AdapterRegistry`: resolusi, perataan, cache, dan `Adapters.bind` |
| `src/shared/Adapters/Types.luau` | Permukaan tipe lapisan adopsi |
| `src/shared/Adapters/Selector.luau` | Kompilasi descriptor, predikat kecocokan, dan aturan penurunan tag |
| `src/shared/Adapters/Query.luau` | Mesin query yang hidup |
| `src/shared/Adapters/Classes/*.luau` | Satu berkas per keluarga kelas |
| `src/shared/Elements/init.luau` | `ElementManager`: adopsi, resolusi atribut, dan penyambungan |
| `src/shared/Presets.luau` | Bundel atribut bernama yang dipekarkan `UnrestPreset` |
| `src/shared/Util/Resolver.luau` | Validasi runtime di batas publik |
