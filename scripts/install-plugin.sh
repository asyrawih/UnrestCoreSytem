#!/usr/bin/env bash
#                      ,-.--, ,--.-,,-,--,.--, .-.--, .-._         ,---.      .-._
#   _,..---._ .--.-.  /=/, .'/==/  /|=|  ||  |=| -\==Y==/ \  .-._.--.'  \    /==/ \  .-._
# /==/,   -  \\==\ -\/=/- /  |==|_ ||=|, ||  `-' _|==|==|, \/ /, |==\-/\ \   |==|, \/ /, /
# |==|   _   _\\==\ `-' ,/   |==| ,|/=| _|\     , |==|==|-  \|  |/==/-|_\ |  |==|-  \|  |
# |==|  .=.   | |==|,  - |   |==|- `-' _ | `--.  -|==|==| ,  | -|\==\,   - \ |==| ,  | -|
# |==|,|   | -|/==/   ,   \  |==|  _     |     \_ |==|==| -   _ |/==/ -   ,| |==| -   _ |
# |==|  '='   /==/, .--, - \ |==|   .-. ,\     |  \==\==|  /\ , /==/-  /\ - \|==|  /\ , |
# |==|-,   _`/\==\- \/=/ , / /==/, //=/  |      \ /==/==/, | |- \==\ _.\=\.-'/==/, | |- |
# `-.`.____.'  `--`-'  `--`  `--`-' `-`--`       `--``--`./  `--``--`        `--`./  `--`
#
# https://discord.gg/MZYTABSSfb

#
# Build the Studio plugin and drop it where Studio looks for local plugins.
#
# Studio reloads a local plugin whenever its file changes, so re-running this while Studio
# is open is the whole edit loop: build, and the panel comes back with the new code.
#
# macOS / Linux:  ~/Documents/Roblox/Plugins
# Windows:        %LOCALAPPDATA%\Roblox\Plugins   (run the rojo line below by hand there)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS="${ROBLOX_PLUGINS_DIR:-$HOME/Documents/Roblox/Plugins}"

mkdir -p "$PLUGINS"
rojo build "$REPO/plugin/default.project.json" --output "$PLUGINS/UnrestPlugin.rbxm"

echo "Installed: $PLUGINS/UnrestPlugin.rbxm"
echo "Studio picks it up on the next reload; the toolbar button is called \"Unrest\"."
