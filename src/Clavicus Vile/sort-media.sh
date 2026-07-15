#!/usr/bin/env bash
#
# sort-media.sh
#
# Move finished torrent downloads into Sanguine's Jellyfin library:
#   audio  → src/Sanguine/media/music
#   video  → src/Sanguine/media/videos
# Non-media files are flagged and deleted.
#
# Usage:
#   ./sort-media.sh           # move/delete for real
#   ./sort-media.sh --dry-run # report only; do not move or delete
#
# Env (optional overrides):
#   TORRENTS_DIR  — source (default: <script>/data/torrents)
#   MUSIC_DIR     — audio destination
#   VIDEOS_DIR    — video destination
#
# Skips the incomplete/ subdirectory so in-progress downloads are left alone.
# Exit code: 0 on success, 1 if any move/delete failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TORRENTS_DIR="${TORRENTS_DIR:-$SCRIPT_DIR/data/torrents}"
MUSIC_DIR="${MUSIC_DIR:-$REPO_ROOT/src/Sanguine/media/music}"
VIDEOS_DIR="${VIDEOS_DIR:-$REPO_ROOT/src/Sanguine/media/videos}"

DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        -h|--help)
            sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# Lowercase extension match (bash ${var,,} needs bash 4+; macOS ships bash 3.2 —
# use tr so this also works under /bin/bash on macOS if invoked that way).
ext_lower() {
    printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]'
}

is_audio() {
    case "$(ext_lower "$1")" in
        mp3|flac|m4a|aac|ogg|opus|wav|wma|aiff|aif|alac|ape|wv|mpc) return 0 ;;
        *) return 1 ;;
    esac
}

is_video() {
    case "$(ext_lower "$1")" in
        mp4|mkv|avi|mov|wmv|webm|m4v|mpeg|mpg|flv|ts|m2ts|vob) return 0 ;;
        *) return 1 ;;
    esac
}

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

MOVED_AUDIO=0
MOVED_VIDEO=0
DELETED=0
ERRORS=0

if [[ ! -d "$TORRENTS_DIR" ]]; then
    echo "Torrents directory not found: $TORRENTS_DIR" >&2
    exit 1
fi

mkdir -p "$MUSIC_DIR" "$VIDEOS_DIR"

echo "== Sort media =="
echo "Source : $TORRENTS_DIR"
echo "Music  : $MUSIC_DIR"
echo "Videos : $VIDEOS_DIR"
if $DRY_RUN; then
    echo "Mode   : dry-run (no changes)"
fi
echo

# Collect files under torrents, skipping incomplete/
# Use find -print0 for spaces/newlines in names.
while IFS= read -r -d '' file; do
    # Skip empty (should not happen with -print0)
    [[ -n "$file" ]] || continue

    rel="${file#"$TORRENTS_DIR"/}"
    base="$(basename "$file")"

    # No extension (or hidden dotfiles with no meaningful type) → flag & delete
    if [[ "$base" == .* ]] || [[ "$base" != *.* ]]; then
        echo -e "${YELLOW}FLAG${RESET} non-media (no usable extension): $rel"
        if ! $DRY_RUN; then
            if rm -f -- "$file"; then
                DELETED=$((DELETED + 1))
            else
                echo -e "${RED}ERROR${RESET} failed to delete: $rel" >&2
                ERRORS=$((ERRORS + 1))
            fi
        else
            DELETED=$((DELETED + 1))
        fi
        continue
    fi

    if is_audio "$file"; then
        dest_dir="$MUSIC_DIR"
        kind="audio"
    elif is_video "$file"; then
        dest_dir="$VIDEOS_DIR"
        kind="video"
    else
        echo -e "${YELLOW}FLAG${RESET} non-media (.$(ext_lower "$file")): $rel"
        if ! $DRY_RUN; then
            if rm -f -- "$file"; then
                DELETED=$((DELETED + 1))
            else
                echo -e "${RED}ERROR${RESET} failed to delete: $rel" >&2
                ERRORS=$((ERRORS + 1))
            fi
        else
            DELETED=$((DELETED + 1))
        fi
        continue
    fi

    # Preserve relative path under music/ or videos/ (album / release folders)
    parent_rel="$(dirname "$rel")"
    if [[ "$parent_rel" == "." ]]; then
        dest="$dest_dir/$base"
    else
        dest="$dest_dir/$parent_rel/$base"
    fi

    if [[ -e "$dest" ]]; then
        echo -e "${RED}SKIP${RESET} destination exists: $dest" >&2
        ERRORS=$((ERRORS + 1))
        continue
    fi

    if [[ "$kind" == "audio" ]]; then
        label="music"
    else
        label="videos"
    fi
    echo -e "${GREEN}MOVE${RESET} [$kind] $rel → $label/${dest#"$dest_dir"/}"
    if ! $DRY_RUN; then
        mkdir -p "$(dirname "$dest")"
        if mv -- "$file" "$dest"; then
            if [[ "$kind" == "audio" ]]; then
                MOVED_AUDIO=$((MOVED_AUDIO + 1))
            else
                MOVED_VIDEO=$((MOVED_VIDEO + 1))
            fi
        else
            echo -e "${RED}ERROR${RESET} failed to move: $rel" >&2
            ERRORS=$((ERRORS + 1))
        fi
    else
        if [[ "$kind" == "audio" ]]; then
            MOVED_AUDIO=$((MOVED_AUDIO + 1))
        else
            MOVED_VIDEO=$((MOVED_VIDEO + 1))
        fi
    fi
done < <(find "$TORRENTS_DIR" \
    \( -path "$TORRENTS_DIR/incomplete" -o -path "$TORRENTS_DIR/incomplete/*" \) -prune \
    -o -type f -print0)

# Remove empty directories left behind under torrents (not incomplete/)
if ! $DRY_RUN; then
    find "$TORRENTS_DIR" \
        \( -path "$TORRENTS_DIR/incomplete" -o -path "$TORRENTS_DIR/incomplete/*" \) -prune \
        -o -type d -empty -delete 2>/dev/null || true
fi

echo
echo "Done."
echo "  Audio moved : $MOVED_AUDIO"
echo "  Video moved : $MOVED_VIDEO"
echo "  Deleted     : $DELETED"
echo "  Errors      : $ERRORS"

if (( ERRORS > 0 )); then
    exit 1
fi
exit 0
