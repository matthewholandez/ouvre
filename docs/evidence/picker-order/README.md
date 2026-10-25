# Saved picker order verification

The isolated native fixture uses Helium with Personal and Work profiles, plus Chrome and Safari. The UI harness clicks Work's up arrow and Helium's down arrow in **Settings → Browsers**. [Settings](settings.png) then shows Chrome, Helium with Work before Personal, and Safari. [Picker](picker.png) shows the matching visible order and shortcut numbers; pressing **2** selects Work. The controls use ordinary accessible SwiftUI buttons with descriptive labels, and boundary buttons are disabled.

The [interaction log](interactions.log) records these clicks and checks a restored configuration, a hidden destination, an absent browser, a newly discovered browser, and the read-only guard. Core tests cover backward-compatible version 1 decoding, persisted order, and keeping absent IDs. Verification used:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
scripts/ui/capture.sh .build/order-ui --interactions-only
scripts/build-app.sh
```

The fixture does not read or write the real Ouvre configuration, change the system default browser, or launch a browser.
