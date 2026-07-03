#!/bin/bash
# Downloads the 100 CVRPLIB "X" benchmark instances of Uchoa et al. (2013)
# from CVRPLIB (https://galgos.inf.puc-rio.br/cvrplib) into this folder.
set -e
cd "$(dirname "$0")"

BASE_URL="https://galgos.inf.puc-rio.br"
SET_URL="$BASE_URL/cvrplib/en/instances/1"

echo "Fetching instance list from $SET_URL..."
mapping=$(curl -fsSL "$SET_URL" | tr -d '\n' \
    | grep -oE 'href="/cvrplib/en/download/instance/[0-9]+"[^>]*>[[:space:]]*X-n[0-9]+-k[0-9]+' \
    | sed -E 's|href="([^"]+)"[^>]*>[[:space:]]*(X-n[0-9]+-k[0-9]+)|\1 \2|')

if [ -z "$mapping" ]; then
    echo "Could not find any X instances at $SET_URL (page layout may have changed)" >&2
    exit 1
fi

count=0
while read -r path name; do
    curl -fsSL "$BASE_URL$path" -o "$name.vrp"
    echo "Downloaded $name.vrp"
    count=$((count + 1))
done <<< "$mapping"

echo "Done: $count X instances."
