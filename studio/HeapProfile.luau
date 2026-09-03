--!nocheck
--[[
                     ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
  _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
/==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
|==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
|==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
|==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
|==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
|==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
`-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`

    https://discord.gg/MZYTABSSfb
]]

--[[
    Heap Profile -- tempel di Command Bar Studio, lalu Enter.

    Separuh yang tidak bisa dijawab Scriptbench. Benchmarker dan Scriptbench mengukur WAKTU
    saja: formatnya tidak punya kait memori sama sekali. Klaim Scythe justru soal heap Lua --
    "membuka scope tidak mengalokasikan apa pun di heap Lua yang bertahan setelah panggilan
    selesai" (lihat `src/shared/Util/Scope.luau`) -- jadi tanpa berkas ini argumennya belum
    selesai.

    Yang dibandingkan: 1000 wadah bergaya Maid melawan 1000 scope Scythe, masing-masing
    memegang 8 disposable, semuanya ditahan hidup saat pembacaan kedua diambil.

    PRASYARAT. Bangun place-nya dengan `bench.project.json`, bukan `default.project.json`.
    Berkas ini hanya menyentuh dua jalur nyata di DataModel:

        Baseline.Maid                           -- Maid lama, ada hanya di build bench
                                                -- (dicari, bukan disebut path-nya: lihat di bawah)
        ReplicatedStorage.Unrest.Util.Scope     -- re-export Scythe milik framework

    Scythe di-require lewat re-export framework, tidak pernah lewat
    `ReplicatedStorage.Packages.Scythe`. Scythe menyimpan storage-nya di upvalue modul, jadi
    dua salinan modul adalah dua semesta yang terpisah dan handle dari yang satu tidak berarti
    apa-apa bagi yang lain.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--[[
    Dicari, bukan disebut namanya. Nama folder `Bench` itu keputusan mount di
    `bench.project.json`, dan mengganti namanya di sana -- atau menggeser foldernya di Studio
    -- tidak boleh membuat skrip ini mati dengan "index nil" tanpa penjelasan.
]]
local function baseline(name: string): ModuleScript
    for _, child in ReplicatedStorage:GetChildren() do
        local folder = child:FindFirstChild("Baseline")
        if folder ~= nil then
            local module = folder:FindFirstChild(name)
            if module ~= nil and module:IsA("ModuleScript") then
                return module
            end
        end
    end

    error(
        `[HeapProfile] Baseline.{name} tidak ketemu di ReplicatedStorage. `
            .. `Bangun place-nya dengan bench.project.json, bukan default.project.json.`,
        0
    )
end

local Maid = require(baseline("Maid"))
local Scope = require(ReplicatedStorage.Unrest.Util.Scope)

local CONTAINERS = 1000
local ITEMS_PER_CONTAINER = 8
local REPETITIONS = 15
local SETTLE_FRAMES = 6

--[[
    Beri GC inkremental beberapa frame untuk mengejar ketertinggalan.

    Roblox MEMBLOKIR `collectgarbage("collect")` -- satu-satunya argumen yang diizinkan
    adalah `"count"`. Jadi tidak ada cara memaksa koleksi penuh dan menstabilkan heap
    sebelum pengukuran; membiarkan GC inkremental berjalan beberapa frame adalah satu-satunya
    pilihan yang tersisa. Itu juga alasan setiap pembacaan tunggal berisik, dan alasan
    laporan di bawah memakai median.
]]
local function settle(frames: number)
    for _ = 1, frames do
        RunService.Heartbeat:Wait()
    end
end

--[[
    Satu jangkar tingkat-modul yang memegang nilai hasil `build` supaya dia tidak bisa
    dikumpulkan sebelum pembacaan kedua.

    Ini bukan hiasan. Kalau nilainya dilepas sebelum `gcinfo()` yang kedua, GC inkremental
    yang baru saja kita beri waktu berjalan akan membuang persis benda yang sedang kita ukur,
    dan deltanya menyusut ke nol untuk kedua sisi. Yang terukur kemudian bukan "berapa heap
    yang ditahan wadah ini", melainkan "seberapa cepat GC membersihkan sampah" -- pertanyaan
    yang sama sekali berbeda, dan jawabannya sama untuk kedua implementasi.
]]
local anchor = {}

--- Delta heap dalam KB antara sebelum dan sesudah `build`, dengan hasilnya ditahan hidup.
local function measure(label: string, build: () -> any, release: (any) -> ()): number
    settle(SETTLE_FRAMES)
    local before = gcinfo()

    anchor[label] = build()

    settle(SETTLE_FRAMES)
    -- `anchor[label]` masih memegang hasilnya di baris ini. Itu inti dari jangkarnya.
    local after = gcinfo()

    local built = anchor[label]
    anchor[label] = nil
    release(built)

    return after - before
end

--[[
    Median, bukan rata-rata.

    GC inkremental berjalan kapan pun dia mau, jadi satu delta bisa memasukkan sapuan yang
    kebetulan jatuh di tengah pengukuran, atau melewatkan sapuan yang seharusnya jatuh di
    sana. Sampel-sampel semacam itu adalah pencilan sepihak: dia bisa membuat satu bacaan
    jauh lebih besar atau jauh lebih kecil dari yang lain, dan rata-rata akan menyeret hasil
    akhir mengikutinya. Median mengabaikannya.
]]
local function median(values: { number }): number
    local sorted = table.clone(values)
    table.sort(sorted)

    local count = #sorted
    if count % 2 == 1 then
        return sorted[(count + 1) // 2]
    end
    return (sorted[count // 2] + sorted[count // 2 + 1]) / 2
end

local function sample(label: string, build: () -> any, release: (any) -> ()): { number }
    local deltas = table.create(REPETITIONS)
    for run = 1, REPETITIONS do
        deltas[run] = measure(label, build, release)
    end
    return deltas
end

--[[
    Delapan closure dibuat SATU KALI dan ditahan selama skrip hidup, lalu dipakai bersama
    oleh setiap wadah di kedua sisi.

    Closure adalah alokasi. Kalau setiap wadah membuat delapan closure-nya sendiri, delta
    kedua sisi akan didominasi 8000 closure yang identik dan selisih antar-wadah -- satu-
    satunya hal yang sedang ditanyakan -- terkubur di bawahnya. Dibuat di luar pengukuran,
    yang tersisa di dalam delta hanyalah biaya wadahnya sendiri: apa yang dia alokasikan
    untuk dirinya, dan bagaimana dia menyimpan delapan referensi.
]]
local disposables = table.create(ITEMS_PER_CONTAINER)
for index = 1, ITEMS_PER_CONTAINER do
    disposables[index] = function() end
end

--[[
    Kedua builder mengembalikan satu array berisi CONTAINERS entri, jadi array pembungkusnya
    sendiri berbiaya sama di kedua sisi: sebuah handle Scythe adalah `number` dan sebuah Maid
    adalah referensi tabel, dan keduanya menempati satu slot array yang sama besarnya. Yang
    berbeda hanyalah apa yang tergantung di ujung slot itu.
]]
local function buildMaids(): { any }
    local containers = table.create(CONTAINERS)
    for index = 1, CONTAINERS do
        local maid = Maid.new()
        for item = 1, ITEMS_PER_CONTAINER do
            maid:Add(disposables[item])
        end
        containers[index] = maid
    end
    return containers
end

local function releaseMaids(containers: { any })
    for _, maid in containers do
        maid:Destroy()
    end
end

local function buildScopes(): { any }
    local containers = table.create(CONTAINERS)
    for index = 1, CONTAINERS do
        local scope = Scope.scope()
        for item = 1, ITEMS_PER_CONTAINER do
            Scope.add(scope, disposables[item])
        end
        containers[index] = scope
    end
    return containers
end

--[[
    Scope Scythe HARUS dilepas, sedangkan Maid cukup dijatuhkan begitu saja.

    Scythe mendaur ulang slot: `destroy` mengembalikan id-nya ke pool. Kalau 1000 scope
    dibiarkan menggantung setiap pengulangan, storage tingkat-modul Scythe akan tumbuh 15000
    slot selama sesi ini dan setiap pengulangan berikutnya mengukur kebocoran skrip ini,
    bukan biaya sebuah scope.
]]
local function releaseScopes(containers: { any })
    for _, scope in containers do
        Scope.destroy(scope)
    end
end

print("[HeapProfile] mengukur heap Lua, bukan waktu.")
print(
    string.format(
        "[HeapProfile] %d wadah x %d disposable, %d pengulangan, %d frame settle per pembacaan.",
        CONTAINERS,
        ITEMS_PER_CONTAINER,
        REPETITIONS,
        SETTLE_FRAMES
    )
)

local maidDeltas = sample("Maid", buildMaids, releaseMaids)
local scytheDeltas = sample("Scythe", buildScopes, releaseScopes)

local maidMedian = median(maidDeltas)
local scytheMedian = median(scytheDeltas)

print("")
print(string.format("%-24s %14s %14s", "wadah", "sekali (KB)", "median (KB)"))
print(string.rep("-", 54))
print(string.format("%-24s %14.1f %14.1f", "Maid (closure)", maidDeltas[1], maidMedian))
print(string.format("%-24s %14.1f %14.1f", "Scythe (scope)", scytheDeltas[1], scytheMedian))
print(string.rep("-", 54))

if maidMedian ~= 0 then
    local difference = (scytheMedian - maidMedian) / maidMedian * 100
    print(string.format("selisih median: %+.1f%% (Scythe relatif terhadap Maid)", difference))
end
if maidDeltas[1] ~= 0 then
    local firstDifference = (scytheDeltas[1] - maidDeltas[1]) / maidDeltas[1] * 100
    print(string.format("selisih sekali : %+.1f%% (Scythe relatif terhadap Maid)", firstDifference))
end

--[[
    Kolom "sekali" dilaporkan bersama median justru karena keduanya biasanya berbeda jauh
    untuk Scythe, dan perbedaan itu bukan kebisingan melainkan sifat modulnya.
]]
print("")
print("[HeapProfile] Kolom 'sekali' adalah pengulangan pertama: Scythe masih menumbuhkan")
print("              storage SoA-nya di sana. Kolom 'median' adalah keadaan tunak, setelah")
print("              slot didaur ulang dan kapasitasnya tetap hangat -- dan keadaan tunak")
print("              itulah yang dijalani framework, yang membuka dan menutup scope terus")
print("              menerus sepanjang hidupnya.")

--[[
    Delta mengukur ALOKASI, bukan retensi. Angka nol di atas berarti "tidak ada yang baru
    dialokasikan", bukan "tidak ada yang ditahan"; keduanya berbeda dan hanya alat snapshot
    yang bisa membedakannya.
]]
print("")
print("[HeapProfile] PERINGATAN: angka di atas adalah delta alokasi, bukan retensi. Untuk")
print("              memeriksa apa yang masih DITAHAN, nyalakan `Stats.MemoryTrackingEnabled`")
print("              lalu ambil snapshot 'Luau heap' di Developer Console (F9 -> Memory).")
print("              Kalau kamu ingin barisnya punya nama sendiri di sana, bungkus kode yang")
print("              diukur dengan `debug.setmemorycategory(tag)` dan")
print("              `debug.resetmemorycategory()` -- keduanya menandai alokasi THREAD yang")
print("              sedang berjalan, jadi tandai di thread yang sama dengan yang membangun.")
