> Follow-up: compact scrolling has since measured 5.56% faster against the same baseline code. [Compact-scroll correction and bar chart](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/compact-scroll-fix-20261001.md). The original measurements below are preserved.

# Five reported performance paths — 1 October 2026

**Three measured paths have supported speedups. Find and whole compact scrolling remain unconfirmed. The zero-slowdown requirement is not complete.**

Only the five requested paths were changed, in four production files. All 343 controlled native visual comparisons matched. No design values or animation durations were changed. Every executable check was offscreen, with window ordering and activation blocked.

[Static bar charts (PDF)](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-five-paths-20261001/brook-benchmarks.pdf) · [All raw samples](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/five-path-regression-fixes-20261001.json) · [Reproduction archive](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/five-path-regression-evidence-20261001.tar.gz)

## Whole requested workloads

| Workload | Before (ms) | After (ms) | Observed change | Paired 95% interval | Verdict |
|---|---:|---:|---:|---:|---|
| Top-bar progress · 1,000 calls | 0.003675 | 0.002907 | -20.91% | -18.41% to -13.85% | PROVEN |
| Sidebar progress · 1,000 calls | 0.003517 | 0.002747 | -21.89% | -20.28% to -18.13% | PROVEN |
| Command bar · hidden preparation | 3.243 | 1.062 | -67.26% | -62.70% to -56.45% | PROVEN |
| Find bar · open + close | 3.818 | 3.763 | -1.46% | -4.54% to +2.67% | INCONCLUSIVE |
| Compact · scroll tabs | 1.830 | 1.900 | +3.86% | -1.84% to +3.82% | INCONCLUSIVE |


![Five reported paths](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-five-paths-20261001/five-paths.png)

These compare the working tree immediately before this request against the final candidate. Earlier optimization patches over commit `550abacceb5f87026838b09b57a7b05a0610980f` are present in both. They do not compare directly against the historical numbers in the user's message. No old baseline or fastest pilot is substituted into this table.

Four fresh processes each collected 100 before/after pairs after 10 warmup pairs, alternating AB/BA within the same process, window, and synthetic 200-tab state. Every measured sample is retained. Progress samples execute 1,000,000 calls and divide by 1,000 to report milliseconds per 1,000 calls. This batching avoids trying to infer a large percentage from a single few-microsecond sample.

The observed change compares pooled medians. The interval is a separate, exploratory paired estimate: the median log ratio in each process, with all 256 cluster resamples of the four processes. It describes uncertainty in the paired effect, not a bound on all future runs. High raw wall-clock variability prevents using a simple pooled-median threshold alone. The command and progress changes improved all four process medians, with paired intervals wholly below zero; their pilots and component measurements support the same direction. This is the basis for their scoped `PROVEN` labels.

Find improved by 1.46% in pooled medians, but its paired interval crosses zero. Compact scrolling has a **3.86% higher pooled median**; its median adjacent-pair effect is -0.50%, and its interval also crosses zero. Neither proves a speedup, equivalence, or a code-caused slowdown. They remain unresolved whole-action results.

## What changed

- [SidebarView.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/SidebarView.mm:646) and [TopBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/TopBar.mm:1527): pure progress notifications return before the expensive method body. The private direct helper preserves the original strong-reference lifetime and mixed-flag handling. Release assembly reduces the pure-progress path from 10 instructions to 3; the original source and renamed baseline have identical original fast-path assembly.
- [CommandBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/CommandBar.mm:299): reuse the existing editor and unchanged text, while still clearing marked input when required. Avoid resetting an identical panel frame. Text selection, composition handling, attached-to-floating transitions, and resizing checks pass. This benchmark measures hidden preparation, not visible opening animation.
- [ContentAreaView.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/ContentAreaView.mm:227): remove a redundant selection call after native focus, which already selects the text. Repeated focus, partial prior selection, empty and populated fields, search results, closing focus, and DOM selection clearing pass.
- [TopBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/TopBar.mm:834): reuse immutable edge-gradient colors; update geometry and gradient locations only when bounds change; reattach the mask only when needed. Width, fade state, appearance and scroll-position checks pass.

No rendering-mode experiments remain: the trial document redraw policy, clipping change, and Find layer changes were removed. The final Find close method retains its pre-request order. Existing unrelated working-tree changes were preserved. No new production comments, dependencies, or configuration settings were added.

## Find and scroll component measurements

A separate fixed 60-pair run, after 10 warmup pairs, measured the changed components. Find focus averaged 100 real focus calls per sample. The edge-fade test prepared a real start-to-middle transition outside the timer and called the production update method inside it.

| Workload | Before (ms) | After (ms) | Observed change |
|---|---:|---:|---:|
| Find focus, empty field | 0.173 | 0.168 | -2.89% |
| Find focus, populated field | 0.291 | 0.275 | -5.33% |
| Compact edge-fade update | 0.001500 | 0.000333 | -77.78% |


![Changed components](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-five-paths-20261001/changed-components.png)

These narrower results show less work in the modified methods. They are not replacements for the unresolved whole-action measurements above. In this same component run, the full Find action measured 12.51% higher and the full scroll action 0.39% lower. Those readings are preserved in the JSON.

## Identical-code control and machine load

A separate 100-pair control uses the exact same current method implementations under both labels, with the same AB/BA protocol and 10 warmups.

| Workload | Before (ms) | After (ms) | Observed change |
|---|---:|---:|---:|
| Top-bar progress · 1,000 calls | 0.003746 | 0.003924 | +4.77% |
| Sidebar progress · 1,000 calls | 0.003543 | 0.003792 | +7.03% |
| Command bar · hidden preparation | 2.678 | 2.842 | +6.11% |
| Find bar · open + close | 6.582 | 6.720 | +2.10% |
| Compact · scroll tabs | 3.387 | 3.281 | -3.12% |


![Identical-code control](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-five-paths-20261001/identical-code-control.png)

The control produced higher medians without a source change, including +7.03% for sidebar progress. A read-only load snapshot found an unrelated runtime, the macOS malware scanner, Spotlight, and WindowServer using substantial CPU. No other applications were stopped or changed. No thermal or performance warning was reported. These observations establish measurement noise; they do not establish that every code change is harmless.

## Correctness and build checks

- Six before/after correctness suites passed. Native RGBA equality: **248/248 existing UI captures plus 95/95 expanded targeted captures**.
- Expanded fixtures covered 500/900/1280-point windows, light/dark/high-contrast appearances, empty/short/200-character Find text, resized command panels, and start/middle/end scroll positions.
- The first expanded full-content attempt had 12 differences in the asynchronously rendered WebKit background and search highlighting. The original comparisons and captures are retained. The authoritative native comparison places the same solid AppKit backdrop behind the controls; WebKit search and selection behavior is tested separately. This is not a claim that every attempted screenshot matched.
- Existing mixed tab-change flags, selected URLs, reuse, weak lifetimes, hover/tracking, accessibility, and simulated animation checks passed.
- Release build and Debug build plus static analysis passed. Static analysis emitted 40 existing diagnostics, with no new normalized diagnostic signature. Existing compiler warnings remain; this is not a warning-free claim.
- Release code signing (`--deep --strict`), Info.plist syntax, Python syntax, and `git diff --check` passed.
- All 75 production source hashes match the frozen final candidate. Exactly four production files differ from the pre-request snapshot.

The checks do not prove live frame pacing or WindowServer presentation: no visible animation stress tests were run. Cold-start costs, first-ever control creation, unrelated browser actions, and every possible machine state are outside these measurements.

## Reproduction

The archive contains frozen source snapshots, before/final patches, final harness, baseline object files, final paired objects, three final runners, exact compile flags, raw timing/visual results, assembly, profiler exports, logs, and checksums. The clone classes use frozen original production source; the harness verifies instance sizes, ivar offsets, and method ABI encodings before swapping only the changed production methods. Both versions therefore execute against the same object graph. See `confirmation.py` for the preset four-process run.

For a single paired process after extracting the archive, run from its root, choosing a new destination:

```sh
BROOK_CHECK_FIVE_PATHS_ONLY=1 BROOK_CHECK_PAIRED_METHODS=1 \
BROOK_CHECK_RUNS=100 BROOK_CHECK_WARMUPS=10 \
./final2-paired-runner/check-ui /private/tmp/brook-five-recheck --browser --offscreen
```

Add `BROOK_CHECK_PAIRED_CONTROL=1` for the identical-implementation control. Add `BROOK_CHECK_FIVE_COMPONENTS=1` for the component suite. Use `final2-before-runner` and `final2-after-runner` with `BROOK_CHECK_FIVE_VISUALS=1`, one measured iteration, and one warmup for expanded correctness captures. The regular runner without `--browser` performs the broader existing native UI checks. Outputs are synthetic and isolated; never pass a real browser profile as the destination.

Build checks used:

```sh
xcodebuild -project Brook.xcodeproj -scheme Brook -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- build
xcodebuild -project Brook.xcodeproj -scheme Brook -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- build analyze
codesign --verify --deep --strict --verbose=2 build/Build/Products/Release/Brook.app
plutil -lint build/Build/Products/Release/Brook.app/Contents/Info.plist
git diff --check
```

Temporary benchmark directories and duplicate binaries are removed after the evidence archive is verified. The reusable check harness and reports remain. Nothing was committed or pushed.
