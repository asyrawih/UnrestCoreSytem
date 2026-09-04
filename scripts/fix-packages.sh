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
# Repairs the packages Wally installs, for the one that ships broken.
#
# `elitriare/bytenet-max@1.0.0` requires `namespaces.namespacesDependencies` from two files
# (`dataTypes/struct.luau`, `namespaces/namespace.luau`) but publishes the module as
# `namespaceDependencies.luau`, so the whole package fails to load and takes `GameNet` with it.
# The upstream repository has the same mismatch. Renaming the file is the smallest fix that
# touches nothing the game reads. Run this after every `wally install`; it is idempotent.
set -euo pipefail

cd "$(dirname "$0")/.."

fixed=0
for dir in Packages/_Index/elitriare_bytenet-max@*/bytenet-max/src/namespaces; do
    [ -d "$dir" ] || continue
    if [ -f "$dir/namespaceDependencies.luau" ] && [ ! -f "$dir/namespacesDependencies.luau" ]; then
        mv "$dir/namespaceDependencies.luau" "$dir/namespacesDependencies.luau"
        echo "fixed: $dir/namespaceDependencies.luau -> namespacesDependencies.luau"
        fixed=1
    fi
done

if [ "$fixed" -eq 0 ]; then
    echo "nothing to fix"
fi
