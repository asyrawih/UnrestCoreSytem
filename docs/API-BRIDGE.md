# API — `Bridge`

`Bridge` adalah controller framework: satu-satunya jalan antara kode yang memiliki state dan
layar yang menampilkannya.

```luau
local bridge = unrest.Bridge
```

Definisi tipenya ada di `src/shared/Types.luau`, `export type Bridge`.

**Ini bus lokal.** Tidak ada satu pun yang menyeberang mesin. `Dispatch` di client hanya
menjangkau handler di client itu juga; `Publish` di server hanya terlihat oleh kode di server
itu juga. Kalau kamu butuh menyeberang, itu urusan remote milik game-mu — lihat
[Menyeberang mesin](#menyeberang-mesin) di bawah.

---

## Dua arah, empat kata kerja

```
  Kode yang punya state  ──Publish──▶  Bridge  ──▶  Elemen di Studio
            ▲                            │
            └──────────Dispatch──────────┘
```

| Arah | Metode | Bentuk |
| --- | --- | --- |
| state → UI | `Publish` / `Subscribe` / `Peek` | **ditahan**, jadi pelanggan yang telat tetap dapat nilai sekarang |
| UI → state | `Dispatch` | kirim dan lupakan, tidak pernah yield |
| — | `Handle` | memasang handler; beberapa handler boleh berbagi satu nama |

Yang membuat lapisan ini berharga: **atribut bukan mekanisme kedua.** `UnrestCommand` di
Studio lewat `Bridge:Dispatch` yang sama persis dan sampai ke handler yang sama persis
dengan Luau tulisan tangan. Dari sisi seberang Bridge, layar yang dirakit di Studio dan layar
yang dirakit di kode tidak bisa dibedakan.

---

## Field

### `Context: RuntimeContext`

`"Server"` atau `"Client"`. Sama dengan `unrest.Context`.

---

## Channel — state yang mengalir keluar

### `Bridge:Publish(channel: string, value: any): ()`

Menerbitkan state yang **ditahan**: nilainya disimpan, dan setiap pelanggan berikutnya
langsung menerimanya.

```luau
bridge:Publish("Koin", 120)
```

Penahanan itu yang membuat urutan mount berhenti penting. Label yang baru ditandai tiga
puluh detik setelah jumlah koin terakhir diterbitkan tetap menampilkan angka yang benar di
frame pertamanya — tanpa kode, cukup `UnrestChannel = "Koin"`.

Pelanggan dipanggil **inline**. Pelanggan yang yield akan menahan `Publish` itu sendiri, jadi
jangan yield di dalamnya; kalau butuh, bungkus dengan `task.spawn` sendiri.

### `Bridge:Subscribe(channel: string, handler: (value: any) -> ()): Connection`

Berlangganan. Mengembalikan `Connection` dengan `:Disconnect()`.

```luau
local connection = bridge:Subscribe("Koin", function(nilai)
    print("koin sekarang:", nilai)
end)
```

**Kalau channel-nya sudah punya nilai, handler-mu langsung dipanggil** dengan nilai itu —
lewat `task.spawn`, jadi panggilan pertama itu terjadi **setelah** baris `Subscribe` selesai,
bukan di dalamnya. Itu disengaja: berlangganan biasanya terjadi saat sebuah elemen sedang
diadopsi, dan handler yang yield tidak boleh menahan adopsi sisa layarnya.

Simpan `Connection`-nya di sebuah cleanup scope supaya lepasnya satu baris dan tidak bisa
setengah jadi:

```luau
unrest.Scope.add(scope, bridge:Subscribe("Koin", perbarui))
```

### `Bridge:Peek(channel: string): any`

Nilai terakhir yang diterbitkan di channel itu, atau `nil`. Tidak yield, tidak membuat
langganan.

```luau
if bridge:Peek("Koin") == nil then
    unrest:Dispatch("Dompet.Muat", nil)
end
```

Ini yang kamu pakai saat perintah yang benar bergantung pada keadaan sekarang — persis batas
di mana atribut sudah tidak cukup dan kamu turun ke `Unrest:Query`.

---

## Perintah — niat yang mengalir masuk

### `Bridge:Dispatch(command: string, payload: any): ()`

Mengirim sebuah niat ke setiap handler yang terdaftar untuk nama itu. **Tidak pernah yield.**
Tidak mengembalikan apa pun.

```luau
bridge:Dispatch("Toko.Beli", { Player = player, Item = "Pedang" })
```

**Perintah tanpa satu pun handler adalah no-op yang diam**, bukan error. Layar sering dibangun
sebelum kode di belakangnya, dan tombol yang belum melakukan apa-apa tidak seharusnya
memuntahkan peringatan tiap kali diklik.

Yang **tidak** diam adalah handler yang melempar error: dia ditangkap, dilaporkan lengkap
dengan traceback-nya, dan handler lain tetap jalan. Satu sistem yang rusak tidak boleh
menelan klik untuk semua pendengar lainnya.

Handler dijalankan **inline**, satu per satu. Handler yang yield menahan dispatch itu.

### `Bridge:Handle(command: string, handler: CommandHandler): Connection`

Memasang handler. Mengembalikan `Connection`.

```luau
local connection = bridge:Handle("Toko.Beli", function(payload)
    local pembeli = payload.Player :: Player
    toko:beli(pembeli, payload.Item)
end)
```

`CommandHandler` adalah `(payload: any) -> ()`.

**Tidak ada argumen `source`.** Setiap dispatch itu lokal — pemanggilnya ada di sisi yang sama
dari call stack. Kalau kamu butuh tahu pemain mana yang meminta, pemain itu masuk lewat
remote milik game-mu dan kamu yang menaruhnya di payload, seperti `payload.Player` di atas.

**Beberapa handler boleh berbagi satu nama.** Semuanya dipanggil, dalam urutan pendaftaran.

**Payload tidak divalidasi oleh siapa pun.** Tidak ada kontrak dan tidak ada gerbang di
lapisan ini. Kalau payload-nya berasal dari client, yang memeriksanya adalah kode yang
menerima paketnya — sebelum `Dispatch` dipanggil, bukan sesudahnya.

> Satu detail halus: `Disconnect` yang dipanggil **selama** sebuah dispatch berlaku **di
> dalam** dispatch itu. Handler yang belum tersentuh tidak akan jalan. Itu semantik sinyal
> yang normal, dan itu memang yang diminta oleh pemanggil yang men-disconnect.

---

## Menyeberang mesin

Framework tidak menyediakannya, dan itu keputusan: dia abstraksi UI, bukan pustaka jaringan.
Pola sambungannya cuma dua baris di masing-masing sisi. Game contoh di repo ini memakai
ByteNet di `src/game-net`:

```luau
-- src/game-server/init.server.luau — paket masuk jadi niat
GameNet.packets.Beli.listen(function(data, player: Player?)
    if player == nil or typeof(data) ~= "table" or typeof(data.Barang) ~= "string" then
        return
    end
    unrest.Bridge:Dispatch("Toko.Beli", { Player = player, Item = data.Barang })
end)
```

```luau
-- src/game-client/Shop.luau — paket masuk jadi state yang bisa diikuti UI
GameNet.packets.Koin.listen(function(data)
    bridge:Publish("Koin", data.Nilai)
end)
```

Tiga hal yang harus kamu pegang sendiri, karena tidak ada yang memegangnya untukmu:

* **Identitas datang dari transport, tidak pernah dari pesan.** `player` di atas adalah
  argumen kedua yang diserahkan ByteNet, diteruskan apa adanya dari `OnServerEvent`. Paket
  `Beli` sengaja tidak punya field pemain, dan memang tidak boleh punya.
* **Periksa bentuk `data` di batas itu.** Skema paket menjamin `Barang` bertipe string
  kalau buffer-nya berhasil didekode, tapi berhasil didekode bukan berarti masuk akal.
* **Server tidak menyuruh client.** Arah itu adalah state di channel, bukan perintah. Server
  tidak bisa memverifikasi client menurut, jadi perintah ke arah sana cuma saran.

---

## `Bridge:Destroy(): ()`

Mengosongkan channel dan handler, dan membereskan semua koneksi.

Kamu hampir tidak akan pernah memanggil ini, dan framework tidak memanggilnya dari
`Unrest:Stop`. Setiap metode lain melempar error setelah Bridge dihancurkan.
