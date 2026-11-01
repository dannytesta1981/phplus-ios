# phplus 1.3

Native SwiftUI iPhone application (iOS 17+) with automatic Face ID/device-passcode lock, three user-configured HTTPS portals, retained WKWebViews, persistent web data and a non-ephemeral system-browser path for external passkeys such as OpenAge AgeKey. No personal site, account, credential, verification URL or token is embedded. Public provider hostnames are used only to show contextual help.

## Install

Sign phplus-1.3-unsigned.ipa with Feather and your valid certificate/profile. Install as an update with the same signing identity and bundle ID (`com.phplus.app`) to retain the sandbox. Do not uninstall or clear data first. Name and neutral icon remain phplus.

## AgeKey: supported path and integration limit

Open a configured portal, then choose **⋯ → AgeKey / browser di sistema → Apri portale nel browser di sistema**. The same option is suggested when a navigation to a recognized public OpenAge/AgeKey origin is detected; detection reads only the host and does not extract the verification query/token.

The app starts **the original configured portal entry**, unchanged, using ASWebAuthenticationSession with `prefersEphemeralWebBrowserSession = false`. Login, official AgeKey creation/reuse, and the site's own redirect back to its portal remain within that single system-browser flow. This gives iOS/the service the opportunity to offer a passkey already held in the credential manager. Actual AgeKey recognition, creation, reuse and provider acceptance require physical-iPhone testing and are NOT claimed as verified. The site's iframe Permissions Policy and provider requirements still apply.

The system browser and WKWebView do not share an assumed cookie/session store. Login may be required in the system browser. Closing it restores the unchanged embedded page; no result is imported, no PASS is inferred and no site session is reloaded automatically. The app ignores authentication callback URL values rather than decoding or forwarding them. No verification token, assertion, cookie, public-key credential or DOM verification result is read, persisted, rewritten or synthesized by this integration.

An arbitrary third-party portal does not register phplus as its native client or callback. OpenAge/AgeKey's native-app contract requires a registered redirect and service/backend cooperation. phplus cannot invent that registration, rewrite a signed verification URL, add a working association to someone else's domain, or transparently transplant system-browser verification into WKWebView. Consequently this release is an **alternative complete portal flow in the system browser**, not a verified native callback bridge to the embedded session. No associated-domains entitlement, fake deep-link handler, API client key or backend is added. For an external RP, WKWebView cannot simply gain passkey access from app settings or from an unapproved entitlement.

Face Scan in the embedded browser remains available with the 1.1 camera/microphone usage descriptions, trusted WebKit per-origin consent (`.prompt`, never unconditional grant), secure-origin/frame checks and persistent data store. This is distinct from the app's local Face ID lock.

## Privacy

A separate opaque high-level window covers the complete application scene when it deactivates, including presented sheets; it displays only phplus. It never becomes key. On foreground activation it is removed, with the existing app-lock overlay protecting the page until authentication. Camera/passkey/system prompts are not treated as a real background transition, avoiding duplicate app-auth requests or premature session cancellation.

In actual background, on lock, or when leaving a portal, public WKWebView APIs pause playback, close media presentations, suspend further playback, and stop camera/microphone capture without deleting or reloading the page. PiP and AirPlay are disabled in root and popup configurations. An isolated-world hook pauses HTML media and clears accessible MediaSession metadata; it reads no credentials or tokens. The app clears its own Now Playing metadata and deactivates its audio session. Returning to an authorized visible page permits future playback but does not explicitly restart paused media. A live camera stream is not serialized or silently restored.

ASWebAuthenticationSession has no API for controlling its page's individual media or cookies. Therefore a real app-background event cancels the system-browser presentation; the stored AgeKey remains controlled by iOS and the provider, not by phplus. The original WKWebView remains intact. A cancelled/incomplete service flow may need restarting in the system browser.

The IPA contains no background-audio mode and explicitly disables Live Activities; the app creates no ActivityKit activity or media-control extension. None of this can suppress mandatory iOS camera/microphone indicators, change Safari's own UI, or prove Dynamic Island/Now Playing cleanup on a real iPhone. Brief OS indicators/cached system UI may remain while shutdown completes. App-switcher snapshots, physical Dynamic Island behavior and a system-browser capture shutdown require hardware verification; this release does NOT claim measured complete invisibility on iOS.

## Persistent navigation and local security

The 1.2 per-portal WebState/WKWebView/host/coordinator/popup ownership is retained. Lock/background does not replace the navigation tree, page, history or scroll state. The browser uses WKWebsiteDataStore.default(); the app never clears site data or changes token expiration. Cookies, localStorage, IndexedDB and supported web data follow WebKit and site policy. Best-effort cookie/storage-count checkpoints are observations, not a synchronous disk-flush guarantee.

Portal configuration is migrated from the original UserDefaults key into atomic complete-file-protected, backup-excluded files. Active portal and strictly allowed read-only HTTPS restoration routes are protected files too. Query/fragment/userinfo/unknown/operation routes and non-GET requests are excluded from automatic cold restoration. An unsafe configured entry requires explicit user action. SessionStorage, JS memory, live media and expired verification state are not artificially made durable. A site may legitimately ask for another age check.

Face ID/passcode is on by default, starts automatically on launch/real foreground return, and has manual retry only after failure/cancellation. Impostazioni → Sicurezza requires device-owner authentication for enabling or disabling. Generation guards reject callbacks from attempts invalidated by background. Changing these features does not create a release authentication bypass.

## Diagnostics and tests

Diagnostics hold at most 80 local in-memory technical events per portal. They omit arbitrary JavaScript messages, page text, media, complete URLs/queries, device IDs and credential values. WebAuthn capability inspection reports only API/platform availability; it does not enumerate AgeKeys or prove the external RP is associated/usable. Origin hosts are visible only in the local diagnostics.

GitHub Actions builds Release for physical iPhone ARM64 and checks the actual IPA usage descriptions, media permission delegate, system-browser configuration selector, PiP configuration selector, no Live Activities/background modes, binary architecture and source correspondence. It also runs capture-origin/JavaScript regression checks and XCTest on iPhone 16 Pro/iOS 18.5 simulator using a trusted disposable HTTPS fixture. Two test-host processes verify persistent synthetic Secure cookies, localStorage and IndexedDB across relaunch. The simulator-only minimum target is 18.4 for WebKit bug 293831; device Release remains iOS 17+.

New tests verify non-ephemeral session configuration, original-portal URL forwarding, duplicate suppression, start failure, background cancellation, stale/ignored callback URLs, the neutral UIKit cover and retained WebView/media configuration. They use a mock authentication-session factory, not a real account or passkey. Existing auth/navigation/storage/camera API tests remain enabled. The MediaSession hook is tested for media pause/metadata clearing without cookie access.

**Not executed without a physical iPhone/account:** actual AgeKey creation/reuse, recognition of an existing iPhone credential, provider verification and return flow, physical Face ID/code prompts, physical camera/Face Scan, real app-switcher screenshots and Dynamic Island cleanup. These must not be labeled passed based on mocks or simulator checks.

Official integration references:

- https://docs.agekey.org/guides/mobile-apps/
- https://docs.ageapi.org/guide
- https://developer.apple.com/documentation/authenticationservices/supporting-passkeys
- https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
- https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/prefersephemeralwebbrowsersession
