# phplus 1.0

Native SwiftUI iPhone app (iOS 17+) with Face ID/device passcode protection and three configurable HTTPS web spaces. No sites, credentials, analytics or personal data are included.

## Install with Feather
Import phplus-unsigned.ipa into Feather, sign with your valid certificate and provisioning profile, then install. The unsigned file cannot be installed before signing. Unlock and tap a space or its pencil to configure it.

WKWebView stores cookies and sessions on this device. Website policies can expire sessions or reject embedded-browser authentication. No certificate validation bypass is implemented. JavaScript, redirects, web dialogs and links opening a new window are supported; new windows open in the same view. Authentication requiring an external app callback or a provider that rejects WKWebView is outside this release's scope.

The app covers its UI while inactive and locks on background. Face ID uses the system device-owner policy, with iPhone passcode fallback. A cancelled background authentication cannot unlock the app later.

## Build
Install XcodeGen from Homebrew, run `xcodegen generate`, then open phplus.xcodeproj. The macos-15 GitHub workflow builds Release for physical iPhone ARM64, checks the binary and packages Payload/phplus.app as an unsigned IPA. It also exports a source ZIP containing the generated Xcode project.

Compilation and binary validation do not replace physical-device testing of Face ID or the user's configured websites.
