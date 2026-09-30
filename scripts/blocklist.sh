#!/bin/bash
# Builds Resources/blocklist.lzfse: the lists uBlock Origin Lite enables by default (EasyList,
# EasyPrivacy, uBlock filters, Peter Lowe's list, uBlock badware risks) converted to WebKit
# content-blocker JSON by AdGuard's SafariConverterLib (the converter AdGuard for Safari and wBlock
# use), then LZFSE-compressed (~17 MB -> ~1.6 MB; Foundation decompresses it in ~10 ms).
# The converter is only a build tool; it isn't linked into or shipped with Brook.
# All lists are converted together into one rule list: a list's exceptions (ignore-previous-rules)
# only override its own earlier rules, so with a list each, one could block what another allows.
# One list of ~132k rules; WebKit's cap is 150k, checked below.
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

# Same coverage as uBlock Origin Lite's defaults, which scores 100/100 on adblock-tester.com.
# AdGuard's own lists were tried first: they leave out Sentry/Bugsnag and the tester's banner paths,
# score 73, and their "full" versions don't fit under the 150k cap.
: > "$WORK/rules.txt"
for url in https://easylist.to/easylist/easylist.txt \
           https://easylist.to/easylist/easyprivacy.txt \
           https://ublockorigin.github.io/uAssets/filters/filters.min.txt \
           "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext" \
           https://ublockorigin.github.io/uAssets/filters/badware.min.txt; do
    curl -fsSL "$url" >> "$WORK/rules.txt"
    echo >> "$WORK/rules.txt"
done

# Without output paths the tool prints a JSON summary with the rules inside it.
"$TOOL" convert --input-path "$WORK/rules.txt" > "$WORK/result.json"
read -r rules discarded < <(jq -r '"\(.safariRulesCount) \(.discardedSafariRules)"' "$WORK/result.json")
if [ "$discarded" != 0 ]; then
    echo "error: $discarded rules over WebKit's 150,000-rule cap were dropped" >&2
    exit 1
fi
jq -r .safariRulesJSON "$WORK/result.json" > "$WORK/converted.json"
# The lists overlap, so ~1.5k rules come out twice. Keep each rule's last copy only: an exception
# (ignore-previous-rules) between two copies cancels the first but not the second, so the last copy
# is the one that decides, and blocking is unchanged.
jq -c 'to_entries | group_by(.value | tojson) | map(max_by(.key)) | sort_by(.key) | map(.value)' \
    "$WORK/converted.json" > "$WORK/blocklist.json"
rules=$(jq length "$WORK/blocklist.json")
rm -f "$OUT"
compression_tool -encode -a lzfse -i "$WORK/blocklist.json" -o "$OUT"
echo "$rules rules, $(wc -c < "$OUT" | tr -d ' ') bytes -> $OUT"
