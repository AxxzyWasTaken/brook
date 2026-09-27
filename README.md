# Drift

A fast, native macOS 26 browser: AppKit + WebKit, an Arc-style sidebar with Liquid Glass,
DuckDuckGo's cookie-popup auto-reject and Fire button, and Chrome extension support.

## Get the app
Every push to `main` is built by GitHub Actions on a Mac. Download `Drift.zip` from the
**latest** release (or the run's artifact), unzip, move `Drift.app` to Applications, then run once:

    xattr -dr com.apple.quarantine /Applications/Drift.app

(The build is signed ad-hoc, not notarized, so macOS needs that the first time.)

## Build locally
    brew install xcodegen && xcodegen generate && open Drift.xcodeproj

## Shortcuts
| | |
|---|---|
| ⌘T / ⌘L | Command bar (new tab / edit address) |
| ⌘S | Hide / show sidebar (hover the left edge to peek) |
| ⌘D / ⇧⌘D | Pin tab / add to favorites |
| ⌘W / ⇧⌘T | Close tab / reopen closed tab |
| ⌘1–9, ⌃Tab | Switch tabs |
| ⌃1–9, ⌥⌘← → , two-finger swipe on sidebar | Switch spaces |
| ⇧⌘C | Copy link |
| ⌘F | Find in page |
| ⇧⌘⌫ | Fire: burn tabs & browsing data |

## Extensions
Uses WebKit's `WKWebExtension` API (as DuckDuckGo's browser does). Install from the puzzle
button in the address pill: paste a Chrome Web Store link, or browse the store and click
**Add to Drift**. Manifest V3 extensions work best; APIs Safari doesn't support
(e.g. blocking `webRequest`) won't work.

## Credits
- Cookie-popup handling uses DuckDuckGo's [autoconsent](https://github.com/duckduckgo/autoconsent)
  (MPL-2.0, see `Resources/autoconsent-LICENSE.txt`) and rules from DuckDuckGo's public privacy config.
- Extension and autoconsent integration modelled on
  [duckduckgo/apple-browsers](https://github.com/duckduckgo/apple-browsers) (Apache-2.0).
- Favicons from DuckDuckGo's icon service. Not affiliated with DuckDuckGo or The Browser Company.
