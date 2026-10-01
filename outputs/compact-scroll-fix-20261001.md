# Compact-scroll regression correction — 1 October 2026

**PROVEN for this offscreen workload: compact scrolling now has a 5.56% lower median than the baseline code behind the earlier +3.9% comparison.** The new fix alone lowered the median by 6.77% in 400 paired samples. All four paired confirmation processes improved. All 359 native visual comparisons matched.

[Static chart (PDF)](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-compact-scroll-20261001/compact-scroll.pdf) · [Raw measurements](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/compact-scroll-fix-20261001.json) · [Reproduction archive](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/compact-scroll-evidence-20261001.tar.gz)

![Compact scrolling](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-compact-scroll-20261001/compact-scroll.png)

## Change

Only [TopBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/TopBar.mm:203) changed in production:

```objc
_label.clipsToBounds = YES;
```

The native title field already uses `NSLineBreakByClipping`. Explicitly bounding its drawing reduces scroll work in AppKit's backing layers. The profiler attributed 175 of 264 sampled milliseconds inside the measured actions to Core Animation commits, including 150 milliseconds under layer display; direct layout and display calls were small. The retained change targets that work. Fonts, colors, dimensions, fade masks, input handling, accessibility, and animation parameters were not edited.

Earlier experiments that flattened label subviews, with and without an explicit redraw policy, measured slower and were removed. Their source snapshots and results remain in the evidence. There are no new dependencies or production comments. Other existing working-tree changes were preserved.

## Results

| Comparison | Before median (ms) | After median (ms) | Change | Before p95 (ms) | After p95 (ms) |
|---|---:|---:|---:|---:|---:|
| Same baseline code as the +3.9% comparison | 0.500813 | 0.472979 | -5.56% | 0.615875 | 0.559167 |
| This one-line fix, paired in the same process | 0.548667 | 0.511500 | -6.77% | 0.636833 | 0.589833 |
| identical-control | 0.503354 | 0.498187 | -1.03% | 0.587417 | 0.563708 |
| top-scroll | 0.580188 | 0.521062 | -10.19% | 0.653417 | 0.606708 |


The first row reuses the **exact archived baseline object files from the earlier +3.9% comparison**, verified against their archive checksums. Four alternating AB/BA process pairs collected 40 measured samples per process after five warmups: 160 samples per version. The test uses a compact-only fixture so other benchmark actions do not precede the scroll. Both versions execute the same workload: 200 total synthetic tabs, 100 in the current space, scroll from x=0 to x=300, then layout, display, and Core Animation flush. This changes the session setup from the earlier five-path run; absolute milliseconds must not be spliced into that old run or compared across sessions.

The four fresh-process median changes were **-8.49%, -11.68%, -10.36%, and +1.87%**. The higher fourth pair is retained. The pooled median and p95 both improve; the exploratory process-pair 95% interval is **-11.02% to -1.34%**.

The second row isolates the new fix using the same production instances in each process. The harness alternates the real native label property between its verified old value (`NO`) and new value (`YES`), outside timing, then settles the browser. Four fresh processes each collected 100 adjacent before/after pairs after 10 warmup pairs. Their median changes were **-8.86%, -6.15%, -6.69%, and -5.94%**. The exploratory cluster interval over paired log ratios is **-7.25% to -5.47%**. This matched design and the independent executable comparison support the speedup; a simple pooled coefficient-of-variation threshold alone would not.

The identical-code control used 100 pairs with clipping enabled under both labels and measured -1.03%. The shared top-bar path used 100 pairs and measured -10.19%. Its result is supporting evidence for the shared code path; the requested correction remains compact scrolling. Every sample, per-process statistic, p95, range, and coefficient of variation is preserved in the JSON. Runs were preset; no samples were discarded or selected to make the chart lower.

## Correctness

- **359/359 RGBA comparisons matched:** 248 existing native UI captures and 111 compact-scroll captures.
- Expanded label checks include 500/900/1280-point windows, 11/13/17-point text, light/dark/high-contrast appearances, short and long titles, accented text, Japanese, Arabic, emoji, hover, and start/middle/end scroll positions.
- Existing checks also cover normal and compact top bars, selection, title replacement, address editing, reuse, accessibility, weak lifetimes, tracking, and simulated motion.
- Release build, Debug build plus static analysis, code-sign verification, plist validation, Python syntax, and `git diff --check` passed. No new normalized source-warning signature was introduced; existing warnings remain.
- All 75 production source hashes match the frozen candidate. Only one production line differs from the snapshot at the start of this request.

All executable checks blocked window ordering and activation. No live windows or flashing animation tests were shown. These results cover offscreen main-thread scroll work, not visible presentation/frame pacing or every machine load. They do not guarantee that every individual timing sample is faster. Find and other earlier unresolved paths were outside this request and were not changed.

## Reproduction

The archive contains source snapshots, the one-line patch, the final harness, baseline object files, before/after executables, the earlier comparison baseline executable, profiler exports, raw samples, PNG captures, logs, and a SHA-256 manifest. Temporary working directories are removed after archive verification. Nothing was committed or pushed.

After extracting it, use a new output directory for each invocation. To reproduce the same-instance comparison:

```sh
BROOK_CHECK_COMPACT_ONLY=1 BROOK_CHECK_SCROLL_PAIRED=1 \
BROOK_CHECK_RUNS=100 BROOK_CHECK_WARMUPS=10 \
./final-after-runner/check-ui /private/tmp/brook-compact-recheck --browser --offscreen
```

Add `BROOK_CHECK_PAIRED_CONTROL=1` to use the current configuration for both labels, or `BROOK_CHECK_SCROLL_LAYOUT=top` to check the shared top-bar path. For independent executable comparisons, omit `BROOK_CHECK_SCROLL_PAIRED` and compare `reported-baseline-runner/check-ui` with `final-after-runner/check-ui`, alternating their process order. `confirm.py`, `reported-confirmation.py`, `controls.py`, and `correctness.py` record the fixed run protocols; choose fresh destination names before rerunning them.

Set `BROOK_CHECK_SCROLL_VISUALS=1`, one warmup, and one measured run with `final-before-runner` and `final-after-runner` for expanded label captures. The normal runner without `--browser` executes the existing native UI checks. Never use a real browser profile as an output directory.
