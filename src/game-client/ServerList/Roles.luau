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
    Finding the parts of a panel by the role a designer wrote on them.

    `Unrest:Query` is the right tool when the framework should watch something for you. It is
    the wrong tool for "which label inside THIS clone shows the count": a query matches every
    such label on screen, and the caller would then have to work out which of them belongs to
    the row it just made. These three walk one subtree instead, and the caller already knows
    which subtree it means.

    NO FALLBACK TO `Instance.Name`, WHICH IS THE DIFFERENCE FROM `Selector.roleOf`. That one
    falls back deliberately, so a query keeps working before anybody has typed an attribute.
    Here the opposite is wanted: these parts were marked on purpose, and a fallback would let
    any child that happens to be called `CountLabel` claim a role nobody gave it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Unrest.Constants)

local Roles = {}

--- The role written on this instance, or nil. Never its name.
function Roles.of(instance: Instance): string?
    local role = instance:GetAttribute(Constants.Attributes.Role)
    if typeof(role) == "string" and #role > 0 then
        return role
    end
    return nil
end

--- The first descendant carrying `role`, searching `root`'s whole subtree.
function Roles.find(root: Instance, role: string): Instance?
    for _, descendant in root:GetDescendants() do
        if Roles.of(descendant) == role then
            return descendant
        end
    end
    return nil
end

--[[
    The nearest ANCESTOR carrying `role`, or `node` itself when there is none.

    This exists because the interesting parts of a panel are usually siblings rather than
    children. A status line sits above the scrolling frame, not inside it, so a search that
    started at the list found nothing and left the label showing whatever placeholder text it
    shipped with -- which looks exactly like a label that works.

    The walk stops at the first `LayerCollector`: a screen is the widest thing a panel can be.
]]
function Roles.owner(node: Instance, role: string): Instance
    local current: Instance? = node.Parent
    while current ~= nil and not current:IsA("LayerCollector") do
        if Roles.of(current) == role then
            return current
        end
        current = current.Parent
    end
    return node
end

return Roles
