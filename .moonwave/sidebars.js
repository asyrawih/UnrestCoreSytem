/**
 * Sidebar untuk situs dokumentasi UnrestCoreSystem.
 *
 * Berkas ini ditulis tangan, bukan dihasilkan otomatis, supaya `docs/` bisa tetap berupa
 * folder datar berisi berkas Markdown tanpa front matter. Pengelompokan, urutan, dan label
 * semuanya tinggal di sini; sumber Markdown-nya tidak disentuh.
 *
 * Konvensi:
 *   - seluruh dokumentasi ditulis dalam bahasa Indonesia, jadi tidak ada penanda bahasa;
 *   - kategori Usulan terpisah dari yang lain, dan halaman indeksnya mengatakan alasannya,
 *     karena isinya menggambarkan kode yang belum ada.
 *
 * Catatan pemeliharaan: karena sidebar ini eksplisit, berkas BARU yang ditaruh di docs/
 * tetap mendapat URL-nya sendiri tapi TIDAK akan muncul di sidebar sampai ditambahkan di
 * bawah. Itu ongkos yang dibayar supaya sumber Markdown-nya bebas front matter.
 */
module.exports = {
    defaultSidebar: [
        {
            type: "doc",
            id: "intro",
            label: "Mulai di sini",
        },
        {
            type: "category",
            label: "Panduan",
            collapsed: false,
            link: {
                type: "generated-index",
                title: "Panduan",
                description:
                    "Baca berurutan. Halaman-halaman ini menggambarkan framework seperti yang ada di src/ hari ini.",
                slug: "/category/guides",
            },
            items: [
                { type: "doc", id: "MENTAL-MODEL", label: "Model Mental" },
                { type: "doc", id: "GETTING-STARTED", label: "Panduan Memulai" },
                { type: "doc", id: "GAME-MODULE", label: "ModuleScript Game" },
                { type: "doc", id: "ARCHITECTURE", label: "Arsitektur" },
            ],
        },
        {
            type: "category",
            label: "Referensi API",
            collapsed: false,
            link: {
                type: "generated-index",
                title: "Referensi API",
                description:
                    "Setiap API framework, satu per satu. Diverifikasi langsung terhadap src/shared/Types.luau.",
                slug: "/category/api",
            },
            items: [
                { type: "doc", id: "API-OVERVIEW", label: "Peta API" },
                { type: "doc", id: "API-UNREST", label: "Unrest" },
                { type: "doc", id: "API-BRIDGE", label: "Bridge" },
                { type: "doc", id: "API-CORE", label: "Core & System" },
                { type: "doc", id: "API-ELEMENTS", label: "Elements & Query" },
                { type: "doc", id: "API-ADAPTERS", label: "Adapters" },
                { type: "doc", id: "API-CONTRACTS", label: "Contracts" },
                { type: "doc", id: "API-PRESETS", label: "Presets" },
                { type: "doc", id: "API-TRANSPORT", label: "Transport" },
            ],
        },
        {
            type: "category",
            label: "Referensi UI",
            collapsed: false,
            link: {
                type: "generated-index",
                title: "Referensi UI",
                description:
                    "Bahan rujukan, bukan bacaan dari depan ke belakang. Buka saat kamu butuh jawaban.",
                slug: "/category/ui",
            },
            items: [
                { type: "doc", id: "UI-BINDING", label: "Ikhtisar" },
                { type: "doc", id: "UI-ADOPTION", label: "Adopsi & Tag" },
                { type: "doc", id: "UI-ATTRIBUTES", label: "Referensi Atribut" },
                { type: "doc", id: "UI-HANDLERS", label: "Kosakata Handler" },
                { type: "doc", id: "UI-ADAPTERS", label: "Cakupan Adapter" },
            ],
        },
        {
            type: "category",
            label: "Operasional",
            collapsed: false,
            link: {
                type: "generated-index",
                title: "Operasional",
                description: "Keamanan, dan apa yang harus dilakukan saat ada yang salah.",
                slug: "/category/operations",
            },
            items: [
                { type: "doc", id: "REMOTE-SECURITY", label: "Keamanan Remote" },
                { type: "doc", id: "TROUBLESHOOTING", label: "Pemecahan Masalah" },
            ],
        },
        {
            type: "category",
            label: "Usulan — belum diimplementasikan",
            collapsed: true,
            link: {
                type: "generated-index",
                title: "Usulan — belum diimplementasikan",
                description:
                    "Rancangan, bukan dokumentasi. Isi bagian ini menggambarkan kode yang belum ada di src/. Jangan membacanya sebagai deskripsi perilaku yang sudah berjalan.",
                slug: "/category/proposals",
            },
            items: [
                { type: "doc", id: "PROPOSAL-CONTROLS", label: "Controls (v2)" },
                { type: "doc", id: "PROPOSAL-TRANSPORT", label: "Transport" },
            ],
        },
    ],
};
