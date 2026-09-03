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

# Cakupan Adapter

Tabel per kelas: event apa yang ada, dan properti apa yang boleh ditulis sebuah channel.

Adapter menumpuk mengikuti hierarki kelas Roblox lewat `Extends`, jadi setiap baris di bawah
hanya mencantumkan apa yang kelas itu **tambahkan**. Resolusi memilih adapter terdaftar paling
spesifik yang di-`:IsA()` instance-nya, meratakan rantainya (yang turunan menang), lalu
menyimpan hasilnya di cache per `ClassName`.

Cara mendaftarkan adapter-mu sendiri ada di [API Adapters](API-ADAPTERS.md).

---

## Dasar 2D

| Kelas | Extends | Tambahan handler | Tambahan properti bindable |
| --- | --- | --- | --- |
| `GuiBase2d` | — | — | `Active`, `AutoLocalize`, `Selectable` |
| `GuiObject` | `GuiBase2d` | `Hover`, `Unhover`, `Press`, `Release` | `Visible`, `Position`, `Size`, `AnchorPoint`, `AutomaticSize`, `Rotation`, `LayoutOrder`, `ZIndex`, `ClipsDescendants`, `BackgroundColor3`, `BackgroundTransparency`, `BorderColor3`, `BorderSizePixel` |

---

## Tombol

| Kelas | Extends | Tambahan handler | Tambahan properti bindable |
| --- | --- | --- | --- |
| `GuiButton` | `GuiObject` | `Active`, `Secondary` | `AutoButtonColor`, `Modal`, `Selected` |
| `TextButton` | `GuiButton` | `Changed` *(Text)* | himpunan teks † |
| `ImageButton` | `GuiButton` | `Changed` *(Image)* | himpunan gambar ‡, `HoverImage`, `PressedImage` |

`Active` diikat ke `Activated`, bukan `MouseButton1Click`, dengan sengaja: `Activated` sudah
melipat mouse, sentuh, dan gamepad jadi satu event, dan sudah menghormati `Modal` dan `Active`.

---

## Teks

| Kelas | Extends | Tambahan handler | Tambahan properti bindable |
| --- | --- | --- | --- |
| `TextLabel` | `GuiObject` | `Changed` *(Text)* | himpunan teks † |
| `TextBox` | `GuiObject` | `Focus`, `Blur`, `Submit`, `Changed` *(Text)* | himpunan teks †, `PlaceholderText`, `PlaceholderColor3`, `ClearTextOnFocus`, `MultiLine`, `TextEditable` |

---

## Frame dan tampilan

| Kelas | Extends | Tambahan handler | Tambahan properti bindable |
| --- | --- | --- | --- |
| `Frame` | `GuiObject` | — | `Style` |
| `ScrollingFrame` | `GuiObject` | `Changed` *(CanvasPosition)* | `CanvasPosition`, `CanvasSize`, `AutomaticCanvasSize`, `ScrollingEnabled`, `ScrollingDirection`, `ScrollBarThickness`, `ScrollBarImageColor3`, `ScrollBarImageTransparency`, `ElasticBehavior`, `HorizontalScrollBarInset`, `VerticalScrollBarInset` |
| `CanvasGroup` | `GuiObject` | `Changed` *(GroupTransparency)* | `GroupColor3`, `GroupTransparency` |
| `ViewportFrame` | `GuiObject` | — | `Ambient`, `CurrentCamera`, `ImageColor3`, `ImageTransparency`, `LightColor`, `LightDirection` |
| `VideoFrame` | `GuiObject` | `Changed` *(Video)* | `Video`, `Playing`, `Looped`, `TimePosition`, `Volume` |
| `ImageLabel` | `GuiObject` | `Changed` *(Image)* | himpunan gambar ‡ |

---

## Layer collector

`LayerCollector` adalah `GuiBase2d` tapi **bukan** `GuiObject`, dan itu persis alasan kenapa
dia tidak punya event penunjuk sama sekali. `ScreenGui` tidak punya `MouseEnter` dan tidak
punya `BackgroundColor3`; mendeklarasikan salah satunya berarti menjanjikan sesuatu yang tidak
bisa ditepati kelasnya.

| Kelas | Extends | Tambahan handler | Tambahan properti bindable |
| --- | --- | --- | --- |
| `LayerCollector` | `GuiBase2d` | `Changed` *(Enabled)* | `Enabled`, `ResetOnSpawn`, `ZIndexBehavior` |
| `ScreenGui` | `LayerCollector` | — | `DisplayOrder`, `IgnoreGuiInset`, `ClipToDeviceSafeArea`, `SafeAreaCompatibility`, `ScreenInsets` |
| `SurfaceGui` | `LayerCollector` | — | `Adornee`, `Face`, `AlwaysOnTop`, `Brightness`, `LightInfluence`, `MaxDistance`, `PixelsPerStud`, `SizingMode`, `CanvasSize`, `ClipsDescendants` |
| `BillboardGui` | `LayerCollector` | — | `Adornee`, `Size`, `AlwaysOnTop`, `Brightness`, `LightInfluence`, `MaxDistance`, `StudsOffset`, `StudsOffsetWorldSpace`, `ExtentsOffset`, `ExtentsOffsetWorldSpace`, `ClipsDescendants` |

---

## Pengubah UI

Tidak satu pun dari kelas ini punya event, dan itu memang tujuannya: `UIPadding` tidak bisa
diaktifkan, jadi `UnrestCommand` padanya adalah peringatan, bukan misteri. Yang mereka punya
adalah tata letak yang bisa kamu gerakkan dari sebuah channel.

| Kelas | Extends | Tambahan properti bindable |
| --- | --- | --- |
| `UIBase` | — | — |
| `UIComponent` | `UIBase` | — |
| `UILayout` | `UIComponent` | — |
| `UIGridStyleLayout` | `UILayout` | `FillDirection`, `HorizontalAlignment`, `VerticalAlignment`, `SortOrder` |
| `UIListLayout` | `UIGridStyleLayout` | `Padding`, `Wraps`, `ItemLineAlignment`, `HorizontalFlex`, `VerticalFlex` |
| `UIGridLayout` | `UIGridStyleLayout` | `CellSize`, `CellPadding`, `FillDirectionMaxCells`, `StartCorner` |
| `UIPageLayout` | `UIGridStyleLayout` | `Animated`, `Circular`, `EasingDirection`, `EasingStyle`, `GamepadInputEnabled`, `Padding`, `ScrollWheelInputEnabled`, `TouchInputEnabled`, `TweenTime` |
| `UITableLayout` | `UIGridStyleLayout` | `FillEmptySpaceColumns`, `FillEmptySpaceRows`, `MajorAxis`, `Padding` |
| `UIConstraint` | `UIComponent` | — |
| `UIAspectRatioConstraint` | `UIConstraint` | `AspectRatio`, `AspectType`, `DominantAxis` |
| `UISizeConstraint` | `UIConstraint` | `MaxSize`, `MinSize` |
| `UITextSizeConstraint` | `UIConstraint` | `MaxTextSize`, `MinTextSize` |
| `UIPadding` | `UIComponent` | `PaddingTop`, `PaddingBottom`, `PaddingLeft`, `PaddingRight` |
| `UICorner` | `UIComponent` | `CornerRadius` — plus `Changed` |
| `UIGradient` | `UIComponent` | `Color`, `Enabled`, `Offset`, `Rotation`, `Transparency` |
| `UIStroke` | `UIComponent` | `ApplyStrokeMode`, `Color`, `Enabled`, `LineJoinMode`, `Thickness`, `Transparency` |
| `UIScale` | `UIComponent` | `Scale` — plus `Changed` |
| `UIFlexItem` | `UIComponent` | `FlexMode`, `GrowRatio`, `ShrinkRatio`, `ItemLineAlignment`, `FillEmptySpace` |

---

## Permukaan interaksi 3D

Bukan GUI, dan keduanya tidak menggambar apa pun. Tapi desainer menandainya dengan alasan
yang persis sama seperti mereka menandai tombol, dan mengharapkan `Active` berarti "pemainnya
melakukan hal itu" di kedua kasus.

Berbicara dengan kosakata handler yang sama itulah yang membuat satu query bisa memilih
*setiap elemen yang bisa diaktifkan di ruangan ini* tanpa peduli caranya diaktifkan.

| Kelas | Handler | Properti bindable |
| --- | --- | --- |
| `ClickDetector` | `Active` *(MouseClick)*, `Secondary` *(RightMouseClick)*, `Hover` / `Unhover` *(MouseHoverEnter/Leave)* | `MaxActivationDistance`, `CursorIcon` |
| `ProximityPrompt` | `Active` *(Triggered)*, `Hover` / `Unhover` *(PromptShown/PromptHidden)*, `Press` / `Release` *(PromptButtonHoldBegan/Ended)* | `ActionText`, `ObjectText`, `Enabled`, `HoldDuration`, `MaxActivationDistance`, `RequiresLineOfSight`, `KeyboardKeyCode`, `GamepadKeyCode`, `ClickablePrompt`, `Exclusivity`, `Style`, `UIOffset` |

`ClickDetector` tidak punya pasangan turun/naik, jadi mengikat `Press` padanya adalah error,
bukan kebohongan.

---

> † **himpunan teks** — `Text`, `TextColor3`, `TextTransparency`, `TextScaled`, `TextSize`,
> `TextWrapped`, `TextTruncate`, `TextXAlignment`, `TextYAlignment`, `TextStrokeColor3`,
> `TextStrokeTransparency`, `RichText`, `FontFace`, `LineHeight`, `MaxVisibleGraphemes`.
>
> ‡ **himpunan gambar** — `Image`, `ImageColor3`, `ImageTransparency`, `ImageRectOffset`,
> `ImageRectSize`, `ScaleType`, `SliceCenter`, `SliceScale`, `TileSize`, `ResampleMode`.

---

## `Bindable` adalah daftar-izin, dan itu disengaja

Nilai channel bisa datang dari server. Kalau `UnrestBind` menerima nama properti apa saja,
sebuah string yang diterbitkan cuma berjarak satu atribut dari menulis `Parent`, `Adornee`,
atau `CurrentCamera` pada instance sembarangan.

Jadi setiap adapter mendaftar **dengan tangan** properti mana yang boleh ditulis nilai
channel — dan sisanya ditolak dengan peringatan yang menyebutkan elemennya, kelasnya, dan apa
yang kelas itu **memang** dukung.

---

## `ValueProperty` — gagasan yang sama, arah sebaliknya

`ValueProperty` adalah satu properti yang berarti "nilai elemen ini". Dia adalah:

* bawaan `UnrestBind`,
* properti yang diawasi `Changed`,
* nilai yang dilaporkan `Submit`.

Registry **mensintesis** binder `Changed` darinya, jadi adapter yang menulis
`ValueProperty = "Text"` mendapat `Changed` secara gratis, dan keduanya tidak akan pernah bisa
melenceng.

Sebuah kelas hanya mendapat `ValueProperty` kalau dia benar-benar punya satu nilai yang jelas.
`Frame` tidak punya, jadi mengikat `Changed` padanya adalah kesalahan yang layak kamu dengar,
bukan langganan ke ketiadaan. `UICorner` dan `UIScale` masing-masing punya persis satu
properti, jadi keduanya punya. `UIListLayout` punya sembilan, jadi dia tidak punya.

Daftar lengkap kelas mana punya `ValueProperty` apa ada di
[Kosakata Handler](UI-HANDLERS.md), bagian 4.2.
