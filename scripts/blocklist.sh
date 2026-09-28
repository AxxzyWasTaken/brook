#!/bin/bash
# Builds Resources/blocklist.lzfse: AdGuard's filter lists converted to WebKit content-blocker
# JSON by AdGuard's SafariConverterLib (the converter AdGuard for Safari and wBlock use), then
# LZFSE-compressed (17 MB -> 1.7 MB; Foundation decompresses it in ~10 ms).
# The converter is only a build tool; it isn't linked into or shipped with Brook.
# Both lists are converted together into one rule list: a list's exceptions (ignore-previous-rules)
# only override its own earlier rules, so with a list each, one could block what the other allows.
# One list of ~137k rules compiles as fast as two; WebKit's cap is 150k, checked below.
set -euo pipefail
cd "$(dirname "$0")/.."

CONVERTER_TAG=v4.3.0
WORK=build/blocklist
TOOL="$WORK/scl/.build/release/ConverterTool"
OUT=Resources/blocklist.lzfse
mkdir -p "$WORK"

if [ ! -x "$TOOL" ]; then
    rm -rf "$WORK/scl"
    git clone -q --depth 1 --branch "$CONVERTER_TAG" https://github.com/AdguardTeam/SafariConverterLib "$WORK/scl"
    swift build -c release --product ConverterTool --package-path "$WORK/scl"
fi

# 2 = AdGuard Base (EasyList + AdGuard English), 3 = Tracking Protection (EasyPrivacy + AdGuard).
: > "$WORK/rules.txt"
for id in 2 3; do
    curl -fsSL "https://filters.adtidy.org/extension/safari/filters/${id}_optimized.txt" >> "$WORK/rules.txt"
    echo >> "$WORK/rules.txt"
done

# Without output paths the tool prints a JSON summary with the rules inside it.
"$TOOL" convert --input-path "$WORK/rules.txt" > "$WORK/result.json"
read -r rules discarded < <(jq -r '"\(.safariRulesCount) \(.discardedSafariRules)"' "$WORK/result.json")
if [ "$discarded" != 0 ]; then
    echo "error: $discarded rules over WebKit's 150,000-rule cap were dropped" >&2
    exit 1
fi
jq -r .safariRulesJSON "$WORK/result.json" > "$WORK/blocklist.json"
rm -f "$OUT"
compression_tool -encode -a lzfse -i "$WORK/blocklist.json" -o "$OUT"
echo "$rules rules, $(wc -c < "$OUT" | tr -d ' ') bytes -> $OUT"
