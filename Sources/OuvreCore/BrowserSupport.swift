import Foundation

public enum BrowserSupport {
    // Local State profile.info_cache and --profile-directory are supported by these Chromium-family apps.
    public static let profileDataPaths: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "org.chromium.Chromium": "Chromium",
        "net.imput.helium": "net.imput.helium"
    ]

    public static let knownBrowserIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox",
        "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac",
        "com.brave.Browser", "org.chromium.Chromium", "net.imput.helium",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.kagi.kagimacOS"
    ]
}
