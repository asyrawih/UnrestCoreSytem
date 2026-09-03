#!/usr/bin/env bash
#
# Stamp the UnrestCoreSystem banner on the top of a source file.
#
# The art lives in exactly one place -- .githooks/banner.txt -- and this script wraps it in
# whatever comment syntax the target file speaks. That way the art is never duplicated per
# language, and re-branding is a one-file edit.
#
# Usage:
#   .githooks/apply-banner.sh <file> [<file>...]   stamp these files
#   .githooks/apply-banner.sh --all                stamp every tracked file that can take it
#   .githooks/apply-banner.sh --check <file>...    exit 1 if any file is missing the banner
#
# A file is skipped, silently, when it already carries the banner, when its format has no
# comment syntax (JSON), or when it is not ours to touch (vendor/, licences, lockfiles).

set -euo pipefail

DISCORD_URL="https://discord.gg/MZYTABSSfb"
# Any file containing this substring is considered already stamped.
MARKER="discord.gg/MZYTABSSfb"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANNER_FILE="$HOOK_DIR/banner.txt"

if [ ! -f "$BANNER_FILE" ]; then
	echo "apply-banner: missing $BANNER_FILE" >&2
	exit 1
fi

# --------------------------------------------------------------------------------------
# Which files are off limits
# --------------------------------------------------------------------------------------

# Paths are matched repo-relative, as globs.
is_skipped() {
	case "$1" in
		# Third-party code. Reformatting vendor/Scythe.luau would modify an MPL-2.0 file
		# and make it undiffable against upstream -- see NOTICE.md and .styluaignore.
		vendor/*) return 0 ;;
		# Licence texts must stay verbatim.
		LICENSE | LICENSE-* | */LICENSE | */LICENSE-*) return 0 ;;
		# Generated or installed trees.
		node_modules/* | build/* | Packages/* | DevPackages/* | ServerPackages/*) return 0 ;;
		*.lock | package-lock.json) return 0 ;;
		# JSON has no comment syntax; .luaurc is JSON too.
		*.json | .luaurc) return 0 ;;
		# The banner's own source.
		.githooks/banner.txt) return 0 ;;
		# Anything binary-ish.
		*.png | *.jpg | *.jpeg | *.gif | *.svg | *.ico | *.woff | *.woff2 | *.ttf) return 0 ;;
		*.rbxl | *.rbxlx | *.rbxm | *.rbxmx) return 0 ;;
	esac
	return 1
}

# Echoes the comment style for a path, or nothing when the format cannot hold a comment.
style_for() {
	local path="$1" base
	base="$(basename "$path")"

	case "$base" in
		.gitignore | .gitattributes | .styluaignore | .editorconfig | Makefile | Dockerfile)
			echo hash
			return
			;;
	esac

	case "$path" in
		*.luau | *.lua) echo lua ;;
		*.md | *.markdown) echo markdown ;;
		*.css | *.scss | *.js | *.mjs | *.cjs | *.jsx | *.ts | *.tsx) echo cblock ;;
		*.toml | *.yml | *.yaml | *.sh | *.bash | *.zsh | *.py | *.conf | *.cfg | *.ini) echo hash ;;
		*) echo "" ;;
	esac
}

# --------------------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------------------

render_banner() {
	case "$1" in
		lua)
			# A Luau block comment. The art contains no `]`, so it cannot close early.
			printf -- '--[[\n'
			cat "$BANNER_FILE"
			printf -- '\n    %s\n]]\n' "$DISCORD_URL"
			;;
		cblock)
			# The art contains no `*`, so it cannot close the comment early.
			printf -- '/*\n'
			cat "$BANNER_FILE"
			printf -- '\n    %s\n*/\n' "$DISCORD_URL"
			;;
		hash)
			sed 's/^/# /; s/[[:space:]]*$//' "$BANNER_FILE"
			printf -- '#\n# %s\n' "$DISCORD_URL"
			;;
		markdown)
			# A four-backtick fence: the art has runs of two backticks, never four.
			printf -- '````\n'
			cat "$BANNER_FILE"
			printf -- '````\n\n[Discord](%s)\n' "$DISCORD_URL"
			;;
		*)
			return 1
			;;
	esac
}

# How many lines at the top of the file the banner must sit *below*: shebangs, Luau mode
# directives and Markdown front matter all have to stay on line 1.
preamble_lines() {
	local path="$1" style="$2" n=0 line

	if [ ! -s "$path" ]; then
		echo 0
		return
	fi

	case "$style" in
		lua)
			# `--!strict` and friends are hot comments: only honoured before the first token.
			while IFS= read -r line; do
				case "$line" in
					'--!'*) n=$((n + 1)) ;;
					*) break ;;
				esac
			done < "$path"
			;;
		hash | cblock)
			IFS= read -r line < "$path" || true
			case "$line" in
				'#!'*) n=1 ;;
			esac
			;;
		markdown)
			IFS= read -r line < "$path" || true
			if [ "$line" = "---" ]; then
				# YAML front matter: keep the whole block on top.
				n=$(awk 'NR==1{next} /^---[[:space:]]*$/{print NR; exit}' "$path")
				[ -n "$n" ] || n=0
			fi
			;;
	esac

	echo "$n"
}

# --------------------------------------------------------------------------------------
# The stamp itself
# --------------------------------------------------------------------------------------

# stamp <path> -> 0 when the file was changed, 1 when it was left alone.
stamp() {
	local path="$1" style preamble tmp next

	[ -f "$path" ] || return 1
	is_skipped "$path" && return 1

	style="$(style_for "$path")"
	[ -n "$style" ] || return 1

	if grep -qF "$MARKER" "$path" 2> /dev/null; then
		return 1
	fi

	preamble="$(preamble_lines "$path" "$style")"
	tmp="$(mktemp)"

	if [ "$preamble" -gt 0 ]; then
		head -n "$preamble" "$path" > "$tmp"
	fi

	render_banner "$style" >> "$tmp"

	# One blank line between the banner and the code, unless the code already starts blank.
	next="$(tail -n +"$((preamble + 1))" "$path" | head -n 1 || true)"
	if [ -s "$path" ] && [ -n "$next" ]; then
		printf '\n' >> "$tmp"
	fi

	tail -n +"$((preamble + 1))" "$path" >> "$tmp"

	cat "$tmp" > "$path"
	rm -f "$tmp"
	return 0
}

# --------------------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------------------

mode="stamp"
files=()

case "${1:-}" in
	--all)
		mode="stamp"
		while IFS= read -r f; do files+=("$f"); done < <(git ls-files)
		;;
	--check)
		mode="check"
		shift
		files=("$@")
		;;
	-h | --help | "")
		sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		files=("$@")
		;;
esac

changed=0
missing=0

for f in "${files[@]}"; do
	[ -n "$f" ] || continue
	if [ "$mode" = "check" ]; then
		if [ -f "$f" ] && ! is_skipped "$f" && [ -n "$(style_for "$f")" ] \
			&& ! grep -qF "$MARKER" "$f" 2> /dev/null; then
			echo "apply-banner: missing banner: $f" >&2
			missing=$((missing + 1))
		fi
	else
		if stamp "$f"; then
			echo "banner: stamped $f"
			changed=$((changed + 1))
		fi
	fi
done

if [ "$mode" = "check" ]; then
	[ "$missing" -eq 0 ] || exit 1
	exit 0
fi

echo "banner: ${changed} file(s) stamped"
