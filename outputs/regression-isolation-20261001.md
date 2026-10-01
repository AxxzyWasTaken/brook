# Rendering fix and regression controls — 1 October 2026

**Shared color resolution improved by 47.3–48.6% across four appearances. The browser-wide zero-slowdown requirement is not certified.**

Eight of the 12 reported browser workloads now have lower medians against the original commit; four have higher medians. None of their paired intervals is wholly above zero. That is not proof of equivalence, and the higher readings remain in the table.

[All 60 measured workloads as bar charts](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-isolation-20261001/brook-benchmarks.pdf) · [Raw evidence](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/regression-isolation-20261001.json)

## Production change

[Utilities.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/App/Utilities.mm:389) previously resolved a color before entering the view’s appearance, discarded that result, then resolved it again. It now resolves once inside the correct appearance. The return value retains the same ownership. This is the only production file changed in this pass; earlier optimizations remain.

The focused test alternated six before/after process pairs, with four warmups and 15 measured samples per process. Each sample resolves 10,000 colors. All six paired medians improved in every appearance. Native color equality and restoration of the surrounding drawing appearance passed.

| Appearance, 10,000 resolutions | Before (ms) | Current (ms) | Change | Paired 95% interval |
|---|---:|---:|---:|---:|
| High-contrast light · 10,000 resolutions | 13.500 | 6.939 | -48.6% | -49.5% to -47.5% |
| High-contrast dark · 10,000 resolutions | 13.464 | 7.094 | -47.3% | -48.1% to -46.1% |
| Light appearance · 10,000 resolutions | 13.186 | 6.891 | -47.7% | -51.1% to -45.4% |
| Dark appearance · 10,000 resolutions | 13.456 | 6.992 | -48.0% | -48.4% to -47.2% |

![Color resolution](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-isolation-20261001/color-resolution.png)

## The 12 reported workloads

These compare original commit `550abacceb5f87026838b09b57a7b05a0610980f` with the current working tree, including the earlier optimizations. Four controlled groups used different process orders; each variant had two warmups and seven measured samples per process. The observed percentages compare pooled medians. The paired intervals separately summarize process-median log ratios. End-to-end differences cannot be attributed solely to the new color fix.

| Workload | Original (ms) | Current (ms) | Observed change | Paired interval |
|---|---:|---:|---:|---:|
| Settings · Layout request | 33.2054 | 30.9943 | -6.66% | -34.9% to -2.9% |
| Settings · Appearance request | 27.4403 | 22.3669 | -18.49% | -24.8% to +1.5% |
| Tab context menu · batched | 0.0201 | 0.0180 | -10.86% | -29.4% to +26.5% |
| Space context menu · batched | 0.006651 | 0.005650 | -15.06% | -26.6% to +1.3% |
| Spaces menu · batched | 0.0263 | 0.0253 | -3.60% | -3.1% to +1.5% |
| Command bar · hidden preparation | 1.7857 | 1.8426 | +3.19% | -32.6% to +12.7% |
| Find bar · open + close | 3.3760 | 3.5807 | +6.06% | -16.9% to +37.5% |
| Compact · scroll tabs | 0.5782 | 0.6030 | +4.29% | -41.3% to +14.3% |
| Top bar · scroll tabs | 0.7759 | 0.6647 | -14.33% | -37.0% to +32.2% |
| WebKit scroll script round trip | 1.2136 | 1.0572 | -12.89% | -32.9% to +1.1% |
| Window resizing | 4.5047 | 3.7327 | -17.14% | -40.1% to -6.5% |
| Warm session restore · 200 tabs | 0.4434 | 0.4436 | +0.04% | -4.3% to +4.5% |

![Reported workloads](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-isolation-20261001/reported-workloads.png)

## Why higher readings are not automatically code regressions

The current executable was also run under a second label. The executable paths and SHA-256 hashes are identical. Its command-bar median changed by -31.9%, find-bar median by -27.7%, and window-resize median by -13.5% between those two sets. The identical-build comparison even produced an exploratory interval above zero for one history query. These controls demonstrate that this shared-desktop protocol can flag differences without a source change. They do not prove that every code change is harmless.

![Identical-build controls](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-isolation-20261001/identical-build-control.png)

The separate longer menu/session test used four alternating groups, four warmups, 15 samples, 2,000 menu constructions and 100 restores per sample. All four current medians were below the original baseline; none established a stable speedup. Its identical-build control also changed the readings. Those batches are separate workloads and are not spliced into the browser table.

## Graphics follow-up and unresolved readings

The first full graphics run placed the color microbenchmark ahead of unrelated tests. That setup performs different amounts of warmup work in the two builds. The color benchmark is now a separate mode. All earlier measurements are retained in the evidence.

A follow-up used every permutation of before, after and an identical-after control: six groups, four warmups and 15 samples per process. The previously flagged provided-icon medians became lower: favorites -17.2% and sidebar -17.2%. This is a new diagnostic protocol, not a replacement for the earlier raw samples.

Two progress-return microbenchmarks still have higher medians against the start of this pass:

| Workload, 1,000 calls | Before (ms) | Current (ms) | Absolute increase |
|---|---:|---:|---:|
| Sidebar progress · 1,000 calls | 0.003917 | 0.013167 | 0.009250 ms |
| Top-bar progress · 1,000 calls | 0.003958 | 0.008083 | 0.004125 ms |

Their object files, fast-path instructions and instruction addresses match exactly between these two executables; the progress path returns before calling the changed helper. The cause of the timing difference remains unassigned. Neither row is presented as a zero-slowdown pass. Across the isolated graphics suite, 16 of 17 control medians also rose with identical code, although none of those control intervals was wholly above zero.

## Verification

- 68 completed offscreen suites passed their correctness assertions. One initial sandboxed WebKit attempt timed out because its subprocess could not start; it was rerun with the required execution permission, with the failure log retained.
- 1,090/1,090 RGBA comparisons matched: 992 graphics comparisons, 84 browser comparisons across the original/start/current/control variants, and 14 additional settings/font comparisons. All ten settings panes and four font choices were checked.
- Existing hover, tracking, tab reuse, focus, accessibility, icon mutation and sampled animation checks passed. No animation or layout source changed.
- Release and Debug builds passed. Static analysis completed with 40 existing analyzer diagnostics and no new warning signatures. Signing, plist and whitespace checks passed.
- Every executable blocked window presentation and activation. Browser runs also recorded zero visible windows and nominal thermal state.

The only accepted performance claim is the focused color-resolution improvement. These results do not certify a universal zero-slowdown result, live display frame pacing, external network/service performance, or visible command-bar dismissal. Intervals are exploratory, unadjusted for multiple comparisons, and use every measured sample.

## Repeat the focused checks

```sh
BROOK_CHECK_COLORS_ONLY=1 python3 scripts/check-ui.py --offscreen --runs 15 --warmups 4 --output /tmp/brook-colors
BROOK_CHECK_UI_TIMINGS_ONLY=1 python3 scripts/check-ui.py --offscreen --runs 15 --warmups 4 --output /tmp/brook-graphics
python3 scripts/check-ui.py --offscreen --browser --runs 7 --warmups 2 --output /tmp/brook-browser
```

The evidence includes the frozen harnesses, drivers, build logs, source hashes and complete patches for each baseline. Build each recorded source patch from the stated original commit. The chart baselines are labeled: browser charts use the original commit; graphics and color charts use the start of this pass. No samples were removed to improve a score.

Temporary comparison builds and test profiles from this pass were removed after preserving their evidence. The reusable offscreen test runner remains.
