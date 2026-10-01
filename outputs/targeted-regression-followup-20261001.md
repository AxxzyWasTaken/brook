# Targeted regression follow-up — 1 October 2026

**The no-slowdown requirement remains unmet. No production optimization from this follow-up was accepted.** All trial source changes were reverted; the 75 production source files exactly match their state at the start of this follow-up. Earlier optimizations remain in place.

The 12 higher readings identified in the previous report remain unresolved. The experiments below are retained for review and are not presented as improvements in the current code.

[Raw evidence](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/targeted-regression-followup-20261001.json) · [All 56 experimental bar charts (PDF)](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-targeted-regressions-20261001/brook-benchmarks.pdf) · [Previous original-commit comparison](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/browser-regression-fixes-20261001.md)

## What was tested

- A pane-layer retention experiment was measured in two alternating before/after process pairs. It did not establish a consistent overall benefit and was reverted.
- A broader candidate removed repeated pane sizing, selection updates, menu setters, scroll-mask writes, page-layout work and session lookup allocations. Four alternating pairs covered 56 timing workloads, including all 12 reported problem rows. Six of the 12 target medians and 24 of all 56 medians were higher. That candidate was rejected.
- Longer batches then checked menus and session restore: 2,000 menu constructions or 100 restores per sample, four warmups, 15 measured samples per process, four alternating pairs. The broader candidate remained slower in those batch medians.
- A final one-line menu experiment skipped setting the native default shortcut modifier without first reading it. Its three menu medians were 0.6–1.8% lower, but two of the three paired intervals still included an increase. This did not establish the requested result, and it was also reverted.

## Checks and limits

- Release and Debug builds of the restored code passed. Static analysis completed with 40 existing diagnostics. Signing verification and whitespace checks passed.
- All 16 broad suites, two additional full-settings correctness suites, and 16 longer-batch suites passed their assertions. The broad candidate produced 1,034/1,034 matching RGBA captures, including all ten settings panes and four font choices. Those captures validate the rejected candidate; final source restoration is separately verified by hashes.
- Native shortcut defaults, empty and nonempty shortcuts, four modifier combinations and menu action invocation were checked. The longer batches recorded main-thread QoS 33 and nominal thermal state in both variants.
- Every executable blocked window ordering and application activation and checked for visible windows. No visible test was run. No design, animation or production source change from this follow-up remains.
- A shared desktop and hidden-window fixtures limit timing attribution. WebKit round trips include IPC and event-loop work. These checks do not establish live display frame pacing or visible-window activation latency.
- Observed changes below compare pooled sample medians. The intervals separately summarize paired process-median log ratios, using all 256 bootstrap resamples of four pairs. They are exploratory and unadjusted for multiple comparisons. No samples were dropped.
- This follow-up starts from the previously optimized working tree. Its timings must not be spliced with the earlier original-commit comparison. Longer batch timings are a separate workload.

## The 12 target workloads — rejected broad candidate

![Rejected candidate bar chart](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-targeted-regressions-20261001/targeted-workloads.png)

| Workload | Before (ms) | Candidate (ms) | Observed change |
|---|---:|---:|---:|
| Command bar · hidden preparation | 1.645 | 1.583 | -3.8% |
| Compact · scroll tabs | 0.733 | 0.703 | -4.1% |
| Find bar · open + close | 3.619 | 3.911 | +8.0% |
| WebKit scroll script round trip | 1.161 | 1.169 | +0.6% |
| Warm session restore · 200 tabs | 0.431 | 0.428 | -0.6% |
| Settings · Appearance request | 36.148 | 23.985 | -33.6% |
| Settings · Layout request | 36.841 | 37.480 | +1.7% |
| Space context menu · batched | 0.012 | 0.011 | -10.8% |
| Spaces menu · batched | 0.035 | 0.041 | +16.2% |
| Tab context menu · batched | 0.027 | 0.033 | +23.8% |
| Top bar · scroll tabs | 0.807 | 0.812 | +0.6% |
| Window resizing | 5.476 | 4.102 | -25.1% |

## Final narrow menu trial — also reverted

These are per-operation averages within longer batches. Session restore is unchanged in this narrow candidate and is retained as a comparison control.

| Workload | Before (ms) | Candidate (ms) | Change | Paired interval |
|---|---:|---:|---:|---:|
| Warm session restore · 200 tabs | 0.487 | 0.482 | -0.93% | -4.44% to +2.15% |
| Space context menu · batched | 0.004743 | 0.004658 | -1.78% | -4.12% to -0.79% |
| Spaces menu · batched | 0.020 | 0.020 | -0.59% | -1.50% to +2.01% |
| Tab context menu · batched | 0.016 | 0.016 | -1.55% | -3.19% to +0.42% |

## All measured workloads in the rejected broad candidate

### Browser actions

![Browser actions](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-targeted-regressions-20261001/browser-actions.png)

### History queries

![History queries](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-targeted-regressions-20261001/history-queries.png)

### Graphics & controls

![Graphics & controls](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-targeted-regressions-20261001/graphics-controls.png)

### Additional browser actions

![Additional browser actions](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-targeted-regressions-20261001/additional-actions.png)

Temporary experiment binaries, object copies and capture files were removed after their evidence was preserved. The reusable test runner remains. All five static charts were visually checked, and all 56 plotted measurements match the evidence JSON.

## Reproduce safely

```sh
python3 scripts/check-ui.py --offscreen --browser --runs 9 --warmups 3 --output /tmp/brook-browser-check

BROOK_CHECK_MODEL_ONLY=1 python3 scripts/check-ui.py --offscreen --browser --runs 15 --warmups 4 --output /tmp/brook-model-check
```

The model-only mode averages 2,000 menu constructions and 100 session restores per sample. The full mode covers all settings panes unless `BROOK_CHECK_FOCUSED_SETTINGS=1` selects Appearance and Layout. Use the frozen harnesses, before patch, candidate patch and recorded paired drivers in the evidence JSON to reproduce the discarded experiments. Visible test modes remain disabled without explicit permission.
