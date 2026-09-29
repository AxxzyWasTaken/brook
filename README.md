# Brook

A fast, native macOS 26 browser: AppKit + WebKit, an Arc-style sidebar with Liquid Glass,
DuckDuckGo's cookie-popup auto-reject and Fire button, and Chrome extension support.
Apple silicon only.

## Get the app
Every push to `main` is built by GitHub Actions on a Mac. Download `Brook.zip` from the
**latest** release (or the run's artifact), unzip, move `Brook.app` to Applications, then run once:

    xattr -dr com.apple.quarantine /Applications/Brook.app

(The build uses a stable self-signed certificate and is not notarized, so macOS needs that the first time.)

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
- **Passwords**: import CSV exports or selected Chromium browser profiles, search and manage saved
  logins, and unlock with Touch ID or your login password to reveal or copy them.
- **Boosts**: your own CSS and JavaScript for the sites you choose (or every site), like Arc's.
- **Spaces**: any colour, and optionally a **separate profile** so the space keeps its own
  cookies and logins.
- **Advanced**: download folder, export/import all settings as a file, reset.

## Passwords

Open **Settings → Passwords → Import…**, **File → Import Passwords…**, or type
`import passwords` in the command bar. Empty pages offer an import button while no logins are saved.

Choose a detected Chromium browser, select profiles, and approve macOS's data/keychain prompts.
Brook reads a private SQLite snapshot, including passwords in the signed-in account database.
Unsupported encryption formats use the CSV path instead. CSV imports support Chrome, Safari,
Apple Passwords, Firefox/Zen, Orion, 1Password, Bitwarden and compatible exports.

Duplicates match the website origin and username. Identical or older passwords stay unchanged;
only a known newer modification time replaces a saved password. Conflicting passwords without
that information are skipped, so keep the CSV and use **Edit…** if you want to replace one.
The import summary separates duplicate rows from already saved logins. After a complete, successful
CSV import, Brook offers to move the readable source file to the Bin; keeping it is the default.

Click a username or current-password field on a standard login form, then choose a login in Brook's
native popover. Autofill works only in the main frame on the saved login's exact scheme, host and
port. It does not fill automatically on load. After a user-edited form is submitted to the same
origin, Brook offers **Save Password**, **Update Password**, **Not Now**, or **Never for This Website**.
Forms with multiple password fields, passkeys and direct Firefox vault reading are not supported;
Firefox and Zen can use CSV import.

Passwords are sealed with a Secure Enclave key in
`~/Library/Application Support/Brook/passwords.json`. Site names and usernames are readable;
passwords require Touch ID or the Mac's login password. The vault locks after five idle minutes,
on screen lock, sleep and switching away from the macOS session. Passwords copied in Settings
stay on this Mac's clipboard and clear after 30 seconds unless another copy replaces them.
This vault is tied to this Mac; it is not a portable password backup.

## Extensions
Uses WebKit's `WKWebExtension` API (as DuckDuckGo's browser does). Install from the puzzle
button in the address pill: paste a Chrome Web Store link, or browse the store and click
**Add to Brook**. Manifest V3 extensions work best; APIs Safari doesn't support
(e.g. blocking `webRequest`) won't work.

## Credits
- Ad and tracker blocking uses [AdGuard's filter lists](https://github.com/AdguardTeam/AdguardFilters)
  (Base and Tracking Protection), converted at build time by AdGuard's
  [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) (`scripts/blocklist.sh`).
- Cookie-popup handling uses DuckDuckGo's [autoconsent](https://github.com/duckduckgo/autoconsent)
  (MPL-2.0, see `Resources/autoconsent-LICENSE.txt`) and rules from DuckDuckGo's public privacy config.
- Extension and autoconsent integration modelled on
  [duckduckgo/apple-browsers](https://github.com/duckduckgo/apple-browsers) (Apache-2.0).
- Favicons from DuckDuckGo's icon service. Not affiliated with DuckDuckGo or The Browser Company.
