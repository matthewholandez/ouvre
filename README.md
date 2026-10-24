# Ouvre

Ouvre is a local macOS link router. It receives `http` and `https` links, applies ordered rules, and opens the selected browser or Chromium profile. When no rule matches, a keyboard-driven picker asks where to open the link.

## Build and run

Requires macOS 14 or later and Xcode. Open `Ouvre.xcodeproj` and run the shared **Ouvre** scheme, or build a local app:

```sh
./scripts/build-app.sh
open dist/Ouvre.app
```

The script produces an ad hoc signed `dist/Ouvre.app`. The app lives in the menu bar. Open **Settings…** to inspect browsers, show or hide picker destinations, add rules, and test a URL. Choose **Make default** in General only when you want macOS to send web links to Ouvre. Merely building or launching the app does not change the default browser.

Run core tests with `swift test`. The [integration verification](docs/VERIFICATION.md) records tested link and profile delivery with a disposable Chrome data directory; the [manual test checklist](docs/TESTING.md) covers the remaining UI and browser checks.

## Rules and destinations

Rules are evaluated top to bottom. The first enabled match wins. A rule can match an exact domain, a domain and its subdomains, or a full `http`/`https` URL prefix. URL prefixes require the same scheme, host, and port. A prefix containing a query requires the same path and a matching query prefix; URL fragments and credentials are not accepted in rule prefixes. The fallback is the picker unless you choose a destination.

Ouvre reads profile names from Chromium `Local State` metadata for Chrome, Helium, Edge, Brave, and Chromium. It validates the corresponding profile directory before launching the browser with a profile argument. Safari, Firefox, and other browsers open as whole apps. Discovery includes known browser bundle IDs and installed HTTP(S) handlers that also declare HTML document support; some unusual browsers may not advertise that metadata. Profile support for other browsers is not implied. If a saved destination disappears, Ouvre shows the picker and an error instead of silently opening another profile.

macOS may block an app from reading another browser's profile metadata. If **Settings → Browsers** shows “macOS denied access” under Chrome, click **Choose profile folder…**, select `~/Library/Application Support/Google/Chrome`, then click **Use Folder**. For Helium, select `~/Library/Application Support/net.imput.helium` if prompted. Ouvre requests access to that browser's folder, reads its profile names, and saves a read-only folder bookmark for later launches. “Whole browser” remains available when profiles cannot be read.

Profile launching starts the browser executable with a URL argument, including its query and fragment. Ouvre can confirm that the process started but cannot confirm that the browser rendered the page. Behavior with every browser version and already-running browser instance requires the manual checks above.

## Privacy and configuration

Ouvre reads browser installation paths and Chromium profile metadata locally. It does not edit browser data, fetch link previews, send telemetry, or keep browsing history. Settings are stored at `~/Library/Application Support/Ouvre/config.json` with atomic writes. If the file is unreadable or from an unsupported version, Ouvre reports the error and prevents settings changes until the file is repaired or moved.

The app has no third-party runtime dependencies. The routing core is also a Swift package for tests.
