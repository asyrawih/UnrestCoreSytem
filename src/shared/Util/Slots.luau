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
    Unrest / Util / Slots

    One rule, written once: how a list of handlers survives being edited while something is
    walking it.

    `Signal` and `Bridge` both dispatch by walking their handler list by index, without
    copying it -- a copy per fire is a table per published value, per adopted element, per
    click. That makes removal the hard case. Taking a handler out with `table.remove` shifts
    every later handler down one, out from under the indices the running loop still holds, so
    the loop skips a handler or calls one twice.

    So a slot holds a live value or `false`, NEVER nil: a dropped handler is replaced in
    place, the array stays dense, `#` keeps meaning what the loop needs it to mean, and the
    holes are squeezed out once no dispatch is left on the stack.

    The counter that decides "no dispatch is left" belongs to the caller, because the two count
    different things -- a `Signal` counts fires of itself, a `Bridge` counts dispatches of one
    command name -- but it must be a counter and not a boolean in both. A handler is allowed to
    fire the signal it is running under, or dispatch the command it is handling; a boolean
    would be cleared by the inner call and let it compact the array the outer loop is still
    indexing into.

    This module exists because the rule was written twice, in two files, identically. That is
    the shape of every bug this repository has produced.
]]

local Slots = {}

--- A live value, or the hole left by one dropped mid-dispatch. Never nil.
export type Slot<T> = T | false

--[[
    Squeezes the holes out, preserving order.

    Only safe with no dispatch on the stack: it moves live values to lower indices, which is
    precisely what a running loop's indices cannot survive. The caller's depth counter is what
    proves that, and calling this while it is above zero is the one way to misuse this module.
]]
function Slots.compact<T>(slots: { Slot<T> }): ()
    local count = #slots
    local write = 0

    --[[
        `~= false` rather than truthiness, because a slot's value may itself be falsy in the
        general case. The live value is moved by re-reading the index rather than through the
        local the test narrowed: Luau widens the `false` half of a generic `T | false` to
        `boolean` when it refines, and the unnarrowed read is already the element type.
    ]]
    for read = 1, count do
        if slots[read] ~= false then
            write += 1
            if write ~= read then
                slots[write] = slots[read]
            end
        end
    end

    for _ = count, write + 1, -1 do
        table.remove(slots)
    end
end

--- Empties the list in place, leaving holes for a dispatch that is still walking it.
function Slots.vacateAll<T>(slots: { Slot<T> }): ()
    for index = 1, #slots do
        slots[index] = false
    end
end

return Slots
