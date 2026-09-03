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
# Point this clone's hooks at .githooks/.
#
# Git hooks are not cloned, so every clone runs this once. `core.hooksPath` is used rather
# than copying files into .git/hooks so the hook stays version-controlled and a fix reaches
# everyone with a pull.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$HOOK_DIR" rev-parse --show-toplevel)"

chmod +x "$HOOK_DIR/pre-commit" "$HOOK_DIR/apply-banner.sh" "$HOOK_DIR/install.sh"
git -C "$ROOT" config core.hooksPath .githooks

echo "hooks: core.hooksPath -> .githooks"
echo "hooks: new files added to a commit will be stamped with the banner."
echo "hooks: uninstall with 'git config --unset core.hooksPath'"
