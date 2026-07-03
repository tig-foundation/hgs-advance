#!/bin/bash
# Downloads classical VRPTW benchmark instances in the original text format
# into this folder.
#
# Usage:
#   ./download.sh                  # 56 Solomon instances (100 customers)
#   ./download.sh 200              # 60 Gehring & Homberger instances with 200 customers
#   ./download.sh 400 600          # any combination of 200, 400, 600, 800, 1000
#   ./download.sh all              # Solomon + all Gehring & Homberger sizes
set -e
cd "$(dirname "$0")"

SOLOMON_BASE_URL="https://raw.githubusercontent.com/GBarbo/GA-VRPTW/ba4db6e16eefb3b6d8ae1a261eb48ad4364f3ba2/data"
HOMBERGER_BASE_URL="https://www.sintef.no/globalassets/project/top/vrptw/homberger"

download_solomon() {
    local instances=""
    for i in $(seq 101 109); do instances="$instances C$i"; done
    for i in $(seq 201 208); do instances="$instances C$i"; done
    for i in $(seq 101 112); do instances="$instances R$i"; done
    for i in $(seq 201 211); do instances="$instances R$i"; done
    for i in $(seq 101 108); do instances="$instances RC$i"; done
    for i in $(seq 201 208); do instances="$instances RC$i"; done

    for name in $instances; do
        local lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        curl -fsSL "$SOLOMON_BASE_URL/$lower.txt" -o "$name.txt"
        echo "Downloaded $name.txt"
    done
    echo "Done: $(echo $instances | wc -w) Solomon instances."
}

download_homberger() {
    local size=$1
    local tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" RETURN

    echo "Downloading Gehring & Homberger $size-customer instances..."
    curl -fsSL "$HOMBERGER_BASE_URL/$size/homberger_${size}_customer_instances.zip" \
        -o "$tmp_dir/instances.zip"
    unzip -o -q "$tmp_dir/instances.zip" -d "$tmp_dir"

    local count=0
    for f in "$tmp_dir"/*.TXT "$tmp_dir"/*.txt; do
        [ -e "$f" ] || continue
        local name=$(basename "$f")
        name="${name%.*}.txt"
        mv "$f" "$name"
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
