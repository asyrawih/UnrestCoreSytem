# Benchmark dan Heap

Cara mendapatkan angka dari framework ini, bukan tebakan.

Ada dua alat, dan keduanya diperlukan karena masing-masing buta terhadap separuh
pertanyaannya:

| Alat | Menjawab | Buta terhadap |
| --- | --- | --- |
| **Scriptbench** (plugin Studio) | Berapa lama? | Heap. Sama sekali tidak punya kait memori. |
| **`studio/HeapProfile.luau`** (Command Bar) | Berapa heap Lua yang dialokasikan? | Waktu. |

Klaim terbesar framework ini soal biaya — bahwa membuka sebuah cleanup scope tidak
mengalokasikan apa pun di heap Lua yang bertahan setelah panggilan selesai — adalah klaim
**memori**. Jadi menjalankan Scriptbench saja tidak pernah cukup untuk membuktikannya.

---

## 1. Scriptbench: apa itu dan ambil di mana

Format berkas benchmark de-facto di Roblox datang dari plugin **Benchmarker** buatan
boatbomber. **Scriptbench** buatan AsynchronousAI adalah implementasi ulangnya yang
kompatibel drop-in dengan format yang sama — **gratis**, sumber terbuka, lisensi MIT.

| | |
| --- | --- |
| Creator Store | asset id **`125183599344026`** |
| Sumber | <https://github.com/AsynchronousAI/scriptbench> |
| Lisensi | MIT |

Pasang lewat Creator Store (**Install**), lalu dia muncul sebagai tombol di tab **Plugins**
Studio. Repo ini menargetkan Scriptbench justru karena gratis dan terbuka; berkas `.bench`
yang sama tetap dibaca Benchmarker kalau kamu memang punya yang itu.

---

## 2. Bangun place-nya dengan `bench.project.json`

Benchmark **tidak boleh ikut build normal**. Itu sebabnya ada berkas project terpisah, bukan
satu mount tambahan di `default.project.json`: `bench/` berisi kode mati yang sengaja
dipertahankan supaya kalah dalam perlombaan, dan kode semacam itu tidak punya urusan ikut
terkirim ke pemain.

```sh
rojo build bench.project.json --output bench.rbxl
```

atau, kalau kamu lebih suka menyambung ke Studio yang sudah terbuka:

```sh
rojo serve bench.project.json
```

Isinya sama persis dengan `default.project.json`, ditambah satu mount:

| Mount | Isi |
| --- | --- |
| `ReplicatedStorage.Unrest` | `src/shared` — framework-nya |
| `ReplicatedStorage.GameNet` | `src/game-net` |
| `ReplicatedStorage.Packages` | `Packages` |
| **`ReplicatedStorage.Bench`** | **`bench` — hanya ada di build ini** |

`*.rbxl` sudah masuk `.gitignore`, jadi `bench.rbxl` tidak akan pernah ikut ter-commit.

---

## 3. Nama modulnya harus berakhiran `.bench`

Plugin memindai DataModel mencari `ModuleScript` yang **nama Instance-nya** berakhiran
`.bench`. Rojo hanya membuang ekstensi terakhir dari nama berkas, jadi penamaannya begini:

| Berkas di repo | Instance yang dihasilkan |
| --- | --- |
| `bench/Cleanup.bench.luau` | `ReplicatedStorage.Bench.Cleanup.bench` |
| `bench/Query.bench.luau` | `ReplicatedStorage.Bench.Query.bench` |
| `bench/Baseline/Maid.luau` | `ReplicatedStorage.Bench.Baseline.Maid` — bukan bench, cuma pustaka |

Kalau berkasmu tidak muncul di daftar plugin, hampir selalu ini penyebabnya.

---

## 4. Isi sebuah berkas `.bench`

Sebuah berkas bench adalah `ModuleScript` yang mengembalikan tabel:

```lua
return {
    -- Wajib. Jalan DI LUAR timer, sekali per panggilan.
    ParameterGenerator = function()
        return math.random(1000) / 10
    end,

    -- Semuanya opsional.
    BeforeAll = function() end,
    AfterAll = function() end,
    BeforeEach = function() end,
    AfterEach = function() end,

    -- Wajib. Kuncinya jadi nama baris di grafik.
    Functions = {
        ["nama yang tampil di grafik"] = function(Profiler, nilaiHasilGenerator)
            Profiler.Begin("label") -- opsional, bisa bersarang, tampil di flame chart
            -- kerjanya di sini
            Profiler.End()
        end,
    },
}
```

Empat aturan yang menggigit kalau dilanggar:

1. **Jangan pernah yield.** Tidak ada `task.wait`, tidak ada `WaitForChild`. Angka dari
   fungsi yang yield adalah sampah.
2. **`require` di atas berkas**, bukan di dalam fungsi yang diukur.
3. **`ParameterGenerator` kembalikan TEPAT SATU nilai.** Scriptbench hanya meneruskan return
   **pertama** — itu bug nyata di `benchmark.ts`-nya. Butuh beberapa nilai? Bungkus jadi satu
   tabel.
4. **Bench jalan di DataModel Edit-mode**, terhadap place-mu yang sebenarnya. Jadi jangan
   bergantung pada apa pun yang cuma ada saat Play, dan sadari bahwa instance yang dibuat
   `BeforeAll` benar-benar muncul di berkasmu sampai `AfterAll` menghapusnya.

Titik 4 itu juga alasan `bench/Query.bench.luau` membangun pohonnya di bawah
`ReplicatedStorage` dan merapikannya lagi. Kalau sebuah run terhenti di tengah jalan, hapus
`ReplicatedStorage.UnrestBenchFixture` dengan tangan.

---

## 5. Menjalankan satu bench — persis apa yang kamu ketik

```sh
rojo build bench.project.json --output bench.rbxl
```

1. Buka `bench.rbxl` di Roblox Studio.
2. Tab **Plugins** → tombol **Scriptbench**.
3. Di daftar modul yang muncul, pilih `ReplicatedStorage.Bench.Cleanup.bench`.
4. Tekan **Run**.

Tunggu sampai grafiknya berhenti bergerak. Satu baris per entri di `Functions`.

---

## 6. Membaca angkanya: p50

Plugin menjalankan setiap fungsi ribuan kali dan menampilkan **sebaran** waktunya, bukan satu
angka. Yang kamu baca adalah **p50**.

**p50 adalah median**: separuh panggilan lebih cepat dari itu, separuh lebih lambat.

Kenapa median dan bukan rata-rata? Karena satu panggilan bisa kebetulan menanggung sapuan GC,
atau ter-preempt penjadwal Studio. Sampel semacam itu bisa puluhan kali lebih lambat dari
tetangganya, dan rata-rata akan menyeret hasil akhir mengikutinya. Median mengabaikannya.

Tiga kebiasaan yang membuat angkanya berarti:

* **Bandingkan baris di dalam SATU run.** p50 dari run pagi ini dan p50 dari run kemarin
  dijalankan di atas mesin yang beban latarnya berbeda; yang sebanding adalah dua baris yang
  diukur berdampingan.
* **Perhatikan lebar sebarannya, bukan cuma p50.** Sebaran yang lebar berarti ada sesuatu
  yang tidak deterministik di dalam fungsi itu.
* **Jalankan ulang sebelum percaya.** Selisih di bawah beberapa persen biasanya kebisingan.

---

## 7. Apa yang diukur berkas bench di repo ini

| Berkas | Mengukur | Sengaja TIDAK mengukur |
| --- | --- | --- |
| `bench/TableFill.bench.luau` | **Jalankan ini duluan.** Mengisi tabel yang sudah dialokasikan (`table.create`) melawan tabel kosong. Jawabannya sudah diketahui — `table.create` menang, dan bedanya ada di label `Create`, bukan `Fill`. | Apa pun tentang framework. Ini uji asap: kalau angkanya keluar, plugin-nya terpasang dan penemuan `.bench` jalan, jadi masalah pada bench lain adalah masalah bench itu sendiri. |
| `bench/Cleanup.bench.luau` | Maid lama (berbasis closure) melawan scope Scythe, pada tiga bentuk yang benar-benar dipakai framework: `add 8, destroy` (satu elemen diadopsi), `add 1, destroy` (satu binding), `add 8, clean, add 8, destroy` (rewire). | Apa pun yang menyentuh API Instance. Disposable-nya `function() end` polos, jadi yang terukur wadahnya, bukan Roblox. Closure-nya juga dibuat di `ParameterGenerator`, di luar timer. |
| `bench/Query.bench.luau` | Jalur panas `Selector` yang read-only: `roleOf`, `ancestorChain`, `attributeOf`, `groupOf`, dan `matches` untuk dua descriptor. | `Unrest:Query` itu sendiri. Query mendaftarkan koneksi CollectionService yang hidup lebih lama dari panggilannya; menjalankannya ribuan kali di dalam loop timer akan meninggalkan ribuan langganan hidup dan meracuni sisa sesi Studio-mu. |

`TableFill.bench` juga berkas yang paling enak dijadikan contoh saat menulis bench baru, dan
sengaja memakai ejaan khas Scriptbench (`Name`, `Parameter`, `lib.profilebegin`) supaya
terbukti keduanya jalan. Ejaan yang portabel — yang juga dimengerti Benchmarker-nya
boatbomber — adalah `ParameterGenerator` dan `Profiler.Begin` / `Profiler.End`; itu yang
dipakai dua berkas lainnya.

`bench/Baseline/Maid.luau` adalah Maid lama yang dipulihkan dari riwayat git apa adanya
(commit `80a6e97`, induk dari commit yang menggantinya), bukan tulisan ulang. Perbandingan
terhadap tulisan ulang adalah perbandingan terhadap ingatan penulis benchmark.

> **Semuanya jam dinding, dan hanya jam dinding.** Format ini tidak punya kait memori dalam
> bentuk apa pun. Kalau yang kamu perdebatkan adalah alokasi, angka di halaman ini tidak
> menjawabnya.

---

## 8. Heap: `studio/HeapProfile.luau`

Ini separuh yang tidak bisa dilakukan Scriptbench. Dia mengukur heap Lua, bukan waktu.

**Cara menjalankannya:**

1. `rojo build bench.project.json --output bench.rbxl`, lalu buka di Studio.
2. **View → Command Bar**.
3. Buka `studio/HeapProfile.luau`, salin seluruh isinya, tempel di Command Bar, tekan
   **Enter**.

`studio/` **bukan** mount Rojo dan tidak akan pernah jadi mount Rojo — isinya skrip sekali
pakai yang ditempel dengan tangan. Tapi skrip ini butuh build bench, karena dia me-require
`ReplicatedStorage.Bench.Baseline.Maid`.

**Yang dia lakukan:** membangun 1000 wadah bergaya Maid dan 1000 scope Scythe, masing-masing
memegang 8 disposable, semuanya ditahan hidup saat pembacaan diambil, lalu mencetak tabel
berisi KB absolut dan selisih persennya.

**Kenapa bentuknya begitu:**

* Roblox **memblokir `collectgarbage("collect")`** — satu-satunya argumen yang diizinkan
  adalah `"count"`, dan `gcinfo()` adalah bentuk yang didokumentasikan untuk membaca total
  heap Lua dalam KB. Karena koleksi penuh tidak bisa dipaksa, skripnya menunggu beberapa
  frame `Heartbeat` sebelum tiap pembacaan dan membiarkan GC inkremental mengejar.
* Nilai hasil pembangunan **ditahan hidup** melewati pembacaan kedua. Kalau dilepas lebih
  dulu, GC yang baru saja diberi waktu berjalan akan membuang persis benda yang sedang
  diukur, dan yang terukur berubah jadi "seberapa cepat GC bekerja".
* Hasilnya diulang 15 kali dan yang dilaporkan **median**, dengan alasan yang sama seperti
  p50 di bagian 6.
* Kolom **sekali** dan kolom **median** dilaporkan berdampingan karena untuk Scythe keduanya
  memang berbeda jauh: pengulangan pertama masih menumbuhkan storage-nya, sedangkan median
  adalah keadaan tunak setelah slot didaur ulang — dan keadaan tunak itulah yang dijalani
  framework.

**Batasnya, dan ini penting:** delta mengukur **alokasi**, bukan **retensi**. Angka nol
berarti "tidak ada yang baru dialokasikan", bukan "tidak ada yang ditahan". Untuk memeriksa
apa yang masih dipegang:

1. Nyalakan `Stats.MemoryTrackingEnabled`.
2. Buka Developer Console (**F9**) → tab **Memory** → ambil snapshot **Luau heap**.

Kalau kamu ingin kodemu punya barisnya sendiri di snapshot itu, bungkus dengan
`debug.setmemorycategory(tag)` dan `debug.resetmemorycategory()`. Keduanya menandai alokasi
**thread yang sedang berjalan**, jadi tandai di thread yang sama dengan yang mengalokasikan.

> `Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap)` menerima tag pada
> `GetMemoryUsageMbForTag` — **bukan** pada `GetTotalMemoryUsageMb`, yang tidak menerima
> argumen sama sekali — dan mengembalikan `0` disertai peringatan kalau
> `Stats.MemoryTrackingEnabled` masih mati.

---

## 9. Kapan menjalankan ulang

Setelah setiap perubahan yang menyentuh biaya per-elemen. Yang paling dekat sekarang adalah
hoisting jalan-naik di `Selector`: `groupOf` dan `attributeOf` hari ini menaiki rantai leluhur
lebih dari sekali untuk satu jawaban — `presetFor` menaikinya, lalu lapisan inheritable
menaikinya lagi. Kalau perubahan itu berhasil, dua baris itu di `Query.bench` turun dan
`roleOf`, yang tidak pernah menaiki apa pun, tidak bergerak sebagai kontrolnya.
