# macOS integration verification

Verified on October 23, 2026 in a graphical macOS session with Google Chrome 155, Safari, and Helium installed. The tests used a temporary Ouvre Debug app with a distinct bundle ID and a temporary Chrome `--user-data-dir`. They did not change the system default browser or read/write the user's normal Chrome profiles. The HTTP and HTTPS default handler was OpenIn before and after testing.

| Path | Evidence | Result |
| --- | --- | --- |
| Cold Ouvre and cold isolated Chrome | LaunchServices `open -a` sent `https://example.com/ouvre-e2e-cold?marker=cold-A#fragment-A`; Ouvre traced receipt, rule to `com.google.Chrome|Default`, and launch. Chrome DevTools listed the exact URL. The temporary `Default/History` contained it. | Pass |
| Already-running isolated Chrome | A second `open -a` sent `https://example.com/ouvre-e2e-running?marker=running-B#fragment-B`. DevTools listed both exact URLs and temporary `Default/History` contained both. | Pass |
| Profile switch | After changing only the temporary config, `https://example.com/ouvre-e2e-second?marker=second-C#fragment-C` routed to `com.google.Chrome|Profile 1`. DevTools listed it; temporary `Profile 1/History` contained it and `Default/History` did not. | Pass |
| Generic app adapter | `BrowserLauncher.open` delivered `https://example.com/ouvre-e2e-generic?marker=generic-D#fragment-D` to a disposable URL-logging app through `NSWorkspace`. Its log contained the exact URL. | Pass for generic adapter fixture |
| Picker and queue | An unmatched OS-delivered URL caused an on-screen `Open with Ouvre` window. Two more unmatched URLs were received in order; only the first was processed until a Debug-only `dismiss` command, after which the second was processed. | Pass for OS input and queue transition |
| Missing saved profile | A rule targeting `com.google.Chrome|Missing` reported “This browser profile is no longer available,” left the picker visible, and Chrome had no target for that marked URL. | Pass |
| Early browser exit | A disposable fake browser executable exited with status 42; `BrowserLauncher.open` threw `launchFailed(42)`. | Pass |

The generic fixture proves the launch adapter, not Safari or Helium behavior. Those apps were not opened in this first pass because doing so would write to the user's real browser profiles. Later isolated Helium and native UI verification appears below. System-wide Accessibility trust was unavailable; the later isolated UI harness covers controls without requiring it. `Process.run` plus a short exit check cannot prove every browser version will render a page; the Chrome DevTools and profile-history checks above establish URL and profile delivery for this installed Chrome version.

## Reproduce in an opted-in graphical session

These steps create only temporary artifacts. Run from the repository root. Use Xcode's developer directory for this machine without changing `xcode-select`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
verify_root=$(mktemp -d /tmp/ouvre-e2e.XXXXXX)
xcodebuild -project Ouvre.xcodeproj -scheme Ouvre -configuration Debug -derivedDataPath "$verify_root/DerivedData" -arch arm64 CODE_SIGNING_ALLOWED=NO build
swiftc -parse-as-library Sources/OuvreCore/*.swift scripts/verification/Prepare.swift -o "$verify_root/prepare"
"$verify_root/prepare" "$verify_root"
ditto "$verify_root/DerivedData/Build/Products/Debug/Ouvre.app" "$verify_root/Ouvre Integration.app"
plutil -replace CFBundleIdentifier -string com.matthewholandez.Ouvre.Integration "$verify_root/Ouvre Integration.app/Contents/Info.plist"
plutil -insert LSEnvironment -json "{\"OUVRE_TEST_CONFIG\":\"$verify_root/config.json\",\"OUVRE_TEST_CHROME_ROOT\":\"$verify_root/Chrome\",\"OUVRE_TEST_TRACE\":\"$verify_root/trace.log\"}" "$verify_root/Ouvre Integration.app/Contents/Info.plist"
codesign --force --deep --sign - "$verify_root/Ouvre Integration.app"
open -a "$verify_root/Ouvre Integration.app" 'https://example.com/ouvre-e2e-cold?marker=cold-A#fragment-A'
```

Wait for `Chrome/DevToolsActivePort`, then inspect the trace, DevTools pages, and the disposable profile history:

```sh
cat "$verify_root/trace.log"
port=$(head -n 1 "$verify_root/Chrome/DevToolsActivePort")
curl --noproxy '*' --silent "http://127.0.0.1:$port/json/list" | python3 -c 'import json,sys; [print(t.get("url")) for t in json.load(sys.stdin) if t.get("type")=="page"]'
python3 - "$verify_root/Chrome/Default/History" <<'PY'
import sqlite3, sys
db = sqlite3.connect('file:' + sys.argv[1] + '?mode=ro&nolock=1', uri=True)
print(list(db.execute("select url from urls where url like '%ouvre-e2e%'")))
PY
```

Send another marked URL with `open -a "$verify_root/Ouvre Integration.app" 'https://example.com/ouvre-e2e-running?marker=running-B#fragment-B'` and repeat the inspection. To test the second profile, inspect `pgrep -fl 'Ouvre Integration.app/Contents/MacOS/Ouvre'`, terminate **only that test clone's PID**, run `"$verify_root/prepare" "$verify_root" second`, then reopen the clone with the `second-C` URL above. Query both temporary `Default/History` and `Profile 1/History` with the same read-only Python command.

For the picker queue, send two unmatched URLs using `open -a` (for example `https://example.org/ouvre-e2e-queue?marker=queue-F` and `https://example.net/ouvre-e2e-queue?marker=queue-G`). Inspect the trace: both `receive` entries should appear, but only F should have `process` and `picker`. Write `dismiss` to `$verify_root/command.txt`; this Debug-only command closes the current picker. The trace should then show `dismiss F`, `process G`, and `picker G`. This command hook is compiled out of Release builds.

For a missing target, terminate only the test clone, run `"$verify_root/prepare" "$verify_root" missing`, and reopen it with `https://example.com/ouvre-e2e-missing?marker=missing-H#fragment-H`. The trace should show the failure and the picker should remain visible; the Chrome DevTools target list should contain no `missing-H` URL.

To test the generic adapter without touching another browser profile:

```sh
fixture="$verify_root/URL Logger.app"
mkdir -p "$fixture/Contents/MacOS"
swiftc scripts/verification/URLLogger.swift -o "$fixture/Contents/MacOS/URLLogger"
cp scripts/verification/URLLoggerInfo.plist "$fixture/Contents/Info.plist"
plutil -replace VerificationLogPath -string "$verify_root/fixture.log" "$fixture/Contents/Info.plist"
codesign --force --deep --sign - "$fixture"
swiftc -parse-as-library Sources/OuvreCore/*.swift Sources/OuvreApp/VerificationHooks.swift Sources/OuvreApp/ProfileAccessStore.swift Sources/OuvreApp/BrowserCatalog.swift scripts/verification/LaunchFixture.swift -o "$verify_root/launch-fixture"
"$verify_root/launch-fixture" "$fixture" 'https://example.com/ouvre-e2e-generic?marker=generic-D#fragment-D'
cat "$verify_root/fixture.log"
```

The early nonzero-exit branch can be exercised with an executable that exits 42, using only the disposable Chrome root:

```sh
fake_app="$verify_root/Failing Chrome.app"
mkdir -p "$fake_app/Contents/MacOS"
printf '#!/bin/sh\nexit 42\n' > "$fake_app/Contents/MacOS/FailBrowser"
chmod +x "$fake_app/Contents/MacOS/FailBrowser"
cp scripts/verification/FailingBrowserInfo.plist "$fake_app/Contents/Info.plist"
swiftc -D DEBUG -parse-as-library Sources/OuvreCore/*.swift Sources/OuvreApp/VerificationHooks.swift Sources/OuvreApp/ProfileAccessStore.swift Sources/OuvreApp/BrowserCatalog.swift scripts/verification/EarlyExit.swift -o "$verify_root/early-exit"
OUVRE_TEST_CONFIG="$verify_root/config.json" OUVRE_TEST_CHROME_ROOT="$verify_root/Chrome" OUVRE_TEST_TRACE="$verify_root/trace.log" "$verify_root/early-exit" "$fake_app"
```

The harness prints `Caught early browser exit status 42` only if `BrowserLauncher.open` throws the expected error.

## Profile discovery follow-up

The isolated Chrome routing test above did not exercise macOS access to the user's normal Chrome `Local State`. A separately identified Debug Ouvre app, launched through LaunchServices in the graphical session, scanned the installed browsers. It discovered two Helium profiles. Its read of Chrome's `Local State` failed with `NSCocoaErrorDomain/257` (permission denied), although a terminal process could read the same file. The previous generic Chrome row therefore came from an unreported app-data access failure; the previous generic Helium row came from missing Helium profile support. The updated Browsers settings reports access failures and offers a per-browser folder chooser. Actual Chrome permission recovery still requires the user to choose the Chrome folder in that native panel.

The read-only bookmark creation, resolution, and scan path was exercised inside a separately signed Ouvre GUI bundle against a disposable one-profile folder; it returned one profile. This checks the app-bundle API path, but a disposable folder does not simulate macOS consent for protected Chrome data. Installed Helium was also launched with a disposable `--user-data-dir` and `--profile-directory=Profile 1`; only the temporary `Profile 1/History` contained the exact marked URL, including its query and fragment. No normal browser profile was launched or modified. The temporary app and browser processes were stopped and their folders removed. HTTP and HTTPS handlers remained OpenIn.

## Full-flow audit after native UI update

A fresh Debug Ouvre clone with a separate bundle ID, temporary configuration, and disposable Chrome and Helium data roots received marked links through LaunchServices. Installed browser metadata contained one valid Chrome profile and two Helium profiles. The GUI app found both Helium profiles; without a folder grant, its read of the real Chrome metadata still returned `NSCocoaErrorDomain/257`. This confirms the Chrome permission prompt remains a user action, not an automated test pass.

| Path | Observed result |
| --- | --- |
| Chrome cold and running | Exact query-and-fragment URLs arrived through Ouvre in temporary `Default/History` and DevTools, both on cold launch and while Chrome was already running. |
| Chrome profile switch | After restarting only the test Ouvre/Chrome processes, a new URL appeared in temporary `Profile 1/History` and not `Default/History`. |
| Ordered rules, hidden destination, fallback | An explicit picker rule beat a later destination rule and fallback. Disabling it let the next rule route. A hidden Profile 1 destination still worked as the configured fallback. |
| Queue and failure recovery | Three picker links were received in order; dismissing each exposed only the next one. A missing-profile rule reported failure and opened no browser URL. |
| Installed Helium through Ouvre | Ouvre routed a marked URL to `net.imput.helium|Profile 1` using a disposable Helium data root. Helium DevTools and only temporary `Profile 1/History` contained the exact URL, query, and fragment. |
| Native status menu | The Debug clone activated the actual NSMenu items for Pause, Try the picker, Settings, and Refresh. State, menu titles, picker visibility, settings-window visibility, and browser rescan matched the actions. The paused header was corrected to show paused state even before default-browser setup. |

The isolated SwiftUI/AppKit interaction harness additionally verified picker arrows, search, mouse selection, long-list navigation, Return, Escape, busy/no-match behavior, settings sidebar, pause, profile visibility, fallback picker, rule enable/reorder, deletion cancel/confirm, and editor add/edit. An editor issue found here was fixed: Return in the rule value field now saves a valid rule once; invalid Return keeps the sheet open. The harness does not prove VoiceOver narration, window-compositor glass rendering, native default-browser consent, or the protected Chrome folder grant. No system default handler or normal browser profile was changed.

After testing, terminate only the processes whose command lines contain this exact temporary root, unregister the temporary app bundles with Launch Services if needed, and remove `$verify_root`. Do not terminate any normal Chrome, Safari, Helium, OpenIn, or Ouvre process.
