# Native UI prototype

The prototype replaces the segmented settings form with a compact sidebar, browser cards, and a smaller searchable link picker. Profiles are the primary label in the picker; browser names provide context. Rules have explicit ordering controls, an editor, deletion confirmation, and a URL tester. Setup, profile permission, empty, loading, launch-error, and read-only states have dedicated presentations.

## System appearance

Navigation and search surfaces use SwiftUI's native `glassEffect(.regular)` on macOS 26 and later when built with Swift 6.2 or later. Earlier systems use regular material. Content stays on system background colors. Reduce Transparency and Increase Contrast select opaque navigation surfaces. System appearance controls rendering; Ouvre does not read private preferences or offer a competing glass setting. Native controls and animations retain system behavior.

References: [Apple's custom Liquid Glass guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) and [macOS appearance settings](https://support.apple.com/en-gb/guide/mac-help/mchlp1225/26/mac/26).

## Reproduce the review

Run `./scripts/ui/capture.sh` with Xcode installed. The standalone harness compiles the actual views with synthetic browsers and rules, then writes PNGs to `.build/ui-review`. It does not read or write user configuration, launch browsers, change the default browser, or use system-wide Accessibility automation. It temporarily brings its own windows forward.

The matrix covers 17 screen/state combinations in light, dark, reduced-transparency, and increased-contrast modes (68 images), including 700 × 500 settings layouts. Accessibility overrides are injected only by the harness. Captures use AppKit view rendering; the window compositor's live glass effect is not faithfully represented in these PNGs.

Interaction checks send keyboard and mouse events to the harness's own windows and assert model outcomes. Run only those checks with `./scripts/ui/capture.sh .build/ui-review --interactions-only`.

## Verification and limits

- Reviewed picker, General, Browsers, Rules, new/edit rule, empty, permission, busy, error, and read-only layouts, including dark mode and small settings windows.
- Picker interaction checks cover arrows, search, mouse selection, long-list navigation, Return, Escape, no matches, and launch-in-progress protection.
- Settings interaction checks cover sidebar navigation, pause, profile visibility, fallback selection, rule enablement, ordering, and deletion cancel/confirm.
- Error-state checks ensure dismissing a link preserves unrelated settings failures, successful setup clears its own error, and link failures do not appear on General. Setup and profile-access errors have dedicated screen captures.
- Rule editor interaction checks cover adding and editing rules, disabled save buttons for invalid patterns, and Return submitting a valid rule exactly once while invalid Return keeps the sheet open.
- Six core routing tests pass. Debug and Release builds succeed; the local Release app passes signature verification.
- Native menu Pause, Try the picker, Settings, and Refresh actions were exercised in an isolated running app through its actual NSMenu items. Pause title, icon tooltip, and header state update together; reopening Ouvre presents settings or the pending picker.
- Global Clear/Tinted preference switching, VoiceOver narration, native default-browser confirmation, and real folder-consent flows were not automated in this UI review. Existing profile-routing verification is recorded separately in `VERIFICATION.md`.

Build with `./scripts/build-app.sh`; the app is written to `dist/Ouvre.app`.
