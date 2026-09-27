#!/bin/bash
# Builds Resources/blocklist-*.json: AdGuard's filter lists converted to WebKit content-blocker
# JSON by AdGuard's SafariConverterLib (the converter AdGuard for Safari and wBlock use).
# The converter is only a build tool; it isn't linked into or shipped with Brook.
# One JSON per list: WebKit caps a rule list at 150k rules, and a list's exceptions
# (ignore-previous-rules) only cover its own rules, as in Safari content blockers.
set -euo pipefail
cd "$(dirname "$0")/.."

CONVERTER_TAG=v4.3.0
WORK=build/blocklist
TOOL="$WORK/scl/.build/release/ConverterTool"
mkdir -p "$WORK"

if [ ! -x "$TOOL" ]; then
    rm -rf "$WORK/scl"
    git clone -q --depth 1 --branch "$CONVERTER_TAG" https://github.com/AdguardTeam/SafariConverterLib "$WORK/scl"
    swift build -c release --product ConverterTool --package-path "$WORK/scl"
fi

convert() {   # name, AdGuard filter id
    curl -fsSL "https://filters.adtidy.org/extension/safari/filters/$2_optimized.txt" -o "$WORK/$1.txt"
    "$TOOL" convert --input-path "$WORK/$1.txt" --safari-rules-json-path "Resources/blocklist-$1.json" \
        --advanced-blocking-rules-path "$WORK/$1-advanced.txt" > "$WORK/$1.log"
    ls -l "Resources/blocklist-$1.json"
}
convert ads 2        # AdGuard Base filter (EasyList + AdGuard English)
convert trackers 3   # AdGuard Tracking Protection filter (EasyPrivacy + AdGuard)
