#!/usr/bin/env bash
#
# Link this repo's Fabro workflows into ~/.fabro/workflows/ so they resolve
# from any repository.
#
# Fabro looks for a workflow in exactly two places: the current project's
# .fabro/workflows/ directory, and the user-level ~/.fabro/workflows/
# directory. There is no configurable search path. Symlinking each workflow
# directory into the user-level location is what makes these workflows
# available everywhere without copying them into every project.
#
# Usage:
#   ./install.sh            link workflows (refuses to clobber real directories)
#   ./install.sh --force    replace existing entries, including real directories
#   ./install.sh --uninstall  remove only the symlinks that point back here

set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/workflows" && pwd)"
target_dir="${FABRO_HOME:-$HOME/.fabro}/workflows"

force=0
uninstall=0
for arg in "$@"; do
	case "$arg" in
	--force) force=1 ;;
	--uninstall) uninstall=1 ;;
	*)
		echo "unknown argument: $arg" >&2
		exit 2
		;;
	esac
done

mkdir -p "$target_dir"

linked=0
skipped=0
removed=0

for src in "$source_dir"/*/; do
	name="$(basename "$src")"
	dest="$target_dir/$name"

	if ((uninstall)); then
		# Only remove links we own, so a hand-made workflow of the same
		# name is never deleted by an uninstall.
		if [[ -L $dest && "$(readlink -f "$dest")" == "$(readlink -f "${src%/}")" ]]; then
			rm "$dest"
			removed=$((removed + 1))
		fi
		continue
	fi

	if [[ -e $dest || -L $dest ]]; then
		if [[ -L $dest && "$(readlink -f "$dest")" == "$(readlink -f "${src%/}")" ]]; then
			continue # already linked here
		fi
		if ((force)); then
			rm -rf "$dest"
		else
			echo "skip: $dest already exists (use --force to replace)" >&2
			skipped=$((skipped + 1))
			continue
		fi
	fi

	ln -s "${src%/}" "$dest"
	linked=$((linked + 1))
done

if ((uninstall)); then
	echo "removed $removed symlink(s) from $target_dir"
else
	echo "linked $linked workflow(s) into $target_dir ($skipped skipped)"
	echo "verify with: fabro validate facto-pr"
fi
