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
    The two channel names this feature publishes on, in the one place that owns them.

    A channel name is a string that has to be identical in two files and, for anything a
    designer binds, in Studio as well -- and a misspelled one is SILENT. `Bridge:Publish` to a
    name nobody subscribes to is not an error, and `Subscribe` to a name nobody publishes just
    never fires. Lifting both here is what turns that silence into a require.
]]
return table.freeze({
    --- Boolean. Whether the panel is open. Written by the button, read by the animation.
    Open = "ServerList.Open",
    --- `{ Directory.Entry }`. The last directory the server sent, newest wins.
    Servers = "ServerList.Servers",
    --[[
        The `JobId` of the row the player picked, or `""` for none.

        An empty string rather than nil, because a retained channel cannot tell "published
        nothing" apart from "never published": `Peek` answers nil to both, and a side panel
        would have no way to know whether it had ever been open.
    ]]
    Selected = "ServerList.Selected",
})
