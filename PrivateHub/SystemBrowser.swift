import SwiftUI

// The configured portal, never a captured verification URL, is handed to the
// user's actual default browser. No callback, cookie or verification result is read.
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

@MainActor final class SystemBrowserController: ObservableObject {
    typealias Opener = (URL, @escaping (Bool) -> Void) -> Void
    @Published private(set) var active = false
    @Published private(set) var status: String?
    private let opener: Opener
    init(opener: Opener? = nil) {
        self.opener = opener ?? { url, completion in UIApplication.shared.open(url, options: [:], completionHandler: completion) }
    }
    func open(portal: URL?) {
        guard !active else { return }
        guard let url = SystemBrowserPolicy.entry(portal) else {
            status = "Ingresso HTTPS non valido. Nessun browser aperto."; return
        }
        active = true
        opener(url) { [weak self] opened in
            Task { @MainActor in
                self?.active = false
                self?.status = opened ? "Richiesta di apertura accettata da iOS. Non è un esito di verifica. Continua nel browser esterno; la WebView conserva la propria sessione separata." : "Browser esterno non aperto. La pagina in phplus è conservata; puoi riprovare o usare Face Scan."
            }
        }
    }
    // External tabs belong to the browser: phplus cannot close or privatize them.
    func close() {}
    func backgrounded() {}
}

struct AgeKeyBrowserHelp: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: SystemBrowserController
    let start: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("AgeKey nel browser esterno") {
                    Text("Apri il portale dall’inizio nel browser predefinito di iOS (Safari se impostato). Completa lì accesso, AgeKey e ritorno al portale, mantenendo tutto il percorso nello stesso browser. Non viene inoltrato l’URL temporaneo di verifica.")
                    Text("Usa una scheda normale per conservare i dati che il servizio consente. Il gestore credenziali di iOS e il sito decidono se la AgeKey esistente può essere riutilizzata. Face Scan resta disponibile in phplus.")
                }
                Section("Sessioni e ritorno") {
                    Text("Cookie e verifica del browser esterno non vengono trasferiti alla WebView. Tornando a phplus ritrovi la sua pagina precedente, che potrebbe richiedere ancora la verifica. Non è previsto un ritorno automatico registrato per questi portali.")
                }
                Section("Privacy fuori da phplus") {
                    Text("Face ID protegge l’accesso a phplus, non Safari o altri browser. Anteprime, cronologia, sincronizzazione, cookie, schede e attività multimediali esterne sono controllati dal browser. phplus non può oscurarli, fermarli o chiuderli. Usa le protezioni e i comandi del browser.")
                }
                Section {
                    Button("Apri intero portale nel browser esterno") { dismiss(); start() }.disabled(browser.active)
                    if let status = browser.status { Text(status).font(.footnote) }
                }
            }
            .navigationTitle("AgeKey esterna")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
