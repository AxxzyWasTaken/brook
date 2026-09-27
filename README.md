# Brook

A fast, native macOS 26 browser: AppKit + WebKit, an Arc-style sidebar with Liquid Glass,
DuckDuckGo's cookie-popup auto-reject and Fire button, and Chrome extension support.

## Get the app
Every push to `main` is built by GitHub Actions on a Mac. Download `Brook.zip` from the
**latest** release (or the run's artifact), unzip, move `Brook.app` to Applications, then run once:

    xattr -dr com.apple.quarantine /Applications/Brook.app

(The build is signed ad-hoc, not notarized, so macOS needs that the first time.)

## Build locally
    brew install xcodegen && xcodegen generate && open Brook.xcodeproj

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
| ⌘, | Settings |
| ⌘P / ⌘. | Print / stop loading |
| ⇧⌘⌫ | Fire: burn tabs & browsing data |

Any menu shortcut can be remapped in System Settings → Keyboard → Keyboard Shortcuts →
App Shortcuts (add one for Brook with the exact menu item title).

## Customising
Everything is in **Settings (⌘,)** and applies instantly:
- **Appearance**: light/dark/system, sidebar left or right, floating card or edge-to-edge page
  (margin and corner radius), space tint strength, tab density and text size, which sidebar
  parts show, favorites columns.
- **Tabs**: where new tabs open, what a new tab shows (command bar, blank page, or a URL),
  what ⌘W does on pinned tabs, auto-archiving idle tabs (restore from the archive), unloading
  background tabs, which space links from other apps open in.
- **Search**: add any engine with a `%s` URL template and a keyword. Type `w cats` in the
  command bar to search that engine. Each space can have its own default engine.
- **Websites**: default zoom, JavaScript and autoplay, plus per-site overrides. Click the lock in
  the address pill for this site's settings.
- **Boosts**: your own CSS and JavaScript for the sites you choose (or every site), like Arc's.
- **Spaces**: any colour, and optionally a **separate profile** so the space keeps its own
  cookies and logins.
- **Advanced**: download folder, export/import all settings as a file, reset.

## Extensions
Uses WebKit's `WKWebExtension` API (as DuckDuckGo's browser does). Install from the puzzle
button in the address pill: paste a Chrome Web Store link, or browse the store and click
**Add to Brook**. Manifest V3 extensions work best; APIs Safari doesn't support
(e.g. blocking `webRequest`) won't work.

## Credits
- Cookie-popup handling uses DuckDuckGo's [autoconsent](https://github.com/duckduckgo/autoconsent)
  (MPL-2.0, see `Resources/autoconsent-LICENSE.txt`) and rules from DuckDuckGo's public privacy config.
- Extension and autoconsent integration modelled on
  [duckduckgo/apple-browsers](https://github.com/duckduckgo/apple-browsers) (Apache-2.0).
- Favicons from DuckDuckGo's icon service. Not affiliated with DuckDuckGo or The Browser Company.
