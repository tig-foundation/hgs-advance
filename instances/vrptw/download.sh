#!/bin/bash
# Downloads classical VRPTW benchmark instances in the original text format
# into this folder, from CVRPLIB (PUC-Rio).
#
# Usage:
#   ./download.sh                  # 56 Solomon instances (100 customers)
#   ./download.sh 200              # 60 Gehring & Homberger instances with 200 customers
#   ./download.sh 400 600          # any combination of 200, 400, 600, 800, 1000
#   ./download.sh all              # Solomon + all Gehring & Homberger sizes
#
# The sources are 7-Zip archives, so a 7z-capable extractor is required:
# `7z`/`7za`/`7zr` (p7zip) or `bsdtar` (libarchive-tools; the default `tar`
# on macOS already is bsdtar). The best-known `.sol` files bundled in the
# archives are ignored; only the `.txt` instance files are extracted.
set -e
cd "$(dirname "$0")"

# CVRPLIB instance-set download endpoints (each serves a .7z archive).
SOLOMON_URL="https://galgos.inf.puc-rio.br/cvrplib/en/download/instance-set/22"    # Solomon/    (100 customers)
HOMBERGER_URL="https://galgos.inf.puc-rio.br/cvrplib/en/download/instance-set/23"  # Holmberger/ (200-1000 customers)

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# Extract a .7z archive into a destination directory, using whichever 7z-capable
# tool is available.
extract_7z() {
    local archive="$1" dest="$2"
    if command -v 7z >/dev/null 2>&1; then
        7z x -y -o"$dest" "$archive" >/dev/null
    elif command -v 7za >/dev/null 2>&1; then
        7za x -y -o"$dest" "$archive" >/dev/null
    elif command -v 7zr >/dev/null 2>&1; then
        7zr x -y -o"$dest" "$archive" >/dev/null
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$archive" -C "$dest"
    elif tar --version 2>/dev/null | grep -qi 'bsdtar\|libarchive'; then
        tar -xf "$archive" -C "$dest"
    else
        echo "Error: no 7z-capable extractor found." >&2
        echo "Install one of: p7zip (7z/7za) or libarchive-tools (bsdtar)." >&2
        exit 1
    fi
}

download_solomon() {
    local dir="$TMP_ROOT/solomon"
    mkdir -p "$dir"
    echo "Downloading Solomon 100-customer instances..."
    curl -fsSL "$SOLOMON_URL" -o "$dir/solomon.7z"
    extract_7z "$dir/solomon.7z" "$dir"

    local count=0
    for f in "$dir"/Solomon/*.txt; do
        [ -e "$f" ] || continue
        cp "$f" "./$(basename "$f")"
        count=$((count + 1))
    done
    echo "Done: $count Solomon instances."
}

# The Homberger archive holds every size (200-1000) in one folder; download it
# once and reuse across multiple size requests in a single invocation.
HOMBERGER_DIR=""
ensure_homberger() {
    [ -n "$HOMBERGER_DIR" ] && return 0
    HOMBERGER_DIR="$TMP_ROOT/homberger"
    mkdir -p "$HOMBERGER_DIR"
    echo "Downloading Gehring & Homberger instances (all sizes)..."
    curl -fsSL "$HOMBERGER_URL" -o "$HOMBERGER_DIR/homberger.7z"
    extract_7z "$HOMBERGER_DIR/homberger.7z" "$HOMBERGER_DIR"
}

download_homberger() {
    local size=$1
    ensure_homberger
    # Instance names encode size as C1_<size/100>_<k>, e.g. 1000 -> C1_10_1.
    local token=$((size / 100))
    local count=0
    for f in "$HOMBERGER_DIR"/*/*_${token}_*.txt; do
        [ -e "$f" ] || continue
        cp "$f" "./$(basename "$f")"
        count=$((count + 1))
    done
    echo "Done: $count Gehring & Homberger $size-customer instances."
}

if [ $# -eq 0 ]; then
    download_solomon
    exit 0
fi

for arg in "$@"; do
    case "$arg" in
        solomon) download_solomon ;;
        all)
            download_solomon
            for size in 200 400 600 800 1000; do download_homberger $size; done
            ;;
        200|400|600|800|1000) download_homberger "$arg" ;;
        *)
            echo "Unknown argument: '$arg' (expected: solomon, 200, 400, 600, 800, 1000, or all)" >&2
            exit 1
            ;;
    esac
done
