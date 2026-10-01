# Brook regression investigation — 1 October 2026

**The zero-regression target is not established.** Two additional production optimizations are implemented and checked. The completed offscreen comparison has 53 lower medians and 12 higher medians. All readings, including increases, are retained below.

[All static bar charts (PDF)](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-fixes-20261001/brook-benchmarks.pdf) · [Raw samples and source snapshots](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/browser-regression-fixes-20261001.json)

## Changes in this pass

- [CommandBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/CommandBar.mm:533): refresh existing suggestion cells when the row count is unchanged. Row selection, text, icons, actions and selected-state colors still update. Count changes retain the original reload path.
- [ExtensionsBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/ExtensionsBar.mm:42): update tint when the displayed icon changes and update opacity only when its value changes. Badge, label, enabled-state and icon changes remain covered.
- No layouts, assets, animation durations or easing functions were changed. Earlier production optimizations were preserved. An initial command-bar row-pooling experiment was rejected because it did not improve timings.

AppKit documents that a full table reload discards visible row and cell views. The command-bar change avoids that repeated work while reconfiguring current content. [Apple: NSTableView.reloadData](https://developer.apple.com/documentation/appkit/nstableview/reloaddata%28%29).

## Completed checks

- Release and Debug builds passed. Static analysis completed with 40 existing diagnostics. Two existing WKProcessPool deprecation warnings appeared while recompiling. Release signing verification and plist validation passed.
- 1036/1036 paired RGBA image comparisons matched. This includes four pairs of 248 core/control/command-bar captures, four browser history-suggestion captures, and four pairs of ten corrected settings captures. The 40 preliminary settings comparisons remain in the raw evidence and are excluded from this final count.
- All 16 main suites and eight settled-settings suites passed their assertions. Startup completed 30 measured before/after fresh-process pairs plus four warmup pairs.
- History ranking, limits, Unicode, persistence, mutable inputs, control interactions, row reuse, tab and space operations, focus, lifetime, menus, find, pinning, favorites, splits and all settings selections were checked. Command-bar tests also check changed titles, row-count changes, selection and rendered content.
- Native transition logic was checked through simulated ticks with normal and reduced motion at 60 and 120 Hz. These are not live display frame-rate measurements.
- Window ordering, child-window ordering and application activation were blocked in the fixture. Assertions checked real window visibility and onscreen WindowServer entries. No visible test was run.

## Settings benchmark correction

The fixed 300 ms preparation delay did not establish a settled starting state. The diagnostic pilot found an outgoing pane still attached after that delay in 28 of 30 preparations. Repeating a selection while its predecessor was still transitioning made those timing comparisons unsuitable for claiming an ordinary settled-pane regression.

The harness now waits until the selected pane is attached and all inactive loaded panes are detached, both before preparation and before timing the next selection. The tables use a separate four-pair comparison of all ten settings panes with this condition. The browser fixture starts fresh for this focused check, so this isolates pane selection rather than reproducing the preceding full browser sequence. Production transitions were not accelerated or disabled. Original fixed-delay measurements remain in the evidence JSON.

## Measurement and remaining limits

- Baseline: original commit `550abacceb5f87026838b09b57a7b05a0610980f`. Current production source hashes and both patches are stored in the evidence. This is not an incremental comparison against the start of this turn.
- Main protocol: four alternating AB/BA process pairs, four warmups and 12 measured samples per workload per process: 48 samples per version. Corrected settings: four pairs, two warmups and seven samples: 28 per version. Startup: 30 paired samples per version.
- Menu values are per-construction averages over batches of 100. Other graphics batch sizes are in their labels. Startup measures hidden-window setup. The command-bar preparation timing cannot exercise visibility-dependent dismissal while presentation is blocked.
- Intervals below use paired process-median log ratios: all 256 possible bootstrap resamples for four pairs, and 20,000 paired startup resamples with seed 20261001. These are exploratory 95% intervals, unadjusted for multiple comparisons. They describe measurements, not proof of a code-level cause. Medians, p95, ranges, CVs and every raw sample are retained.
- This shared desktop was not isolated from scheduling or background activity. No timing sample was dropped. Small increases and uncertain intervals have not been relabelled as speedups.
- WebKit script round-trip timing includes IPC and run-loop scheduling. It does not measure native scrolling frames; no Brook-code cause has been established for its increase.
- Live presentation, compositor pacing and actual window activation remain unverified. Real network, credential/biometric and external extension integration are outside these synthetic fixtures.

## Source review of remaining higher timings

The menu-construction methods and menu-item initializer, FindBar implementation, tab-scroll event handler, settings-window implementation, session-state implementation and WebView factory match the original source. Their section hashes are recorded. This narrows the changed code to investigate; it does not establish equal runtime performance because shared dependencies, retained views and asynchronous work can still affect these paths. No further safe production fix was established for the remaining increases.

**Overall verdict: INCONCLUSIVE. The zero-regression acceptance condition is not passed.** The two new optimizations have clear measured benefits; the browser-wide condition remains unresolved.

## Higher measured medians

| Workload | Before (ms) | After (ms) | Change | Paired 95% interval |
|---|---:|---:|---:|---:|
| Command bar · hidden preparation | 1.354 | 1.533 | +13.3% | -6.1% to +39.3% |
| Compact · scroll tabs | 0.581 | 0.602 | +3.5% | -19.0% to +23.3% |
| Find bar · open + close | 3.085 | 3.276 | +6.2% | -15.5% to +16.5% |
| WebKit scroll script round trip | 0.688 | 1.019 | +48.1% | +4.3% to +63.2% |
| Warm session restore · 200 tabs | 0.417 | 0.420 | +0.5% | -2.3% to +9.5% |
| Settings · Appearance request | 21.017 | 23.103 | +9.9% | -12.8% to +43.9% |
| Settings · Layout request | 30.704 | 33.097 | +7.8% | -11.5% to +25.0% |
| Space context menu · batched | 0.004823 | 0.005250 | +8.9% | +1.4% to +18.9% |
| Spaces menu · batched | 0.021 | 0.021 | +1.1% | -3.2% to +12.6% |
| Tab context menu · batched | 0.015 | 0.016 | +7.8% | -1.0% to +9.4% |
| Top bar · scroll tabs | 0.611 | 0.639 | +4.5% | -18.3% to +40.0% |
| Window resizing | 3.643 | 3.781 | +3.8% | -24.1% to +12.6% |

## Browser actions

![Browser actions](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-fixes-20261001/browser-actions.png)

| Workload | Before (ms) | After (ms) | Change |
|---|---:|---:|---:|
| Startup setup · hidden window | 143.140 | 131.181 | -8.4% |
| Warm session restore · 200 tabs | 0.417 | 0.420 | +0.5% |
| Address-bar typing · 20k history | 41.917 | 9.934 | -76.3% |
| Local page loading | 9.636 | 6.723 | -30.2% |
| WebKit scroll script round trip | 0.688 | 1.019 | +48.1% |
| Window resizing | 3.643 | 3.781 | +3.8% |
| Split-view resizing | 4.750 | 1.918 | -59.6% |
| Layout transition setup | 9.769 | 9.030 | -7.6% |
| Sidebar · switch tab | 4.866 | 2.517 | -48.3% |
| Sidebar · open + close tab | 64.627 | 9.013 | -86.1% |
| Sidebar · switch space | 33.569 | 6.317 | -81.2% |
| Sidebar · scroll tabs | 10.592 | 6.603 | -37.7% |
| Top bar · switch tab | 3.487 | 3.317 | -4.9% |
| Top bar · open + close tab | 10.604 | 10.479 | -1.2% |
| Top bar · switch space | 39.177 | 16.598 | -57.6% |
| Top bar · scroll tabs | 0.611 | 0.639 | +4.5% |
| Compact · switch tab | 4.962 | 4.714 | -5.0% |
| Compact · open + close tab | 12.986 | 11.878 | -8.5% |
| Compact · switch space | 40.086 | 16.579 | -58.6% |
| Compact · scroll tabs | 0.581 | 0.602 | +3.5% |

## History queries

![History queries](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-fixes-20261001/history-queries.png)

| Workload | Before (ms) | After (ms) | Change |
|---|---:|---:|---:|
| 1,000 entries · title | 1.755 | 0.367 | -79.1% |
| 1,000 entries · Unicode | 1.909 | 0.521 | -72.7% |
| 1,000 entries · no match | 1.924 | 0.562 | -70.8% |
| 1,000 entries · URL prefix | 2.071 | 0.691 | -66.6% |
| 20,000 entries · title | 35.628 | 7.552 | -78.8% |
| 20,000 entries · Unicode | 38.777 | 10.610 | -72.6% |
| 20,000 entries · no match | 39.245 | 11.759 | -70.0% |
| 20,000 entries · URL prefix | 42.669 | 14.981 | -64.9% |
| 20,000 entries · first query | 35.711 | 31.745 | -11.1% |

## Graphics & controls

![Graphics & controls](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-fixes-20261001/graphics-controls.png)

| Workload | Before (ms) | After (ms) | Change |
|---|---:|---:|---:|
| Command-bar rows · 100 refreshes | 359.402 | 16.911 | -95.3% |
| Compact tab refresh · 300 calls | 26.324 | 0.994 | -96.2% |
| Edge fades · 10,000 calls | 11.269 | 0.462 | -95.9% |
| Hover updates · 1,000 calls | 4.973 | 4.580 | -7.9% |
| Sidebar progress · 1,000 calls | 258.380 | 0.001792 | >99.9% lower |
| Top-bar progress · 1,000 calls | 151.125 | 0.001792 | >99.9% lower |
| Repeated symbols · 10,000 calls | 470.299 | 0.719 | -99.8% |
| Changing symbols · 1,000 calls | 47.033 | 9.722 | -79.3% |
| Tracking areas · 10,000 calls | 3.804 | 0.863 | -77.3% |
| Sidebar fallback icons · 1,000 calls | 97.122 | 3.406 | -96.5% |
| Sidebar supplied icons · 1,000 calls | 46.723 | 3.272 | -93.0% |
| Sidebar icon changes · 1,000 calls | 74.152 | 8.381 | -88.7% |
| Favorite fallback icons · 1,000 calls | 47.265 | 0.611 | -98.7% |
| Favorite supplied icons · 1,000 calls | 0.614 | 0.611 | -0.5% |
| Favorite icon changes · 1,000 calls | 25.783 | 5.005 | -80.6% |
| Extension fallback icons · 1,000 calls | 49.020 | 0.268 | -99.5% |
| Extension supplied icons · 1,000 calls | 0.626 | 0.189 | -69.8% |
| Extension icon changes · 1,000 calls | 28.489 | 5.856 | -79.4% |

## Additional browser actions

![Additional browser actions](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-fixes-20261001/additional-actions.png)

| Workload | Before (ms) | After (ms) | Change |
|---|---:|---:|---:|
| Tab context menu · batched | 0.015 | 0.016 | +7.8% |
| Space context menu · batched | 0.004823 | 0.005250 | +8.9% |
| Spaces menu · batched | 0.021 | 0.021 | +1.1% |
| Command bar · hidden preparation | 1.354 | 1.533 | +13.3% |
| Find bar · open + close | 3.085 | 3.276 | +6.2% |
| Pin + unpin tab | 62.211 | 42.304 | -32.0% |
| Favorite + unfavorite tab | 61.404 | 8.337 | -86.4% |
| Split · open, swap + separate | 68.320 | 47.199 | -30.9% |
| Settings · General request | 16.158 | 11.619 | -28.1% |
| Settings · Appearance request | 21.017 | 23.103 | +9.9% |
| Settings · Layout request | 30.704 | 33.097 | +7.8% |
| Settings · Tabs request | 18.371 | 16.353 | -11.0% |
| Settings · Search request | 24.486 | 16.849 | -31.2% |
| Settings · Websites request | 19.271 | 13.848 | -28.1% |
| Settings · Passwords request | 21.323 | 14.847 | -30.4% |
| Settings · Boosts request | 9.469 | 4.260 | -55.0% |
| Settings · Shortcuts request | 8.927 | 4.563 | -48.9% |
| Settings · Advanced request | 11.677 | 5.930 | -49.2% |

## Reproduce safely

```sh
python3 scripts/check-ui.py --offscreen --paired-baseline /path/to/original/Objects-normal/arm64 --pairs 4 --runs 12 --warmups 4 --output /tmp/brook-offscreen-comparison

BROOK_CHECK_SETTINGS_ONLY=1 python3 scripts/check-ui.py --offscreen --browser --objects /path/to/Objects-normal/arm64 --runs 7 --warmups 2 --output /tmp/brook-settled-settings
```

Build the recorded original revision in a separate directory for baseline objects. The current runner links the same current guarded native harness against each object set. For the exact earlier full-run harness, use the frozen source stored in the JSON. The current harness includes the subsequent settling correction. Never enable visible tests without new explicit user approval.

## Cleanup

Temporary comparison checkouts, compiled test executables, fixture profiles and raw captures were removed after retaining the samples, patches, harnesses, logs, pixel-comparison hashes and static charts. The reusable test runner and report artifacts remain.
