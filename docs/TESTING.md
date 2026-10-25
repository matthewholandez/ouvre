# Verification checklist

Automated core tests and an Xcode build are required before a release. Use the
commands in the README. The checks below require a graphical macOS session and
installed browsers; a successful build alone does not prove them.

## Link delivery

- Launch the app normally: the menu-bar item and settings are reachable.
- Send an HTTP(S) URL explicitly to Ouvre with `open -a /path/to/Ouvre.app URL`.
  The URL must reach the picker without changing the system default browser.
- Repeat after quitting Ouvre to cover cold launch.
- Send several URLs quickly. Each should be handled once, in arrival order.
- Cancel the current picker. Only that URL should be discarded.
- Double-click a destination or press Return repeatedly. Only one launch should
  occur for the current URL; queued URLs must not be lost.

## Destinations

- A detected Chromium profile's displayed name matches its browser name.
- Choose a profile while its browser is already running. Verify the destination
  profile in the browser, not just the success of spawning a process.
- Repeat from a closed browser in a disposable test account; do not close someone
  else's active browser session for testing.
- Rename/remove a disposable profile, refresh, and check both picker and rules.
  A stale rule must explain the missing target and show the picker.
- Browser routers such as Ouvre and OpenIn must not appear as destinations.
- Hidden destinations must remain available as explicit rule targets if supported,
  but must not appear as picker choices. Hiding all choices needs a recovery path.

## Rules and configuration

- Put a picker rule before a destination rule for the same host. The picker wins.
- Disable the first rule. The next matching rule wins.
- Check `example.com`, `sub.example.com`, `notexample.com`, and
  `example.com.evil.test` against both domain match modes.
- Check URL prefixes against different schemes and ports and against similar
  hostname prefixes. Verify documented path/query/fragment semantics.
- Configure a fallback and confirm that an explicit picker rule overrides it.
- Restart the app and confirm configuration persists.
- In a disposable configuration, use invalid JSON or a future schema version.
  The app should show an error and preserve the original file.

## Picker and accessibility

- Search, arrow-key navigation, Return, and Escape work without a mouse.
- Verify 1–9 opens the numbered visible destination with empty search; ⌘1–9
  opens the numbered filtered result. Digits typed into a nonempty search remain
  text. Hidden destinations do not count, and only the first nine results have badges.
- Check unavailable numbers leave empty search unchanged, shortcuts with no matches
  or during launch do nothing, and Shift/Option/Control combinations do not open a
  destination. Holding a shortcut must not open another queued link.
- Run `scripts/ui/capture.sh /tmp/ouvre-ui-review --interactions-only` for native
  keyboard interaction assertions and `numbered-bare.png` / `numbered-filtered.png`
  proof. Preview fixtures record destination choices without launching browsers.
- Test an empty result set and a destination list longer than the panel.
- Confirm the full URL is inspectable/copyable without fetching its contents.
- Check light/dark appearance, VoiceOver labels, and a second display.
- Confirm a launch failure leaves the URL available to retry or copy.

## Default-browser onboarding

This is a manual, explicit user action. Do not change the default browser as part
of automated tests. When testing in a disposable account, verify both HTTP and
HTTPS associations, denied consent, partial failure, and restoration through
System Settings before removing Ouvre.
