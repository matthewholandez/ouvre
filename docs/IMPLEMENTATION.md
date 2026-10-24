# Ouvre: first working build

Ouvre is a native, local-only macOS link router. It receives external HTTP(S)
links as the user's chosen default browser, evaluates ordered rules, and opens
an explicit browser/profile or presents a picker. It does not intercept normal
navigation inside a browser or links an application explicitly sends elsewhere.

## Implementation sequence

1. **Foundation** — macOS 14+ application, shared Xcode scheme, menu-bar lifecycle,
   HTTP(S) registration, incoming-link queue, versioned local configuration.
2. **Destinations** — discover installed browsers; read Chromium profile metadata;
   preserve stable destination identities; launch explicit applications/profiles.
3. **Picker** — native panel, icons and profile names, search, keyboard navigation,
   cancellation, and queued incoming links.
4. **Rules** — ordered first-match rules for exact domains, domains with subdomains,
   and URL prefixes; destination/picker actions; settings editor and URL tester.
5. **Verification** — core unit tests, Xcode build, local runtime smoke check,
   compatibility notes, build instructions, and CI.

## First-build scope

- Chrome, Edge, Brave, and Chromium profile adapters, with per-browser runtime
  compatibility reported honestly rather than inferred from a shared engine.
- Safari, Firefox, and other discovered browsers as generic destinations.
- Settings for default-browser onboarding, visible destinations, ordered rules,
  and fallback behavior.
- No accounts, analytics, browsing history, page previews, extensions, URL
  rewriting, executable user scripts, source-app rules, or Safari profile automation.
- No automatic changes to the user's system default browser during development.

## Required behavior

- An unavailable saved destination prompts for another destination; it never
  silently substitutes a different profile.
- Profile metadata is read-only. Credentials, cookies, and browsing history are
  neither needed nor collected.
- Browser arguments are passed as an array, never interpolated into a shell.
- HTTP(S) URLs retain their query, fragment, and encoding when forwarded.
- Rules match hostname boundaries, not arbitrary substrings. Prefix rules must
  not match a different origin that happens to share a textual prefix.
- Explicit picker rules stop rule evaluation, even when a fallback is configured.
- Multiple incoming links remain queued while a picker or launch is in progress.
- Selecting a destination never invokes the system default browser indirectly.
- Configuration errors are visible and do not silently destroy existing data.
- Profile discovery and launch failures remain recoverable in the UI.

## Verification gates

Automated tests cover domain boundaries, case normalization, rule priority,
prefix origin checks, malformed metadata, unsafe profile paths, and configuration
round-tripping/version handling. Build the actual app bundle through Xcode in
addition to testing the core package.

Runtime checks should distinguish verified behavior from pending manual checks:
external URL delivery, cold launch, picker keyboard behavior, opening a selected
profile when its browser is both closed and already running, and missing-profile
recovery. Do not close the user's browsers or alter their profiles for a test.

## Follow-on milestones

After the first build: test all supported browser versions; refine accessibility
and multi-display behavior; add manual application selection and destination
ordering if not already present; prepare signed/notarized release distribution.
Firefox and Safari profile routing each require a separate feasibility decision.
