# phplus 1.3.1

Update of the existing native iOS 17+ app. Bundle ID remains `com.phplus.app`. Sign the unsigned physical-iPhone ARM64 IPA with Feather using the same identity/profile as the installed version. Install as an update; uninstalling can remove website data.

## Urgent recovery fix

A native row above web content always offers **Torna al portale** and **Chiudi**. The app cancels pending JavaScript dialogs/loading, closes child popups and keeps the original root WKWebView and persistent data store. An already displayed allowed portal page is not reloaded. When possible it goes to the last allowed read-only portal history item. A provider iframe without its own navigable history also triggers native recovery; JavaScript dialogs offer a native return action. Otherwise a native recovery panel replaces the unusable web content, offering an explicit portal restart or external browser. After cancellation, further navigation/response redirects to recognized OpenAge origins are stopped until the user explicitly reopens the portal. No verification success is inferred.

**Annulla verifica / altri metodi** uses the site's previous history item when one exists; otherwise it invokes portal recovery. A site's SPA method selector may have no separate history item: phplus cannot force that selector or reset the provider state. In that case reopen the portal explicitly and use its own controls to select Face Scan. Home explicitly restarts the configured entry; Back stops the current load first; Close leaves the portal screen. The native recovery panel remains available if the provider refuses navigation or immediately redirects back.

## AgeKey correction and limits

The 1.3 ASWebAuthenticationSession with a nil callback was not a complete native integration and has been removed. The generic third-party portals do not register phplus's callback or associated domains. No callback support is assumed, and no signed verification URL is rewritten. Embedded WKWebView passkey access for an external relying party cannot be enabled simply by adding somebody else's associated domain. The provider's real-device incompatibility message is not treated as a successful verification.

**AgeKey esterna** explicitly opens the original configured HTTPS portal in the actual iOS default browser (Safari if selected), using UIApplication.open. It does not forward the current verification URL, tokens or page DOM. Complete the entire portal login, AgeKey and provider return inside that same browser. Normal browser tabs give the provider/credential manager the opportunity to offer a saved AgeKey. Actual creation, recognition, acceptance and return remain unverified on hardware. Opening success reports only an OS handoff, never verification success. Failed opening gives an explicit error and leaves phplus's page/session intact.

No automatic return or transfer of verification to WKWebView is promised. Its cookies/session are separate. Returning to phplus resumes its retained page after the normal app unlock and can legitimately require verification again. A transparent ASWebAuthenticationSession bridge would require the portal/provider's registered redirect contract and server cooperation. No callback handler, token interception, credential manipulation, forged outcome, client secret or external-domain entitlement is added.

Face Scan remains available inside the existing WKWebView. Camera/microphone usage descriptions, WKUIDelegate media permission implementation, HTTPS/frame/visibility checks and `.prompt` consent are preserved; no unconditional grant. Provider iframe policies and server-side expiration still apply.

## Privacy and persistence

Face ID/device passcode protects phplus, including automatic launch/foreground authentication, duplicate suppression, recovery retry and authenticated settings changes. The opaque scene privacy window, app-lock overlay, retained WebViews and media shutdown are unchanged. Root and popup PiP/AirPlay stay disabled. No Live Activities or background modes are enabled.

**External browser privacy is outside phplus's control:** Face ID for phplus does not lock Safari/another browser. Its tabs, app-switcher previews, history, synchronization, cookies, playback and system indicators are controlled by that browser/iOS. phplus cannot hide or close those tabs or stop external media. Use browser privacy/security controls and close external tabs yourself when appropriate. The app does not force private mode; use a normal tab if provider-approved persistence is desired.

WKWebsiteDataStore.default() remains persistent. No website data is deleted on close. Cookies/localStorage/IndexedDB follow WebKit and service lifetimes; checkpoint counts are observation, not a guaranteed synchronous disk flush. In-memory recovery history is not persisted. Cold restoration remains restricted to approved read-only same-origin HTTPS routes without query, fragment, userinfo or non-GET operations. Configuration/allowed restoration files retain complete file protection. Tokens, assertions and expired verification lifetimes are not modified. No personal portal URL or credentials are embedded.

## Verification

GitHub Actions macOS builds Release for iphoneos ARM64 and inspects the packaged IPA version, camera/microphone/Face ID usage keys, media delegate selector, no Live Activities/background modes, architecture and Mach-O platform. Existing native capture policy and JavaScript diagnostic/media privacy checks remain enabled.

XCTest on iPhone 16 Pro/iOS 18.5 simulator exercises authentication scheduling/settings/stale callbacks, retained WebView/history/scroll/DOM, allowed cold restore, real HTTPS getUserMedia API presence and persistent synthetic cookies/localStorage/IndexedDB across two test-host processes. New cases check original-portal external handoff, duplicate suppression, open failure, cancellation/provider-loop guard/explicit retry, no reload on safe portal return, history recovery with cookies, popup closure and retained root instance. UIKit curtain and media configuration checks remain. The simulator-only minimum target is 18.4 for WebKit bug 293831; device Release remains iOS 17+.

**Requires physical iPhone and service account; not claimed passed:** actual AgeKey creation/reuse and existing credential recognition, portal login/provider return in external browser, OS browser selection, Face ID/code prompts, Face Scan/camera consent, OS app-switcher previews/Dynamic Island and actual media shutdown. Simulator synthetic provider recovery is not an OpenAge end-to-end test. After installation verify cancellation during redirect, retry, Face Scan selection, external full-portal flow, app switching and force-quit/relaunch without uninstalling.

Official references:
- https://docs.agekey.org/guides/mobile-apps/
- https://docs.ageapi.org/guide
- https://developer.apple.com/documentation/authenticationservices/supporting-passkeys
- https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
