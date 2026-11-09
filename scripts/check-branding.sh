#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

/usr/bin/plutil -lint Info.plist
for key in CFBundleName CFBundleDisplayName CFBundleExecutable; do
    value=$(/usr/libexec/PlistBuddy -c "Print :$key" Info.plist)
    if [ "$value" != Isonique ]; then
        printf '%s must be Isonique (found %s)\n' "$key" "$value" >&2
        exit 1
    fi
done
icon=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' Info.plist)
if [ "$icon" != Isonique.icns ] || [ ! -s Resources/IsoniqueIcon.svg ]; then
    printf 'Missing Isonique application icon source or bundle entry.\n' >&2
    exit 1
fi
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Info.plist)
if [ "$identifier" != io.github.wwessex.isonique ]; then
    printf 'Unexpected bundle identifier: %s\n' "$identifier" >&2
    exit 1
fi

# Match direct identity claims and obsolete names, leaving historical comparisons,
# photo terminology and the earlier Isonique library path available.
if git grep --untracked -IinE \
    -e 'Aperture[ _-]+Native|ApertureNative([^/[:alnum:]]|$)' \
    -e 'Isonique[[:space:]]+is[[:space:]]+(the[[:space:]]+|an?[[:space:]]+)?(official[[:space:]]+)?(Apple[- ]developed|Apple[- ]owned|Apple photo editor|(Apple.?s?[[:space:]]+)?Aperture[[:space:]]+(clone|remake|replacement|resurrection|revival|fork|successor)|official[[:space:]]+(Apple[[:space:]]+)?Aperture)' \
    -e 'Isonique[[:space:]]+(is[[:space:]]+)?(developed|owned|maintained|endorsed)[[:space:]]+by[[:space:]]+Apple([^[:alnum:]_]|$)' \
    -- . ':(exclude)scripts/check-branding.sh'; then
    printf 'Review the flagged product identity claims.\n' >&2
    exit 1
else
    status=$?
    if [ "$status" -ne 1 ]; then
        exit "$status"
    fi
fi

printf 'Isonique branding check passed.\n'
