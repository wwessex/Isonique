#!/bin/sh
set -eu

source_svg=$1
destination=$2
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
iconset="$staging/Isonique.iconset"
mkdir "$iconset"
/usr/bin/sips -s format png "$source_svg" --out "$staging/source.png" >/dev/null

for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$staging/source.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    /usr/bin/sips -z "$retina" "$retina" "$staging/source.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

/usr/bin/iconutil -c icns "$iconset" -o "$destination"
