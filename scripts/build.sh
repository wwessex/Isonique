#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Keep SwiftPM on the selected Apple compiler rather than a user-installed toolchain.
export SWIFT_EXEC="$(xcrun --find swiftc)"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build --disable-sandbox --build-system native --configuration release --arch arm64 --scratch-path .build
binpath=$(swift build --disable-sandbox --build-system native --configuration release --arch arm64 --scratch-path .build --show-bin-path)
# Sign outside cloud-backed Documents: Finder/File Provider may attach signing-invalid metadata.
staging=$(mktemp -d "${TMPDIR:-/private/tmp/}isonique.XXXXXX")
trap 'rm -rf "$staging"' EXIT
bundle="$staging/Isonique.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$PWD/build"
cp -X "$binpath/Isonique" "$bundle/Contents/MacOS/Isonique"
cp -X Info.plist "$bundle/Contents/Info.plist"
cp -X LICENSE "$bundle/Contents/Resources/LICENSE"
ditto --norsrc Resources/en-GB.lproj "$bundle/Contents/Resources/en-GB.lproj"
/bin/sh scripts/build-icon.sh Resources/IsoniqueIcon.svg "$bundle/Contents/Resources/Isonique.icns"
xattr -cr "$bundle"
# ImageCaptureCore requires Hardened Runtime and the Photos Library entitlement on macOS.
codesign --force --sign - --options runtime --entitlements Resources/Isonique.entitlements "$bundle"
codesign --verify --deep --strict --verbose=2 "$bundle"
# The archive keeps a clean signed deliverable even on a cloud-backed workspace.
ditto -c -k --norsrc --keepParent "$bundle" "$PWD/build/Isonique.zip"
ditto --norsrc "$bundle" "$PWD/build/Isonique.app"
xattr -cr "$PWD/build/Isonique.app"
echo "Built arm64 app and verified signed archive in $PWD/build"
