# Latest correction — compact scrolling, 1 October 2026

**Compact-scroll median is now 5.56% lower than the baseline code behind the reported +3.9% comparison.** The one-line fix independently improved all four paired confirmation processes (6.77% pooled median reduction). All 359 visual comparisons matched; builds and checks passed. Tests remained offscreen.

[Compact-scroll correction and bar chart](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/compact-scroll-fix-20261001.md) · [Raw evidence](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/compact-scroll-fix-20261001.json)

This correction covers compact scrolling. Earlier reports below remain historical; Find remains outside this follow-up.

---

# Latest scoped follow-up — five reported paths, 1 October 2026

**Three supported speedups; Find and compact scrolling remain unconfirmed. Zero slowdowns is not certified.** Top progress -20.9%, sidebar progress -21.9%, hidden command preparation -67.3%. Find pooled median -1.5%; compact scrolling +3.9%. These compare against the pre-request working tree, not the historical commit baseline below.

[Current report and static bar charts](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/five-path-regression-fixes-20261001.md) · [Raw evidence](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/five-path-regression-fixes-20261001.json)

Only four production files changed in this pass. All 343 controlled native visual comparisons matched, builds and signing passed, and all execution was offscreen. Historical reports follow unchanged.

---

# Latest rendering fix and regression controls — 1 October 2026

**Color resolution is proven 47.3–48.6% faster. The browser-wide zero-slowdown requirement remains uncertified.** Four of the 12 reported browser medians and two separate progress microbenchmarks still read higher. Identical-build controls also vary substantially; they do not establish that every code change is harmless. All 1,090 pixel comparisons matched, and 68 offscreen suites passed.

[Current report](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/regression-isolation-20261001.md) · [Bar charts for all 60 measured workloads](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-isolation-20261001/brook-benchmarks.pdf) · [Raw evidence](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/regression-isolation-20261001.json)

Earlier sections below retain their original baselines and measurements. They are historical results, not a certification of the current browser.

---

# Latest targeted follow-up — 1 October 2026

**The no-slowdown requirement remains unmet.** All new trial production changes were rejected and reverted. The 12 higher readings from the previous comparison remain unresolved. The new charts show rejected experiments, not the current code.

[Follow-up report](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/targeted-regression-followup-20261001.md) · [Experimental bar charts](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-targeted-regressions-20261001/brook-benchmarks.pdf) · [Raw evidence](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/targeted-regression-followup-20261001.json)

---

# Latest browser-wide check — 1 October 2026

**INCONCLUSIVE: the zero-regression target is not established.** The completed offscreen comparison measured 53 lower medians and 12 higher medians across 65 workloads. All 1,036 final paired captures matched. Earlier evidence below uses different baselines and protocols and must not be treated as a browser-wide zero-regression result.

[Current report](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/browser-regression-fixes-20261001.md) · [All static bar charts](/Users/xxxxxxxxxx/.codex/visualizations/2026/09/29/01a0eef1-a5a7-7972-b057-9afee4a34f30/brook-regression-fixes-20261001/brook-benchmarks.pdf) · [Current raw evidence](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/browser-regression-fixes-20261001.json)

---

# Speedup Proof

## ✅ PROVEN — 61.72% less time

> Correctness passed and the lower after median exceeds the noise threshold.

**Project:** Brook  
**Target:** Switching spaces with 200 tabs across two spaces; top-bar layout  
**Preserved behavior:** Same visual design, tab order, selection, keyboard focus, hover, accessibility, history ranking, and existing animation settings.  
**Generated:** 2026-10-01

## Before vs after

| Measurement | Before | After |
|---|---:|---:|
| Median runtime | 39.751 ms | 15.217 ms |
| p95 runtime | 40.901 ms | 16.111 ms |
| Mean runtime | 39.827 ms | 15.286 ms |
| Range | 38.84–41.213 ms | 14.405–16.867 ms |
| Variability | 1.57% CV | 3.3% CV |
| Measured runs | 30 | 30 |

**Speedup ratio:** 2.612×  
**Proof threshold:** 6.6%  
**Correctness:** PASSED

## What changed

Reuse compatible sidebar rows and outgoing top/compact tab views; reset interaction state and preserve active editing/focus. Reuse configured symbol images through an evictable cache that returns independent copies. Normalize history URLs in one mutable buffer, retain immutable cached strings, and partially sort only the requested results, using encounter order for stable ties. Return before retaining the tab for progress-only chrome events; real updates acquire a strong local reference before use, and content progress rendering is unchanged.

**Why behavior remains equivalent:** Reused views are rebound to the incoming tabs and refreshed from current settings; busy/focused views keep the full replacement path. Sidebar reuse requires identical row kinds and counts and no hidden rows. Symbol results match the original factory, and history results match the original stable-sort oracle.

| Complexity | Before | After |
|---|---:|---:|
| Estimate | History ranking: O(m log m) for m matches. Space changes repeatedly create tab view hierarchies. | History ranking: O(m log k) for k requested results, with the original O(m) match storage. Space changes reconfigure eligible existing views. |

### Changed files

- [Utilities.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/App/Utilities.mm:1) — Cache symbol configurations and return independent image copies.
- [Stores.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/Browser/Stores.mm:1) — Reduce history normalization allocations and sort only the requested results.
- [Controls.h](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/Controls.h:1) — Expose interaction reset for reused controls.
- [Controls.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/Controls.mm:1) — Reset hover and pressed state before reuse.
- [SidebarView.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/SidebarView.mm:1) — Rebind equal-shaped space rows without full table reconstruction.
- [TopBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/TopBar.mm:1) — Reuse outgoing tab views while protecting editing and keyboard focus.
- [check-ui.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/scripts/check-ui.mm:1) — Extend behavioral, pixel, mutation and lifetime checks.

## Correctness checks

| Check | Status | Evidence |
|---|---|---|
| Release and Debug builds | ✅ passed | Both configurations built successfully. |
| Native visual comparisons | ✅ passed | 242 RGBA pixel-identical captures in each of two paired runs; light, dark, increased contrast, fonts, tab styles and layouts. |
| Space switching and row edits | ✅ passed | 68 sidebar edit cases; 24 top/compact space-switch captures; variable counts, pins, hover, keyboard focus, held mouse buttons, address editing and closed-tab release. |
| Symbols | ✅ passed | 144 appearance/name/size/weight combinations equal the original AppKit factory; mutating a returned image does not affect subsequent callers. |
| History oracle | ✅ passed | Original ranking and stable ties, Unicode, empty and missing values, limits, mutable inputs, updates, pruning, persistence and clear. |
| Motion | ✅ passed | 24 simulated 60/120 Hz transitions with Reduce Motion on/off; original space-transition type and duration checks passed. |
| Static analyzer | ✅ passed | Analysis completed with 40 existing warnings, none in implementations changed during this pass. |
| Whitespace | ✅ passed | git diff --check passed. |

## Benchmark protocol

**Workload:** Release arm64 production object files on the same Apple M4 Pro. Two paired processes in before/after, then after/before order. Each process uses 4 warmups and 15 measured samples: 30 samples per variant. Startup alternates order in 11 fresh-process pairs: 2 warmups and 9 measured launches per variant. Fixtures are synthetic and local.  
**Command:** `Command unavailable`  
**Warmups:** —  
**Measured runs:** 3 per version

## Reproduce

```bash
python3 scripts/check-ui.py --output /tmp/brook-ui-proof
```
```bash
python3 scripts/check-ui.py --browser --output /tmp/brook-browser-proof
```
```bash
python3 scripts/check-ui.py --startup --output /tmp/brook-startup-proof
```

## Limitations

- The baseline is the working tree at the start of this pass, including earlier optimizations. Earlier charts used older saved baselines; their slower readings did not establish code regressions.
- A verdict uses the speedup-proof guardrail: CV no greater than 15%, effect greater than both 3% and twice the larger CV. This is not a formal significance test. Inconclusive rows are not evidence of either a gain or a regression.
- Browser fixture: 200 blank tabs across two spaces, synthetic 1,000/20,000-entry history, local HTML; external services are disabled. Batch rows time the full named batch, not a single interaction.
- UI timing ends at main-thread layout/display submission. Startup excludes OS process loading. Live frame-rate measurements remain inconclusive because WebKit page visibility was hidden and callbacks timed out.
- Tiny changes on untouched control paths, including any PROVEN timer-scale result, are not attributed to these patches. Only directly affected workloads support optimization claims.
- The symbol cache has an NSCache count limit of 128 and may evict entries. The view reuse pool exists only during reload; it does not cache closed tabs. Whole-browser peak memory was not measured.

## Residual risks

- Performance outside these fixtures, network behavior and compositor FPS remain unmeasured.

## Notes

- The results JSON retains baseline/final patches and raw samples. Rebuild each variant separately, use the same final harness, and alternate the comparison order. Existing evidence from earlier passes remains below.

---

Generated by `$speedup-proof`. Runtime evidence and correctness checks determine the verdict.

## Complete paired results

No comparison crossed the regression threshold. Rows marked INCONCLUSIVE are not proven faster. Times are medians in milliseconds.

### Browser actions

20 workloads · median milliseconds per action.

| Workload | Before (ms) | After (ms) | After p95 (ms) | Change in median time | Verdict |
|---|---:|---:|---:|---:|---|
| Startup to window submission | 182.606 | 177.898 | 183.343 | -2.58% | INCONCLUSIVE |
| Warm session restore · 200 tabs | 0.420 | 0.417 | 0.445 | -0.72% | INCONCLUSIVE |
| Address-bar typing · 20k history | 18.855 | 16.611 | 17.767 | -11.90% | PROVEN |
| Local page loading | 15.487 | 15.068 | 19.442 | -2.70% | INCONCLUSIVE |
| Page scroll script round trip | 0.123 | 0.113 | 0.154 | -8.17% | INCONCLUSIVE |
| Window resizing | 2.100 | 2.020 | 2.390 | -3.77% | INCONCLUSIVE |
| Split-view resizing | 1.160 | 1.413 | 7.785 | +21.83% | INCONCLUSIVE |
| Layout transition setup | 13.558 | 12.237 | 33.231 | -9.74% | INCONCLUSIVE |
| Sidebar · switch tab | 1.820 | 3.254 | 9.383 | +78.82% | INCONCLUSIVE |
| Sidebar · open + close tab | 8.708 | 8.086 | 18.365 | -7.15% | INCONCLUSIVE |
| Sidebar · switch space | 25.370 | 5.120 | 8.233 | -79.82% | INCONCLUSIVE |
| Sidebar · scroll tabs | 5.007 | 4.948 | 5.417 | -1.17% | INCONCLUSIVE |
| Top bar · switch tab | 8.270 | 8.229 | 11.154 | -0.49% | INCONCLUSIVE |
| Top bar · open + close tab | 8.613 | 8.081 | 13.037 | -6.17% | INCONCLUSIVE |
| Top bar · switch space | 39.751 | 15.217 | 16.111 | -61.72% | PROVEN |
| Top bar · scroll tabs | 0.342 | 0.331 | 0.966 | -3.05% | INCONCLUSIVE |
| Compact · switch tab | 6.541 | 6.521 | 14.699 | -0.31% | INCONCLUSIVE |
| Compact · open + close tab | 12.666 | 9.461 | 11.817 | -25.30% | INCONCLUSIVE |
| Compact · switch space | 41.704 | 16.559 | 17.075 | -60.29% | PROVEN |
| Compact · scroll tabs | 0.347 | 0.334 | 0.733 | -3.69% | INCONCLUSIVE |

### History queries

9 workloads · median milliseconds per query.

| Workload | Before (ms) | After (ms) | After p95 (ms) | Change in median time | Verdict |
|---|---:|---:|---:|---:|---|
| 1,000 entries · title | 0.405 | 0.368 | 0.376 | -9.13% | PROVEN |
| 1,000 entries · Unicode | 0.552 | 0.536 | 0.547 | -2.74% | INCONCLUSIVE |
| 1,000 entries · no match | 0.574 | 0.582 | 0.606 | +1.44% | INCONCLUSIVE |
| 1,000 entries · URL prefix | 0.720 | 0.700 | 0.717 | -2.81% | INCONCLUSIVE |
| 20,000 entries · title | 8.202 | 7.453 | 7.879 | -9.13% | PROVEN |
| 20,000 entries · Unicode | 11.854 | 10.589 | 12.067 | -10.67% | PROVEN |
| 20,000 entries · no match | 11.511 | 11.706 | 12.009 | +1.70% | INCONCLUSIVE |
| 20,000 entries · URL prefix | 15.230 | 15.426 | 16.292 | +1.28% | INCONCLUSIVE |
| 20,000 entries · first query | 34.384 | 32.096 | 34.414 | -6.66% | INCONCLUSIVE |

### Graphics & controls

17 workloads · median milliseconds for the entire named batch.

| Workload | Before (ms) | After (ms) | After p95 (ms) | Change in median time | Verdict |
|---|---:|---:|---:|---:|---|
| Compact tab refresh · 300 calls | 0.984 | 0.972 | 1.072 | -1.24% | INCONCLUSIVE |
| Edge fades · 10,000 calls | 0.423 | 0.417 | 0.426 | -1.41% | INCONCLUSIVE |
| Hover updates · 1,000 calls | 4.567 | 4.527 | 4.666 | -0.88% | INCONCLUSIVE |
| Sidebar progress · 1,000 calls | 0.004 | 0.003 | 0.003 | -22.99% | PROVEN |
| Top-bar progress · 1,000 calls | 0.004 | 0.002 | 0.002 | -53.76% | PROVEN |
| Repeated symbols · 10,000 calls | 0.724 | 0.799 | 0.854 | +10.39% | INCONCLUSIVE |
| Changing symbols · 1,000 calls | 47.445 | 9.531 | 10.266 | -79.91% | PROVEN |
| Tracking areas · 10,000 calls | 0.843 | 0.880 | 1.021 | +4.39% | INCONCLUSIVE |
| Sidebar fallback icons · 1,000 calls | 3.450 | 3.402 | 3.659 | -1.40% | INCONCLUSIVE |
| Sidebar supplied icons · 1,000 calls | 3.490 | 3.409 | 3.716 | -2.34% | INCONCLUSIVE |
| Sidebar icon changes · 1,000 calls | 8.353 | 8.252 | 8.576 | -1.21% | INCONCLUSIVE |
| Favorite fallback icons · 1,000 calls | 0.607 | 0.601 | 0.647 | -1.01% | INCONCLUSIVE |
| Favorite supplied icons · 1,000 calls | 0.614 | 0.611 | 0.655 | -0.42% | INCONCLUSIVE |
| Favorite icon changes · 1,000 calls | 5.184 | 5.052 | 5.270 | -2.56% | INCONCLUSIVE |
| Extension fallback icons · 1,000 calls | 0.713 | 0.705 | 0.723 | -1.20% | INCONCLUSIVE |
| Extension supplied icons · 1,000 calls | 0.632 | 0.615 | 0.623 | -2.68% | INCONCLUSIVE |
| Extension icon changes · 1,000 calls | 6.018 | 5.851 | 6.243 | -2.77% | INCONCLUSIVE |

Detailed samples, comparisons, source hashes and visual evidence are in [speedup-proof-results.json](speedup-proof-results.json), under `regression_followup`.

---

## Earlier optimization evidence

# Speedup Proof

## ✅ PROVEN — 83.53% less time for sidebar tab open + close

> Correctness passed and the lower after median exceeds the noise threshold.

**Project:** Brook  
**Target:** One selected blank-tab open + close with 200 tabs across two spaces; sidebar layout  
**Preserved behavior:** Same appearance, row order, selection, hover, scrolling, accessibility and existing motion. Other structural changes retain full reloads.  
**Generated:** 2026-09-30

## Before vs after

| Measurement | Before | After |
|---|---:|---:|
| Median runtime | 52.676 ms | 8.678 ms |
| p95 runtime | 55.528 ms | 11.54 ms |
| Mean runtime | 52.608 ms | 8.973 ms |
| Range | 48.002–57.443 ms | 7.293–12.552 ms |
| Variability | 4.26% CV | 14.73% CV |
| Measured runs | 30 | 30 |

**Speedup ratio:** 6.07×  
**Proof threshold:** 29.45%  
**Correctness:** PASSED

## What changed

Detect one visible regular-tab insertion or removal, then use AppKit row insertion/removal without adding animation. Reconfigure available cells, preserve the scroll origin, and run the existing favorites, rail-height, space-button and selection updates.

**Why behavior remains equivalent:** The fast path verifies every unaffected row identity and kind. It reads visible-row indices before replacing the model, so AppKit sees a consistent old row count during inspection. Reused cells receive the same configuration and hover reset as a full reload. Offscreen and complex edits keep the original behavior. Exact captures and scroll positions match the full-reload reference in all tested cases.

| Complexity | Before | After |
|---|---:|---:|
| Estimate | Rebuild O(n) row model plus full table reload and visible-row reconstruction | O(n) row comparison plus one native row edit and refresh of available cells; fallback remains a full reload |

### Changed files

- [SidebarView.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/SidebarView.mm:472) — Use guarded incremental sidebar row updates.
- [check-ui.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/scripts/check-ui.mm:436) — Extend the existing native check with full-reload equivalence, fallback, transition and object-lifetime checks.
- [speedup-proof-results.json](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/speedup-proof-results.json:1) — Append sidebar proof while preserving earlier evidence.
- [speedup-proof-report.md](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/speedup-proof-report.md:1) — Record the verdict, scope and limitations.

## Correctness checks

| Check | Status | Evidence |
|---|---|---|
| Release and Debug | ✅ passed | Both builds and the full native UI suite pass. Code signatures and Info.plist files validate. Four final Release browser trials pass. |
| Appearance and row behavior | ✅ passed | 202 PNG pairs are byte-identical in both optimized Release and Debug: 82 existing captures plus 60 edit captures and 60 full-reload reference captures. Row identity, accessibility labels/selection, hover reset and scroll origins match. |
| Fast path and fallbacks | ✅ passed | 60 scenarios across light/dark appearance and regular/icon-only sidebars. Insertion/removal at the start, middle and end; first/last tab; pinned rows; pin-divider changes; reorder; bulk insertion; hidden drag rows; space-transition refresh. Eligible cases issue zero full-table reloads; fallbacks issue one, as before. |
| Motion | ✅ passed | 24 simulated layout morph scenarios per suite. Space-transition type and duration are checked when submitted. No transition parameters or design assets changed; live frame-rate comparison remains inconclusive. |
| Object lifetime | ✅ passed | A removed fixture tab deallocates after the autorelease pool drains, in baseline, Release and Debug. No persistent view cache or new per-tab state was introduced. |
| Static analysis | ⚠️ warnings | Xcode analysis succeeds with the same 40 pre-existing diagnostics, none in SidebarView.mm. Diagnostics are preserved in the results JSON. |
| Scope and syntax | ✅ passed | git diff --check passes. All earlier production changes and the Python runner remain unchanged. The only production file changed this pass is SidebarView.mm. |

## Benchmark protocol

**Workload:** Apple M4 Pro, macOS 27.2, Xcode 27.1, Release arm64. Real BrowserState, BrowserWindowController, sidebar and WebKit production objects. Two process pairs in before/after then after/before order. Four warmups and 15 measured samples per process, 30 samples per variant. Fixture setup is excluded. The primary sample opens a blank tab, submits layout/display, closes the tab, and submits layout/display again.  
**Command:** `python3 scripts/check-ui.py --browser --objects BEFORE_OBJECTS`  
**Warmups:** 4  
**Measured runs:** 30 per version

## Reproduce

```bash
python3 scripts/check-ui.py
```
```bash
python3 scripts/check-ui.py --baseline --objects /path/to/baseline/Objects-normal/arm64 --output /tmp/brook-sidebar-before
```
```bash
python3 scripts/check-ui.py --browser --baseline --objects /path/to/baseline/Objects-normal/arm64 --output /tmp/brook-browser-before
```
```bash
python3 scripts/check-ui.py --browser --objects build/Build/Intermediates.noindex/Brook.build/Release/Brook.build/Objects-normal/arm64 --output /tmp/brook-browser-after
```
```bash
xcodebuild -project Brook.xcodeproj -scheme Brook -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- build analyze
```
```bash
python3 scripts/check-ui.py --objects build/Build/Intermediates.noindex/Brook.build/Debug/Brook.build/Objects-normal/arm64
```

## Limitations

- The primary measurement combines opening and closing one selected blank tab in an already-running browser with 200 tabs across two spaces. It includes main-thread UI/layout/display submission, not physical presentation, OS input delivery or a complete web-page load.
- The fast path applies only to one regular-tab insertion/removal at a visible position (including appending after the visible final row), with all remaining row identities/order unchanged. Offscreen edits, complex changes, pin-divider changes, space transitions, hidden drag rows and inconsistent row counts retain the existing full reload.
- Offscreen incremental insertion produced fractional row offsets in the initial experiment. Those cases use the original reload path; final before/after captures and scroll positions match exactly.
- Browser fixtures use local HTML, synthetic history and a nonpersistent WebKit store. Network suggestions, real sites, extensions, downloads, favicons, password/notification services and content blockers are excluded.
- The other 27 before/after workload comparisons are INCONCLUSIVE. No whole-browser speedup is claimed; space switching still costs approximately 25–44 ms in this fixture.
- Live frame-rate comparison is INCONCLUSIVE: before-2 delivered 60 callbacks; both final optimized trials and before-3 timed out with hidden page visibility. Static captures and simulated clocks do not prove live compositor timing.
- The lifetime check establishes release of the removed fixture tab, not whole-process peak memory, RSS, energy or comprehensive leak freedom. The previous and replacement row vectors coexist only while the update runs.
- Static analysis is not warning-free: 37 existing NSNumber presence checks and three existing nullability diagnostics remain outside the changed source file.

## Residual risks

- Future changes to cell configuration or row types must preserve the comparison and refresh contract. AppKit rendering can vary by macOS release; the full-reload equivalence check should run on supported target systems.

## Notes

- Reconstruct the baseline from the recorded HEAD plus sidebar_rows.baseline.patch_from_head in the results JSON, in a separate checkout. Build Release objects there, then use the current native harness with --baseline. Apply sidebar_rows.optimization_patch for the after version.
- The final trial order is before-2, after-3, after-4, before-3. Earlier development runs were excluded because the reviewed implementation reads the visible-row range before replacing the row model; they were not excluded based on timing values.
- Live WebKit checks require desktop/window-service access and ran with approved unsandboxed execution. They use isolated temporary browser data.
- Earlier reports and raw evidence are preserved. Temporary artifacts from this pass are removed after report validation.

---

Generated by `$speedup-proof`. Runtime evidence and correctness checks determine the verdict.

## Other browser actions

All controls are INCONCLUSIVE; these medians are diagnostic timings, not proven gains or regressions. Values are milliseconds per named action. Raw samples and all 28 comparisons are in [the results JSON](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/speedup-proof-results.json), under `sidebar_rows`.

| Action | Before median | After median | After p95 |
|---|---:|---:|---:|
| sidebar tab switch | 1.724 | 2.249 | 6.995 |
| sidebar space switch | 26.380 | 25.265 | 28.259 |
| sidebar tab list scroll | 5.517 | 5.654 | 6.531 |
| top tab open close | 8.633 | 8.443 | 10.269 |
| compact tab open close | 10.986 | 12.053 | 15.016 |
| top space switch | 41.478 | 41.533 | 44.654 |
| compact space switch | 45.992 | 44.092 | 48.254 |
| window resize | 2.398 | 2.232 | 3.752 |
| split resize | 1.014 | 0.777 | 1.823 |
| layout transition setup | 14.443 | 12.662 | 36.828 |
| address bar keystroke 20000 history | 19.762 | 20.050 | 21.197 |
| local page load to title | 8.450 | 8.228 | 11.400 |

Space switching and offscreen sidebar changes remain candidates for a separate measured pass. This result supports faster visible tab edits, not a claim that the entire browser is fully optimized.

<details>
<summary>Earlier history, icon and UI optimization evidence</summary>

# Speedup Proof

## ✅ PROVEN — 62.35% less time per address-bar keystroke

> Correctness passed and the lower after median exceeds the noise threshold.

**Project:** Brook  
**Target:** One warm address-bar keystroke with 20,000 history entries  
**Preserved behavior:** Same search matches, ranking, tie order, mutation/clear/persistence behavior, graphics, layout and animation timing.  
**Generated:** 2026-09-30

## Before vs after

| Measurement | Before | After |
|---|---:|---:|
| Median runtime | 47.614 ms | 17.924 ms |
| p95 runtime | 49.209 ms | 19.861 ms |
| Mean runtime | 47.679 ms | 18.311 ms |
| Range | 46.53–49.484 ms | 17.143–20.259 ms |
| Variability | 1.54% CV | 5.05% CV |
| Measured runs | 30 | 30 |

**Speedup ratio:** 2.656×  
**Proof threshold:** 10.09%  
**Correctness:** PASSED

## What changed

Reuse normalized history URL/title strings on each history entry. Recompute lazily when the copied URL or title property changes. Production changes are confined to Stores.mm.

**Why behavior remains equivalent:** The matching operations are identical to the original implementation. Each search still applies the current query, visit count, age weighting, dictionary enumeration, stable sort and result limit. Retained source strings prevent pointer reuse from leaving stale values. Pruning and clearing release the entries and their caches.

| Complexity | Before | After |
|---|---:|---:|
| Estimate | O(n × string length + m log m), with repeated string normalization on every query | Same scan/sort complexity; normalize unchanged strings once per entry instead of per query |

### Changed files

- [Stores.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/Browser/Stores.mm:16) — Cache normalized URL/title matching inputs; invalidate on property replacement.
- [check-ui.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/scripts/check-ui.mm:120) — Extend the existing native check with history correctness, memory and browser-action measurements.
- [check-ui.py](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/scripts/check-ui.py:15) — Add isolated browser and fresh-process startup modes to the existing runner.

## Correctness checks

| Check | Status | Evidence |
|---|---|---|
| History behavior | ✅ passed | Compared against the original ranking oracle: Unicode, whitespace, misses, limits, URL/title replacement, mutable-string copying, nil values, visits/age, ties, record/update, pruning, persistence and clear. |
| Browser and startup checks | ✅ passed | Four Release browser trials, one Debug browser run, and 22 fresh startup processes passed their assertions. Tabs/spaces, local navigation, scrolling, resize, split view and command-bar handlers exercised. |
| Visual equivalence | ✅ passed | 82 original PNG pairs are byte-identical. Address-bar suggestion captures are identical across all four browser trials. |
| Motion behavior | ✅ passed | 24 simulated layout-morph scenarios per suite; existing motion, hover, accessibility and control checks retained. Live frame-rate comparison is inconclusive. |
| Builds and packaging | ✅ passed | Release and Debug build; codesign --verify --deep --strict and Info.plist checks pass for both. Final native harness compiles and the default UI suite passes. |
| Static analysis | ⚠️ warnings | Analysis completes with 40 pre-existing diagnostics, none in Stores.mm. No unrelated production fixes included. |
| Scope and syntax | ✅ passed | git diff --check and Python AST parsing pass. Earlier UI source changes are byte-for-byte unchanged by this pass. |

## Benchmark protocol

**Workload:** Apple M4 Pro, macOS 27.2, Release arm64. Real production object files. Two trials per variant in before/after then after/before order. Four warmups and 15 samples per process (30 per variant). One action per sample. The command bar cycles b/br/bro/brow/brows/browse/browser; input assignment is outside the timer, while its change handler, suggestion rebuilding and layout/display submission are inside. Network suggestions are disabled.  
**Command:** `python3 scripts/check-ui.py --browser --objects BEFORE_OBJECTS`  
**Warmups:** 4  
**Measured runs:** 30 per version

## Reproduce

```bash
python3 scripts/check-ui.py
```
```bash
python3 scripts/check-ui.py --browser
```
```bash
python3 scripts/check-ui.py --startup
```
```bash
python3 scripts/check-ui.py --browser --baseline --objects /path/to/baseline/Objects-normal/arm64 --output /tmp/brook-browser-before
```
```bash
python3 scripts/check-ui.py --browser --objects build/Build/Intermediates.noindex/Brook.build/Release/Brook.build/Objects-normal/arm64 --output /tmp/brook-browser-after
```
```bash
xcodebuild -project Brook.xcodeproj -scheme Brook -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- build analyze
```

## Limitations

- Timing ends at main-thread layout/display submission, not physical presentation, input dispatch or animation completion. Opening and closing a tab are one combined timed action.
- The synthetic workload uses 200 blank tabs across two spaces, deterministic history, local HTML and a nonpersistent WebKit store. Real websites, network suggestions, favicons, downloads, extensions, content blockers, password autofill and notifications are excluded.
- Fresh-process startup measures the real AppDelegate launch callbacks through first-window submission. It excludes OS process loading, initial NSApplication initialization, fixture construction, page loads and external service readiness. Nine measured processes per variant follow two warmup processes.
- Live frame-rate comparison is INCONCLUSIVE: only before-1 delivered 60 frame callbacks. After-1, after-2 and before-2 reported hidden visibility and timed out with zero callbacks. Simulated motion checks and identical captures do not prove live FPS or every possible interaction.
- The cache adds approximately 9 MB for 20,000 synthetic entries: 8,320,000 retained allocator bytes after first search plus 40 bytes of nominal object storage per entry. This is not an RSS measurement; allocation rounding and string lengths vary.
- The first history query and all other browser-action comparisons are INCONCLUSIVE. No browser-wide percentage improvement is claimed. Sidebar tab open-plus-close and space changes remain measurable costs.
- Xcode analysis succeeds with 40 existing diagnostics outside Stores.mm: 37 NSNumber presence checks and three nullability warnings. This is not a warning-free result.

## Residual risks

- HistoryEntry URL/title properties must retain their current copy semantics for identity-based invalidation. The existing store usage remains on the main thread.
- The retained cache scales with the number and length of history strings. Twenty thousand entries are a stress fixture; larger histories and longer text require proportionally more memory.

## Notes

- This pass changes only the approved history matching path in production. Existing UI optimizations are part of both baselines.
- Reconstruct the before source from the recorded HEAD plus browser_history.baseline.patch_from_head in the results JSON. Build Release objects in a separate checkout and use the current harness. Apply browser_history.optimization_patch for the after version. Use the same Release app resources for both startup runs.
- The WebKit checks require a desktop session and macOS service access; the restrictive execution sandbox could not provide that access. Successful browser/startup runs used approved unsandboxed execution.
- Each process excludes its own warmups. The fresh-process startup test instead uses two warmup processes and nine measured processes per variant.
- The runner cleans its temporary executable and captures unless --output is supplied. Saved evidence retains samples, source patches, hashes and diagnostics; temporary artifacts from this proof are removed after validation.

---

Generated by `$speedup-proof`. Runtime evidence and correctness checks determine the verdict.

## History measurements

One query per sample; 30 samples per variant. Cold queries use a fresh history store, with fixture creation excluded. All times are milliseconds.

| History entries / query | Before median | After median | After p95 | Verdict |
|---|---:|---:|---:|---|
| 1000 browser query | 1.767 | 0.380 | 0.406 | PROVEN |
| 1000 café query | 1.936 | 0.541 | 0.585 | PROVEN |
| 1000 no-match-zyx query | 1.969 | 0.580 | 0.592 | PROVEN |
| 1000 site000 query | 2.134 | 0.716 | 0.764 | PROVEN |
| 20000 browser query | 36.843 | 9.111 | 10.169 | PROVEN |
| 20000 café query | 40.617 | 12.795 | 14.554 | PROVEN |
| 20000 first query | 36.715 | 36.431 | 37.257 | INCONCLUSIVE |
| 20000 no-match-zyx query | 40.284 | 12.231 | 13.844 | PROVEN |
| 20000 site000 query | 44.241 | 15.930 | 17.608 | PROVEN |

The four warm 20,000-entry queries take 9.1–15.9 ms after the change; warm 1,000-entry queries take 0.38–0.72 ms. The first 20,000-entry search remains about 36 ms, with no proven change. The full address-bar handler also rebuilds and lays out suggestions, giving its separate 17.9 ms median.

## Browser-wide measurements

These are diagnostic timings for the unchanged paths. Every before/after comparison below is **INCONCLUSIVE**; none establishes a speedup or regression. Main-thread values end at layout/display submission. Tab open + close is a combined action, and transition setup excludes animation completion.

| Action / layout | Before median (ms) | After median (ms) | After p95 (ms) |
|---|---:|---:|---:|
| Restore 200 blank tabs in an already-running process | 0.425 | 0.429 | 0.495 |
| Local HTML load until title available and loading ends | 8.730 | 8.253 | 9.489 |
| Local page scroll JavaScript round trip | 0.235 | 0.331 | 0.776 |
| Window resize submission | 2.342 | 2.059 | 2.617 |
| Split divider resize submission | 0.975 | 0.847 | 2.047 |
| Layout transition setup | 13.718 | 13.751 | 37.460 |
| Fresh-process AppDelegate startup through window submission | 164.409 | 161.514 | 175.462 |
| Tab switch / sidebar | 2.332 | 2.106 | 7.137 |
| Tab open + close / sidebar | 52.286 | 51.380 | 55.773 |
| Space switch / sidebar | 25.903 | 25.217 | 27.190 |
| Tab-list scroll / sidebar | 5.710 | 5.408 | 6.002 |
| Tab switch / top | 5.444 | 3.628 | 7.751 |
| Tab open + close / top | 9.712 | 8.973 | 11.715 |
| Space switch / top | 41.498 | 40.900 | 42.067 |
| Tab-list scroll / top | 0.325 | 0.319 | 0.879 |
| Tab switch / compact | 5.950 | 3.559 | 10.219 |
| Tab open + close / compact | 12.003 | 10.251 | 11.807 |
| Space switch / compact | 43.799 | 41.762 | 51.973 |
| Tab-list scroll / compact | 0.340 | 0.340 | 0.579 |

Sidebar tab open + close remains about 51 ms; switching spaces takes about 25–42 ms with this 200-tab session. These are the clearest remaining measured UI costs. This history-only pass does not modify them. Startup has nine measured fresh processes per variant; the other rows have 30 samples per variant.

## Memory and live motion

Both optimized trials retained 8,320,000 additional allocator bytes after the first search; both baseline trials retained zero. HistoryEntry grew from 40 to 80 nominal bytes, adding approximately 0.8 MB across 20,000 entries before any search. Combined, this fixture costs roughly 9 MB extra, with allocator rounding and real string lengths affecting actual usage. These measurements are not whole-process RSS.

Only the first baseline frame observation completed: 60 intervals, median 17 ms, maximum 18 ms. Both optimized observations and the second baseline observation timed out with hidden page visibility and no callbacks. **Live frame-rate performance is unverified.** The 24 simulated motion scenarios and identical captures verify the exercised animation logic and static appearance, not compositor timing.

Raw samples, all 29 comparisons, source patches, image hashes and analyzer diagnostics are retained in [speedup-proof-results.json](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/outputs/speedup-proof-results.json), under `browser_history`. Earlier pass evidence is preserved below and in the JSON.

<details>
<summary>Earlier icon and UI optimization evidence</summary>

# Speedup Proof

## PROVEN — 93.92% less time in sidebar fallback refreshes

> Correctness passed and the lower after median exceeds the noise threshold.

**Project:** Brook  
**Target:** 1,000 sidebar-row refreshes with no favicon  
**Preserved behavior:** Identical icon size, tint, alpha, appearance, ordering, loading visibility and UI behavior. No design or animation changes.  
**Generated:** 2026-09-30

## Before vs after

| Measurement | Before | After |
|---|---:|---:|
| Median runtime | 58.503 ms | 3.554 ms |
| p95 runtime | 62.69 ms | 3.985 ms |
| Mean runtime | 58.606 ms | 3.608 ms |
| Range | 55.542–66.244 ms | 3.356–4.206 ms |
| Variability | 4.39% CV | 5.45% CV |
| Measured runs | 30 | 30 |

**Speedup ratio:** 16.46×  
**Proof threshold:** 10.91%  
**Correctness:** PASSED

## What changed

Reuse three native fallback symbol images and avoid assigning an identical image to the sidebar row, favorite tile and extension button.

**Why behavior remains equivalent:** Only immutable fallback symbols are retained. Every refresh still reads the current favicon or action/extension icon, and all tint, alpha, label, badge and loading updates remain in place. The extension button keeps its original initially-empty behavior. No rendering geometry, assets, animations or timing constants changed.

| Complexity | Before | After |
|---|---:|---:|
| Estimate | O(1) per refresh, repeated configured-symbol creation when missing an icon | O(1) per refresh, one configured fallback symbol retained per path |

### Changed files

- [SidebarCells.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/SidebarCells.mm:270) — Reuse the 13-point globe and skip identical image assignments.
- [SidebarParts.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/SidebarParts.mm:190) — Reuse the 16-point globe and skip identical image assignments.
- [ExtensionsBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/ExtensionsBar.mm:47) — Reuse the 13-point extension fallback while preserving the initial empty state.
- [check-ui.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/scripts/check-ui.mm:82) — Benchmark production refresh methods and check icon transitions, appearance and avoided factory calls.

## Correctness checks

| Check | Status | Evidence |
|---|---|---|
| Release and Debug builds | ✅ passed | Both build; native checks pass with Release and Debug objects. Signatures and plists validate; Release is arm64. |
| Visual comparison | ✅ passed | 82 PNG pairs are byte-identical in each of two trials: the prior 46 captures plus 36 icon-state captures across light/dark/high-contrast appearances. |
| Motion and controls | ✅ passed | 24 simulated morph scenarios per suite, plus existing hover, accessibility, loading, title/URL, resizing, fading and address-edit checks. |
| Fallback correctness | ✅ passed | Missing/present/removed icons; exact symbol size and TIFF data; image identity; tint and alpha; extension icon priority, label, badge, enabled state and initial empty state. |
| Avoided factory calls | ✅ passed | Each of three views: 100 calls before, zero after, for 100 repeated warmed fallback refreshes. Instrumentation runs outside timing. |
| Static analysis | ⚠️ warnings | Completed successfully with 40 diagnostics outside the three changed source files: 37 NSNumber presence checks and 3 nullability diagnostics. Their source lines are unchanged from HEAD; no warning-free claim. |
| Diff and runner syntax | ✅ passed | git diff --check and Python AST parsing pass. |

## Benchmark protocol

**Workload:** Apple M4 Pro, macOS 27.2, Release arm64; real production object files with isolated synthetic tab/extension inputs. Two process pairs in before/after then after/before order. Four warmups and 15 measured samples per process, 30 samples per variant. Each sample contains 1,000 calls. Setup, capture, factory instrumentation and autorelease-pool drain excluded.  
**Command:** `python3 scripts/check-ui.py --baseline --objects BEFORE_OBJECTS`  
**Warmups:** 4  
**Measured runs:** 30 per version

## All icon refresh workloads

Each sample contains 1,000 production refresh calls. Values are medians across 30 samples per variant. See [raw evidence and diagnostics](speedup-proof-results.json), under `icon_reuse`.

| View / input | Before (ms) | After (ms) | Reduction | Verdict |
|---|---:|---:|---:|---|
| Sidebar / fallback | 58.5033 | 3.5544 | 93.92% | PROVEN |
| Sidebar / transition | 33.4017 | 8.2575 | 75.28% | PROVEN |
| Sidebar / provided | 3.6483 | 3.4224 | Not proven | INCONCLUSIVE |
| Favorite / fallback | 48.8085 | 0.5969 | 98.78% | PROVEN |
| Favorite / transition | 27.9595 | 5.0502 | 81.94% | PROVEN |
| Favorite / provided | 0.6424 | 0.5951 | Not proven | INCONCLUSIVE |
| Extension / fallback | 55.3642 | 0.7288 | 98.68% | PROVEN |
| Extension / transition | 30.2239 | 6.0330 | 80.04% | PROVEN |
| Extension / provided | 0.6684 | 0.6103 | Not proven | INCONCLUSIVE |

The fallback case means the same missing icon on repeated refreshes; for extensions it starts after a real icon disappears. The transition case alternates absent/present icons. The provided case repeatedly supplies the same real image and is a regression control. All three controls are inconclusive, with no proven slowdown.

To reproduce the baseline, use the revision and `baseline.patch_from_head` recorded under `icon_reuse` in the results JSON in a separate checkout, then build Release objects there. Use the current check harness with those objects. Apply `optimization_patch` for the after version. The previously uncommitted optimizations are part of both versions.

## Reproduce

```bash
python3 scripts/check-ui.py
```
```bash
python3 scripts/check-ui.py --baseline --objects /path/to/baseline/Objects-normal/arm64 --output /tmp/brook-icon-before
```
```bash
python3 scripts/check-ui.py --objects build/Build/Intermediates.noindex/Brook.build/Release/Brook.build/Objects-normal/arm64 --output /tmp/brook-icon-after
```
```bash
xcodebuild -project Brook.xcodeproj -scheme Brook -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- build analyze
```

## Limitations

- No application-wide FPS, GPU, energy, memory-usage or live website performance claim.
- Offscreen views and synthetic motion clocks do not prove all live interactions or all monitor configurations.
- Extension metadata is supplied by deterministic fixture objects; real WebKit extension loading and network activity are excluded.
- Three provided-icon control benchmarks are inconclusive. No proven regression.
- Caches retain three immutable native symbol images for the process lifetime; real favicons and extension icons remain uncached by this change.
- Static analysis is not warning-free: 37 NSNumber presence checks and 3 nullability diagnostics in pre-existing code. No unrelated fixes were included.

## Residual risks

- The retained symbols must remain immutable; future code that changes their size or representation should copy them first.
- Existing unrelated analyzer diagnostics remain; this pass changes only the approved icon refresh paths.

## Notes

- This baseline includes the earlier UI optimizations. It is not the original HEAD baseline used in the previous report.
- The results JSON retains the baseline patch from HEAD, the exact icon-reuse patch, source hashes, raw samples, image hashes, factory counts and analyzer diagnostics.
- Percentages describe the named refresh batches only. Provided-icon controls did not exceed the noise threshold.
- The existing runner removes its temporary executable and captures by default. Temporary before/after artifacts from this proof run are removed after reporting.

---

Generated by `$speedup-proof`. Runtime evidence and correctness checks determine the verdict.

<details>
<summary>Earlier UI optimization evidence</summary>

# Speedup Proof

## PROVEN — 96.25% less time in the compact-tab refresh benchmark

> Correctness passed and the lower after median exceeds the noise threshold.

**Project:** Brook  
**Target:** 300 unchanged compact-tab refresh/layout passes with 200 synthetic tabs  
**Preserved behavior:** Same dimensions, spacing, typography, imagery, effects, interactions, and animation timings.  
**Generated:** 2026-09-30

## Before vs after

| Measurement | Before | After |
|---|---:|---:|
| Median runtime | 26.863 ms | 1.007 ms |
| p95 runtime | 29.063 ms | 1.089 ms |
| Mean runtime | 26.847 ms | 1.034 ms |
| Range | 25.422–29.846 ms | 0.963–1.647 ms |
| Variability | 3.86% CV | 11.31% CV |
| Measured runs | 30 | 30 |

**Speedup ratio:** 26.683×  
**Proof threshold:** 22.62%  
**Correctness:** PASSED

## What changed

Avoided whole-strip layout when refreshing a compact tab without changing its preferred width. Address editing still requests layout. Related changes skip redundant symbol generation, hover redraws, tracking-area allocation, and fade-mask updates; tab notifications refresh only the UI that reads those fields.

**Why behavior remains equivalent:** Existing drawing and animation code is retained. Each fast path checks its inputs: symbol name, size and current image identity; fade edges, width, mask identity and bounds; compact address width and editing state. Real title, URL, loading, navigation and loaded-state changes still refresh their controls. Page progress rendering remains in ContentAreaView.

| Complexity | Before | After |
|---|---:|---:|
| Estimate | O(number of tabs) for each compact refresh layout | O(1) when preferred width stays unchanged |

### Changed files

- [TopBar.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/TopBar.mm:743) — Conditional compact layout, reusable edge fades and targeted toolbar updates.
- [Controls.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/Controls.mm:28) — Skip unchanged control state and symbols; reuse native tracking.
- [SidebarView.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/SidebarView.mm:598) — Route tab changes only to affected rows and toolbar fields.
- [SidebarCells.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/SidebarCells.mm:1) — Reuse the existing automatically resized tracking area.
- [BrowserWindowController.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/BrowserWindowController.mm:1) — Reuse the existing automatically resized tracking area.
- [ContentAreaView.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/ContentAreaView.mm:1) — Reuse the existing automatically resized tracking area.
- [HiddenElements.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/Sources/UI/HiddenElements.mm:1) — Reuse the existing automatically resized tracking area.
- [check-ui.py](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/scripts/check-ui.py:1) — Runnable check; temporary binary and captures removed by default.
- [check-ui.mm](/Users/xxxxxxxxxx/Documents/Coding/Brook/brook/scripts/check-ui.mm:1) — Checks real production views with isolated synthetic data.

## Correctness checks

| Check | Status | Evidence |
|---|---|---|
| Release and Debug builds | ✅ passed | Both compile and link. Existing WKProcessPool deprecations and selector warnings remain. |
| Visual equivalence | ✅ passed | 46 PNG pairs are byte-identical in each of two runs: light/dark/high contrast, tab styles, UI fonts and close-button settings. |
| Morph behavior | ✅ passed | 24 combinations: all six directions between sidebar/top/compact, normal and Reduce Motion, simulated 60/120 Hz. Single snapshot/completion, monotonic progress, final frame and cleanup verified. |
| Controls and refreshes | ✅ passed | Symbols, hover, resizing, accessibility actions, title/URL/loading updates, scrolling fade edges, mask reattachment after resize, and address-editing relayout. |

## Benchmark protocol

**Workload:** Apple M4 Pro, macOS 27.2, Release arm64. Real production object files linked to one native fixture with 200 synthetic tabs. Two process pairs, order before/after then after/before, four warmups and 15 samples per process (30 per variant). Setup and capture excluded.  
**Command:** `python3 scripts/check-ui.py --baseline --objects BASELINE_OBJECTS`  
**Warmups:** 4 per process  
**Measured runs:** 30 per version

## Reproduce

```bash
python3 scripts/check-ui.py
```
```bash
python3 scripts/check-ui.py --output /tmp/brook-ui-after
```
```bash
python3 scripts/check-ui.py --baseline --objects /path/to/baseline/build/Build/Intermediates.noindex/Brook.build/Release/Brook.build/Objects-normal/arm64 --output /tmp/brook-ui-before
```

## Limitations

- No whole-application FPS, GPU, WindowServer, energy, or end-to-end website performance claim.
- Sidebar progress timing is inconclusive because the optimized callback is too short for stable relative timing.
- Changing-symbol benchmark shows no proven speedup or slowdown.
- Offscreen AppKit capture and synthetic timelines cannot establish perfect behavior on every website, monitor, or live interaction. Extension managers and network stores are disabled in the fixture.

## Residual risks

- Future tab-change flags must be included when toolbar or row content begins depending on them.
- No changes to ChromeMorph, graphics assets, blur, shadows, opacity values, spring constants, durations or display-link cadence.

## Notes

- Build baseline commit 550abacceb5f87026838b09b57a7b05a0610980f in a separate checkout before using --objects. The current test harness checks both revisions.
- Timing percentages refer only to the named workloads, not whole-app responsiveness.
- The offscreen editing-field check verifies strip invalidation, then invokes the production tab layout explicitly; AppKit skips that child layout in the unshown fixture on both revisions.

---

Generated by `$speedup-proof`. Runtime evidence and correctness checks determine the verdict.

## All measured workloads

Each value is the median duration of the entire named batch. Raw samples, variability, comparisons, and capture hashes are in [the results JSON](speedup-proof-results.json).

| Workload | Before (ms) | After (ms) | Verdict |
|---|---:|---:|---|
| 300 compact refresh/layout passes | 26.8628 | 1.0067 | PROVEN |
| 10,000 unchanged edge fades | 11.3575 | 0.4145 | PROVEN |
| 1,000 unchanged hover-state/display passes | 2.2806 | 1.8486 | PROVEN |
| 1,000 sidebar progress notifications | 272.9566 | 0.0073 | INCONCLUSIVE |
| 1,000 changing symbols (regression control) | 50.4174 | 47.7397 | INCONCLUSIVE |
| 10,000 unchanged symbols | 458.4435 | 0.7130 | PROVEN |
| 1,000 top-bar progress notifications | 150.2653 | 0.0051 | PROVEN |
| 10,000 tracking-area updates | 3.8438 | 0.8152 | PROVEN |

The sidebar callback now does no UI work for progress-only notifications. Its new runtime is too short for stable relative timing, so its measured percentage is not treated as proven. The changing-symbol control did not exceed the noise threshold; no speedup is claimed for that workload.

Tracking areas retain `NSTrackingInVisibleRect`, which follows visible bounds automatically. [Apple documentation](https://developer.apple.com/documentation/appkit/nstrackingareaoptions/nstrackinginvisiblerect).

</details>

</details>

</details>
