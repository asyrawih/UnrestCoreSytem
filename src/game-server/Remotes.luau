--!strict
--[[
    Dua remote, dibuat di satu tempat supaya server dan client tidak menebak namanya.

    `Niat` naik: client meminta sesuatu. `Kabar` turun: server memberi tahu satu pemain
    bahwa sebuah channel punya nilai baru. Framework tidak lagi membawa apa pun antar realm,
    jadi jembatannya memang milik game.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function ensure(name: string): RemoteEvent
    local found = ReplicatedStorage:FindFirstChild(name)
    if found and found:IsA("RemoteEvent") then
        return found
    end

    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = ReplicatedStorage
    return remote
end

return {
    Niat = ensure("Niat"),
    Kabar = ensure("Kabar"),
}
