# Brook validation — interrupted run

**The six-pair test campaign did not finish.** It was stopped at the user’s request after the visible tests caused discomfort. No visual tests were restarted to prepare this report.

## Completed checks

- Seven native suites completed with no assertion failure: four UI suites and three browser suites.
- Release and Debug builds passed. Static analysis completed with 40 existing warnings.
- All 484 paired core UI captures were pixel-identical: 242 states in each of two pairs.
- Six of eleven additional browser/settings captures matched. Five settings captures differed: Advanced, Boosts, Layout, Passwords and Shortcuts. The Layout pair shows different window heights and unsettled pane content. These are unresolved visual checks, not established production regressions.
- All 36 live native transitions in the three completed browser suites finished. Each suite covered six layout directions with Reduce Motion on and off.
- Each completed browser suite collected 60 visible WebKit frame intervals, for 180 observations. No frame observation timed out; no settling timeout occurred.
- History ranking, symbols, control state, tab-row edits, focus, lifetime, menus, pinning, favorites, split behavior, command-bar and find-bar assertions passed in the completed suites.
- All ten settings selections passed their index/window assertions. Their final rendered content was not fully verified.

## Bar charts and timing scope

[All four static bar charts (PDF)](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-benchmark-charts-interrupted-20261001/brook-benchmarks.pdf)

Charts compare original commit `550abacceb5f87026838b09b57a7b05a0610980f` with the current optimized source. This differs from the previous chart’s incremental baseline.
Only matched, fully completed processes contribute to the charts. Graphics/controls have two pairs and 40 samples per version; browser/history/additional actions have one pair and 20 samples per version. All used five warmups per process. The extra completed current-browser trial and saved portions of the interrupted baseline trial are retained in the JSON but excluded from paired summaries.
Values are medians in milliseconds. Negative changes mean a lower measured median. They are descriptive readings, not confirmed speedups or equivalence claims. The planned six-pair confidence analysis was not run on this incomplete experiment. The startup rerun did not begin; no previous startup result is substituted.
Browser timings end at layout/display submission. Settings timings cover selection requests, not completed animations. Graphics rows cover the entire named batch.

## Browser actions

![Browser actions](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-benchmark-charts-interrupted-20261001/browser-actions.png)

| Workload | Before (ms) | After (ms) | Observed change | Samples/version |
|---|---:|---:|---:|---:|
| Startup to window submission | — | — | Not run | 0 |
| Warm session restore · 200 tabs | 0.463 | 0.422 | -8.8% | 20 |
| Address-bar typing · 20k history | 47.411 | 17.683 | -62.7% | 20 |
| Local page loading | 10.186 | 6.040 | -40.7% | 20 |
| Page scroll script round trip | 0.430 | 0.492 | +14.4% | 20 |
| Window resizing | 3.818 | 3.705 | -2.9% | 20 |
| Split-view resizing | 4.773 | 1.751 | -63.3% | 20 |
| Layout transition setup | 18.818 | 18.739 | -0.4% | 20 |
| Sidebar · switch tab | 5.481 | 2.798 | -49.0% | 20 |
| Sidebar · open + close tab | 71.512 | 9.126 | -87.2% | 20 |
| Sidebar · switch space | 37.760 | 5.858 | -84.5% | 20 |
| Sidebar · scroll tabs | 11.582 | 6.257 | -46.0% | 20 |
| Top bar · switch tab | 4.227 | 3.363 | -20.4% | 20 |
| Top bar · open + close tab | 13.381 | 9.947 | -25.7% | 20 |
| Top bar · switch space | 44.287 | 17.434 | -60.6% | 20 |
| Top bar · scroll tabs | 1.095 | 1.076 | -1.8% | 20 |
| Compact · switch tab | 6.342 | 4.895 | -22.8% | 20 |
| Compact · open + close tab | 17.495 | 12.569 | -28.2% | 20 |
| Compact · switch space | 45.899 | 18.669 | -59.3% | 20 |
| Compact · scroll tabs | 1.089 | 1.048 | -3.8% | 20 |

## History queries

![History queries](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-benchmark-charts-interrupted-20261001/history-queries.png)

| Workload | Before (ms) | After (ms) | Observed change | Samples/version |
|---|---:|---:|---:|---:|
| 1,000 entries · title | 1.753 | 0.362 | -79.3% | 20 |
| 1,000 entries · Unicode | 1.902 | 0.519 | -72.7% | 20 |
| 1,000 entries · no match | 1.930 | 0.562 | -70.9% | 20 |
| 1,000 entries · URL prefix | 2.119 | 0.684 | -67.7% | 20 |
| 20,000 entries · title | 37.436 | 7.956 | -78.7% | 20 |
| 20,000 entries · Unicode | 42.127 | 11.553 | -72.6% | 20 |
| 20,000 entries · no match | 41.225 | 12.147 | -70.5% | 20 |
| 20,000 entries · URL prefix | 44.524 | 16.421 | -63.1% | 20 |
| 20,000 entries · first query | 37.939 | 33.499 | -11.7% | 20 |

## Graphics & controls

![Graphics & controls](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-benchmark-charts-interrupted-20261001/graphics-controls.png)

| Workload | Before (ms) | After (ms) | Observed change | Samples/version |
|---|---:|---:|---:|---:|
| Compact tab refresh · 300 calls | 27.710 | 1.010 | -96.4% | 40 |
| Edge fades · 10,000 calls | 11.766 | 0.420 | -96.4% | 40 |
| Hover updates · 1,000 calls | 4.994 | 4.636 | -7.2% | 40 |
| Sidebar progress · 1,000 calls | 262.596 | 0.002042 | -100.0% | 40 |
| Top-bar progress · 1,000 calls | 153.874 | 0.002042 | -100.0% | 40 |
| Repeated symbols · 10,000 calls | 477.745 | 0.752 | -99.8% | 40 |
| Changing symbols · 1,000 calls | 47.994 | 9.941 | -79.3% | 40 |
| Tracking areas · 10,000 calls | 3.795 | 0.845 | -77.7% | 40 |
| Sidebar fallback icons · 1,000 calls | 100.138 | 3.496 | -96.5% | 40 |
| Sidebar supplied icons · 1,000 calls | 47.299 | 3.469 | -92.7% | 40 |
| Sidebar icon changes · 1,000 calls | 75.965 | 8.552 | -88.7% | 40 |
| Favorite fallback icons · 1,000 calls | 47.518 | 0.622 | -98.7% | 40 |
| Favorite supplied icons · 1,000 calls | 0.626 | 0.612 | -2.3% | 40 |
| Favorite icon changes · 1,000 calls | 26.303 | 5.140 | -80.5% | 40 |
| Extension fallback icons · 1,000 calls | 50.067 | 0.725 | -98.6% | 40 |
| Extension supplied icons · 1,000 calls | 0.629 | 0.635 | +0.8% | 40 |
| Extension icon changes · 1,000 calls | 28.821 | 6.107 | -78.8% | 40 |

## Additional browser actions

![Additional browser actions](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-benchmark-charts-interrupted-20261001/additional-actions.png)

| Workload | Before (ms) | After (ms) | Observed change | Samples/version |
|---|---:|---:|---:|---:|
| Tab context menu | 0.066 | 0.068 | +3.3% | 20 |
| Space context menu | 0.035 | 0.041 | +16.4% | 20 |
| Spaces menu | 0.086 | 0.095 | +10.5% | 20 |
| Command bar · open + close | 4.089 | 6.141 | +50.2% | 20 |
| Find bar · open + close | 2.973 | 2.994 | +0.7% | 20 |
| Pin + unpin tab | 66.679 | 45.518 | -31.7% | 20 |
| Favorite + unfavorite tab | 65.798 | 8.095 | -87.7% | 20 |
| Split · open, swap + separate | 72.316 | 50.933 | -29.6% | 20 |
| Settings · General request | 9.009 | 9.239 | +2.6% | 20 |
| Settings · Appearance request | 17.198 | 17.187 | -0.1% | 20 |
| Settings · Layout request | 22.688 | 23.228 | +2.4% | 20 |
| Settings · Tabs request | 13.465 | 13.686 | +1.6% | 20 |
| Settings · Search request | 12.668 | 13.030 | +2.9% | 20 |
| Settings · Websites request | 10.423 | 10.635 | +2.0% | 20 |
| Settings · Passwords request | 14.035 | 11.680 | -16.8% | 20 |
| Settings · Boosts request | 3.704 | 3.489 | -5.8% | 20 |
| Settings · Shortcuts request | 4.366 | 3.754 | -14.0% | 20 |
| Settings · Advanced request | 5.268 | 4.949 | -6.1% | 20 |

## Remaining gaps

- Startup rerun did not begin.
- Five settings screenshots differ. The Layout pair has different window heights and unsettled pane content; visual equivalence remains unresolved.
- Settings timings measure selection requests and layout/display submission, not completed pane transitions.
- Live callback observations do not prove physical screen presentation or universal frame-rate behavior.
- Real network services, credentials/biometric flows and third-party extension integration were excluded.

## Safe continuation

The default browser/startup/paired commands now refuse to start without explicit permission for visible tests. The native fixture has the same guard. Three CLI denial checks passed without launching an app. Do not enable visible tests without new, explicit user approval.
No browser production code was changed during this reporting step. The saved timing evidence uses the earlier frozen harness, retained with source hashes and the exact production patch in the JSON.

[Raw samples, completed checks, source snapshots and interrupted-run evidence](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/browser-validation-20261001.json)

The foreground opt-in guard also passed a native syntax check. Temporary test binaries and the comparison checkout were removed after the evidence was saved.
