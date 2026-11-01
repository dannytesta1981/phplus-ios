import SwiftUI
import AuthenticationServices

// No verification URL or token is decoded, rewritten, persisted or returned to WKWebView.
// A third-party portal owns its redirect contract; we cannot invent an OIDC callback.
enum SystemBrowserPolicy {
    static func entry(_ url: URL?) -> URL? {
        guard let url = url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme?.lowercased() == "https", let host = c.host, !host.isEmpty, c.user == nil, c.password == nil else { return nil }
        return url
    }
    static func isAgeProvider(_ url: URL?) -> Bool {
        guard let url = url, url.scheme?.lowercased() == "https" else { return false }
        return ["ui.prod.ageapi.org", "ui.ageapi.org", "api.agekey.org", "agekey.org"].contains(url.host?.lowercased() ?? "")
    }
}

@MainActor protocol BrowserAuthenticationSession: AnyObject {
    var prefersEphemeralWebBrowserSession: Bool { get set }
    var presentationContextProvider: ASWebAuthenticationPresentationContextProviding? { get set }
    func start() -> Bool
    func cancel()
}
extension ASWebAuthenticationSession: BrowserAuthenticationSession {}

@MainActor final class SystemBrowserController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    typealias Factory = (URL, @escaping (URL?, Error?) -> Void) -> BrowserAuthenticationSession
    @Published private(set) var active = false
    @Published private(set) var status: String?
    private var session: BrowserAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    private var generation = 0
    private let factory: Factory
    init(factory: Factory? = nil) {
        self.factory = factory ?? { url, completion in
            // nil is deliberate: this generic browser does not own/register the
            // portal's redirect URI. The official portal flow stays in this browser.
            ASWebAuthenticationSession(url: url, callbackURLScheme: nil, completionHandler: completion)
        }
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    func open(portal: URL?, anchor: ASPresentationAnchor) {
        guard !active else { return }
        guard let url = SystemBrowserPolicy.entry(portal) else {
            status = "Ingresso HTTPS del portale non valido. Nessun flusso è stato aperto."; return
        }
        generation += 1
        let attempt = generation
        let created = factory(url) { [weak self] _, error in
            // Intentionally ignore callback URLs. Never infer PASS from a URL,
            // and never copy credentials or cookies to the embedded browser.
            Task { @MainActor in
                guard let self = self, self.generation == attempt else { return }
                self.session = nil; self.anchor = nil; self.active = false
                let nsError = error as NSError?
                let cancelled = nsError?.domain == ASWebAuthenticationSessionErrorDomain && nsError?.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
                self.status = cancelled || error == nil ? "Browser di sistema chiuso. La WebView è invariata; nessun esito o cookie è stato trasferito." : "Il browser di sistema non ha completato l’apertura. Puoi continuare con Face Scan nella WebView o usare Safari."
            }
        }
        self.anchor = anchor
        created.presentationContextProvider = self
        created.prefersEphemeralWebBrowserSession = false
        session = created; active = true; status = nil
        if !created.start() {
            generation += 1; session = nil; self.anchor = nil; active = false
            status = "Impossibile avviare il browser di sistema. Face Scan nella WebView resta disponibile."
        }
    }
    func close() {
        generation += 1
        let old = session
        session = nil; anchor = nil; active = false
        old?.cancel()
        status = "Browser di sistema chiuso; pagina e dati della WebView conservati."
    }
    @objc func backgrounded() {
        guard active else { return }
        close()
        status = "Browser di sistema chiuso in background per interrompere eventuali attività. Le credenziali restano gestite da iOS e dal servizio."
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor ?? ASPresentationAnchor() }
}

struct AgeKeyBrowserHelp: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: SystemBrowserController
    let start: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("AgeKey e passkey") {
                    Text("Apri l’intero portale nel browser di autenticazione di iOS, senza modalità privata richiesta dall’app. Nel sito scegli AgeKey esistente, oppure creane una con il suo flusso ufficiale. iOS e il servizio gestiscono la credenziale.")
                    Text("Potrebbe essere necessario accedere di nuovo. Cookie e login del browser di sistema non vengono copiati nella WebView.")
                }
                Section("Ritorno al sito") {
                    Text("Completa verifica e ritorno al portale nella stessa finestra di sistema. Quando la chiudi ritrovi la WebView precedente, senza trasferimenti automatici della verifica. Un ritorno nativo trasparente richiede la collaborazione del sito e un callback registrato.")
                    Text("Face Scan rimane disponibile nella WebView. Se passi a un’altra app, la finestra di sistema viene chiusa per proteggere la privacy; il servizio potrebbe richiedere di ripartire.")
                }
                Section {
                    Button("Apri portale nel browser di sistema") { dismiss(); start() }.disabled(browser.active)
                    if browser.active { Button("Chiudi browser di sistema") { browser.close() } }
                    if let status = browser.status { Text(status).font(.footnote) }
                }
            }
            .navigationTitle("AgeKey")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
