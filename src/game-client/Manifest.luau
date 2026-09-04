--!strict
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
    Game -- Manifest

    Everything this game adds to the framework's vocabulary, as data and nothing else. Two
    readers, one table:

      * the client bootstrap requires it and calls `Presets.Register` / `Schemas.Register`
        per entry, which is what makes the names real at Play;
      * the Studio tooling finds this ModuleScript by its `UnrestManifest` tag
        (`Manifest.meta.json`) and reads the same table in edit mode, where nothing has run
        and both registries are empty.

    That is the whole reason it is a separate, dependency-free file. A preset declared inline
    in a bootstrap is invisible to a plugin, and `Tooling/Lint` would then warn about every
    `UnrestPreset` on the screen -- the tooling complaining about its own blindness. Keep it
    pure: no `require`, no service, no function, nothing but the table.

    Both lists start empty, and an empty manifest is a complete one. The shapes are below.

        Presets = {
            TombolUtama = { UnrestCommand = "Toko.Beli", UnrestCooldown = 0.25 },
        },
        Widgets = {
            { Name = "Dial", Required = { "DialFace", "DialNeedle" }, Classes = { DialFace = "GuiObject" } },
        },

    A preset key must be an `Unrest*` attribute name, and may not be `UnrestWidget`: a preset
    is inherited by every part under a root, and a widget's identity belongs to the root alone.
    `Presets.Register` refuses it.
]]

--- One preset: a bundle of `Unrest*` attribute names and the values they stand for.
export type Preset = { [string]: any }

--- One widget schema, matching `Widgets/Schemas.WidgetSchema` without requiring it.
export type Widget = {
    Name: string,
    Required: { string },
    Optional: { string }?,
    --- Minimum class per role, tested with `:IsA()`.
    Classes: { [string]: string }?,
}

export type Manifest = {
    Presets: { [string]: Preset },
    Widgets: { Widget },
}

local Manifest: Manifest = {
    Presets = {},
    Widgets = {},
}

return table.freeze(Manifest)
