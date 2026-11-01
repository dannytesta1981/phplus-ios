# phplus 1.1

Native SwiftUI iPhone app (iOS 17+) with Face ID/device passcode protection and three configurable HTTPS web spaces. No sites, credentials, analytics or personal data are included.

## Install with Feather
Import phplus-1.1-unsigned.ipa into Feather, sign with your valid certificate and provisioning profile, then install. The unsigned file cannot be installed before signing. Unlock and tap a space or its pencil to configure it.

WKWebView stores cookies and sessions on this device. Website policies can expire sessions or reject embedded-browser authentication. No certificate validation bypass is implemented. JavaScript, redirects and web dialogs are supported. User-initiated popups use the WKWebViewConfiguration supplied by WebKit, retaining opener semantics and the persistent cookie store. Up to three child windows are allowed; close them from the browser menu. Camera and microphone capture stop when a child is closed or the browser is dismantled. Authentication requiring an external app callback or a provider that rejects WKWebView is outside this release's scope.

The app covers its UI while inactive and locks on background. Face ID uses the system device-owner policy, with iPhone passcode fallback. A cancelled background authentication cannot unlock the app later.

## Build
Install XcodeGen from Homebrew, run `xcodegen generate`, then open phplus.xcodeproj. The macos-15 GitHub workflow builds Release for physical iPhone ARM64, checks the binary and packages Payload/phplus.app as an unsigned IPA. It also exports a source ZIP containing the generated Xcode project.

Compilation and binary validation do not replace physical-device testing of Face ID or the user's configured websites.

## 1.1 camera access

The compiled Info.plist includes NSCameraUsageDescription and NSMicrophoneUsageDescription. The WKUIDelegate capture callback denies insecure/opaque origins, mismatched requester/frame origins or ports, inactive/nonvisible webviews, and iOS-denied/restricted capture. Every eligible request uses WKPermissionDecision.prompt (never unconditional grant), allowing WebKit's trusted site-specific prompt and iOS first-use authorization. No application-level cross-site grants are stored. Third-party HTTPS identity frames may request consent only when permitted by the embedding document; phplus does not relax Permissions Policy, iframe sandbox, HTTPS, TLS, or WebKit restrictions.

The browser menu includes Diagnostica and Apri in Safari. Diagnostics are bounded and in-memory only: fixed technical event codes plus frame origin host, without URL paths/queries, credentials, page text, arbitrary JS messages, device IDs, constraints, or media. It distinguishes API availability, secure context, inspectable frame camera policy, native iOS authorization status, media acquisition errors, JS runtime errors, HTTP status and popup/redirect activity. NotAllowedError is ambiguous and is explicitly labelled as such. Page-origin signals are untrusted and may be changed by the site; they never affect authorization. The getUserMedia observer forwards the original arguments, receiver, stream and rejection object, and never requests capture itself.

If the service explicitly requires Safari or rejects an embedded browser, use Apri in Safari and restart its verification there. This opens the current HTTPS URL with the system browser (Safari when configured as default). phplus cannot transfer its cookies/session to Safari; login may be needed again, and session-bound callback links may require restarting from the service's entry page. No claim is made that a specific identity provider works without testing on an iPhone.

## Validation scope

CI runs nine native Swift capture-origin policy checks plus JavaScript diagnostics/context/error/privacy regression checks, builds the physical-iPhone ARM64 Release, and verifies the actual packaged usage descriptions, diagnostics resource and media-permission delegate selector. These checks do not exercise the iPhone camera, permission dialogs, biometric liveness, identity-provider acceptance, popup callback compatibility or iframe behavior on a real site. These remain physical-device tests. Simulator/unit/VM checks must never be described as successful face scanning.
