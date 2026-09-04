--!strict
-- DIHASILKAN oleh Tooling/Vocab dari StarterGui pada 2026-09-04. Jangan disunting; ekspor ulang.

export type Role =
    "PlayerMenu"
    | "ServerInfoClose"
    | "ServerInfoConnections"
    | "ServerInfoDivider"
    | "ServerInfoItems"
    | "ServerInfoJoin"
    | "ServerInfoOthers"
    | "ServerInfoPanel"
    | "ServerInfoStatus"
    | "ServerListButton"
    | "ServerListClose"
    | "ServerListItems"
    | "ServerListPanel"
    | "ServerListRefresh"
    | "ServerListStatus"
    | "SliderFill"
    | "SliderKnob"
    | "SliderLabel"
    | "SliderTrack"
    | "ToggleButton"
    | "ToggleKnob"
    | "ToggleLabel"
export type Group = "Efek" | "Fullscreen" | "Musik" | "Notifikasi"
export type Widget = "Slider" | "Toggle"

local Vocab = {
    Roles = table.freeze({
        --- InGame.PlayerMenu (Frame)
        PlayerMenu = "PlayerMenu" :: "PlayerMenu",
        --- InGame.ServerListContainer.SidePanelServer.Header.CloseButton (TextButton)
        ServerInfoClose = "ServerInfoClose" :: "ServerInfoClose",
        --- InGame.ServerListContainer.SidePanelServer.List.ConnectionsSection (Frame)
        ServerInfoConnections = "ServerInfoConnections" :: "ServerInfoConnections",
        --- InGame.ServerListContainer.SidePanelServer.List.Divider (Frame)
        ServerInfoDivider = "ServerInfoDivider" :: "ServerInfoDivider",
        --- InGame.ServerListContainer.SidePanelServer.List (ScrollingFrame)
        ServerInfoItems = "ServerInfoItems" :: "ServerInfoItems",
        --- InGame.ServerListContainer.SidePanelServer.JoinButton (TextButton)
        ServerInfoJoin = "ServerInfoJoin" :: "ServerInfoJoin",
        --- InGame.ServerListContainer.SidePanelServer.List.OthersSection (Frame)
        ServerInfoOthers = "ServerInfoOthers" :: "ServerInfoOthers",
        --- InGame.ServerListContainer.SidePanelServer (Frame)
        ServerInfoPanel = "ServerInfoPanel" :: "ServerInfoPanel",
        --- InGame.ServerListContainer.SidePanelServer.StatusLabel (TextLabel)
        ServerInfoStatus = "ServerInfoStatus" :: "ServerInfoStatus",
        --- top.Container.E_ServerListButton (TextButton)
        ServerListButton = "ServerListButton" :: "ServerListButton",
        --- InGame.ServerListContainer.ServerListFrame.Header.CloseButton (TextButton)
        ServerListClose = "ServerListClose" :: "ServerListClose",
        --- InGame.ServerListContainer.ServerListFrame.List (ScrollingFrame)
        ServerListItems = "ServerListItems" :: "ServerListItems",
        --- InGame.ServerListContainer (Frame)
        ServerListPanel = "ServerListPanel" :: "ServerListPanel",
        --- InGame.ServerListContainer.ServerListFrame.RefreshButton (TextButton)
        ServerListRefresh = "ServerListRefresh" :: "ServerListRefresh",
        --- InGame.ServerListContainer.ServerListFrame.StatusLabel (TextLabel)
        ServerListStatus = "ServerListStatus" :: "ServerListStatus",
        --- SliderMulti.Efek.Track.Fill (Frame), SliderMulti.Musik.Track.Fill (Frame)
        SliderFill = "SliderFill" :: "SliderFill",
        --- SliderMulti.Efek.Track.Knob (TextButton), SliderMulti.Musik.Track.Knob (TextButton)
        SliderKnob = "SliderKnob" :: "SliderKnob",
        --- SliderMulti.Efek.Judul (TextLabel), SliderMulti.Musik.Judul (TextLabel)
        SliderLabel = "SliderLabel" :: "SliderLabel",
        --- SliderMulti.Efek.Track (Frame), SliderMulti.Musik.Track (Frame)
        SliderTrack = "SliderTrack" :: "SliderTrack",
        --- ToggleDemo.Fullscreen.Button (TextButton), ToggleDemo.Notifikasi.Button (TextButton)
        ToggleButton = "ToggleButton" :: "ToggleButton",
        --- ToggleDemo.Fullscreen.Button.Knob (Frame), ToggleDemo.Notifikasi.Button.Knob (Frame)
        ToggleKnob = "ToggleKnob" :: "ToggleKnob",
        --- ToggleDemo.Fullscreen.Label (TextLabel), ToggleDemo.Notifikasi.Label (TextLabel)
        ToggleLabel = "ToggleLabel" :: "ToggleLabel",
    }),
    Groups = table.freeze({
        --- SliderMulti.Efek (Frame), SliderMulti.Efek.Judul (TextLabel), SliderMulti.Efek.Track (Frame), SliderMulti.Efek.Track.Fill (Frame), SliderMulti.Efek.Track.Knob (TextButton)
        Efek = "Efek" :: "Efek",
        --- ToggleDemo.Fullscreen (Frame), ToggleDemo.Fullscreen.Button (TextButton), ToggleDemo.Fullscreen.Button.Knob (Frame), ToggleDemo.Fullscreen.Label (TextLabel)
        Fullscreen = "Fullscreen" :: "Fullscreen",
        --- SliderMulti.Musik (Frame), SliderMulti.Musik.Judul (TextLabel), SliderMulti.Musik.Track (Frame), SliderMulti.Musik.Track.Fill (Frame), SliderMulti.Musik.Track.Knob (TextButton)
        Musik = "Musik" :: "Musik",
        --- ToggleDemo.Notifikasi (Frame), ToggleDemo.Notifikasi.Button (TextButton), ToggleDemo.Notifikasi.Button.Knob (Frame), ToggleDemo.Notifikasi.Label (TextLabel)
        Notifikasi = "Notifikasi" :: "Notifikasi",
    }),
    Widgets = table.freeze({
        --- SliderMulti.Efek (Frame), SliderMulti.Musik (Frame)
        Slider = "Slider" :: "Slider",
        --- ToggleDemo.Fullscreen (Frame), ToggleDemo.Notifikasi (Frame)
        Toggle = "Toggle" :: "Toggle",
    }),
}

return table.freeze(Vocab)
