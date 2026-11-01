import SwiftUI
import LocalAuthentication
import WebKit

@main
struct phplusApp: App {
    @StateObject private var security = SecurityController()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(security)
        }
    }
}

@MainActor final class SecurityController: ObservableObject {
    @Published var unlocked = false
    @Published var errorMessage: String?
    private var context: LAContext?
    private var generation = 0
    func lock() { generation += 1; context?.invalidate(); context = nil; unlocked = false }
    func unlock() {
        guard context == nil else { return }
        let context = LAContext()
        self.context = context
        let attempt = generation
        context.localizedFallbackTitle = "Usa codice iPhone"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            self.context = nil
            errorMessage = "Configura Face ID o un codice dispositivo per proteggere l'app."
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Accedi ai portali privati") { success, error in
            Task { @MainActor in
                guard attempt == self.generation else { return }
                self.context = nil
                self.unlocked = success
                if !success { self.errorMessage = error?.localizedDescription ?? "Autenticazione non riuscita" }
                else { self.errorMessage = nil }
            }
        }
    }
}

struct Portal: Codable, Identifiable, Equatable, Hashable {
    var id: Int
    var title: String
    var url: String
}

@MainActor final class PortalStore: ObservableObject {
    @Published var portals: [Portal] = [] { didSet { save() } }
    private let key = "privatehub.portals.v1"
    init() {
        if let data = UserDefaults.standard.data(forKey: key), let value = try? JSONDecoder().decode([Portal].self, from: data) {
            portals = value
        } else {
            portals = (1...3).map { Portal(id: $0, title: "Portale \($0)", url: "") }
        }
    }
    private func save() { if let data = try? JSONEncoder().encode(portals) { UserDefaults.standard.set(data, forKey: key) } }
    func update(_ portal: Portal) { if let index = portals.firstIndex(where: { $0.id == portal.id }) { portals[index] = portal } }
}

struct RootView: View {
    @EnvironmentObject private var security: SecurityController
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PortalStore()
    @State private var selected: Portal?
    @State private var editing: Portal?
    var body: some View {
        Group {
            if security.unlocked {
                NavigationStack {
                    List {
                        Section("Portali") {
                            ForEach(store.portals) { portal in
                                HStack {
                                    Button { if !portal.url.isEmpty { selected = portal } else { editing = portal } } label: {
                                        Label(portal.title, systemImage: "globe")
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Button { editing = portal } label: { Image(systemName: "pencil").foregroundStyle(.secondary) }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Modifica \(portal.title)")
                                }
                            }
                        }
                        Section { Button("Blocca ora", systemImage: "lock.fill") { selected = nil; security.lock() } }
                    }
                    .navigationTitle("phplus")
                    .sheet(item: $editing) { portal in PortalEditor(portal: portal) { store.update($0) } }
                    .navigationDestination(item: $selected) { portal in PortalBrowser(portal: portal) }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 55))
                    Text("phplus").font(.title.bold())
                    Button("Sblocca con Face ID") { security.unlock() }.buttonStyle(.borderedProminent)
                    if let error = security.errorMessage { Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                }.padding()
            }
        }
        .overlay { if scenePhase != .active { Color(uiColor: .systemBackground).ignoresSafeArea().overlay(Image(systemName: "lock.fill").font(.largeTitle)) } }
        .onChange(of: scenePhase) { phase in
            if phase == .background { selected = nil; editing = nil; security.lock() }
        }
    }
}

struct PortalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var portal: Portal
    var save: (Portal) -> Void
    @State private var invalid = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $portal.title)
                TextField("Indirizzo HTTPS", text: $portal.url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                if invalid { Text("Inserisci un indirizzo HTTPS valido.").foregroundStyle(.red) }
                Text("L'accesso avviene sul sito originale. Le sessioni sono conservate sul dispositivo, ma il sito può richiedere nuove verifiche.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Configura portale")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let input = portal.url.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard input.isEmpty || (URLComponents(string: input)?.scheme?.lowercased() == "https" && URLComponents(string: input)?.host != nil) else { invalid = true; return }
                        portal.url = input
                        portal.title = portal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if portal.title.isEmpty { portal.title = "Portale \(portal.id)" }
                        save(portal); dismiss()
                    }
                }
            }
        }
    }
}

@MainActor final class WebState: ObservableObject {
    weak var view: WKWebView?
    @Published var error: String?
}
struct PortalBrowser: View {
    let portal: Portal
    @StateObject private var state = WebState()
    var body: some View {
        VStack(spacing: 0) {
            if let message = state.error { Text(message).font(.footnote).padding().accessibilityIdentifier("webError") }
            if let url = URL(string: portal.url) { BrowserView(url: url, state: state) }
        }
        .navigationTitle(portal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { state.view?.goBack() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Indietro")
                Button { state.view?.goForward() } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Avanti")
                Spacer()
                Button { if let url = URL(string: portal.url) { state.view?.load(URLRequest(url: url)) } } label: { Image(systemName: "house") }.accessibilityLabel("Pagina iniziale")
                Button { state.error = nil; state.view?.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Ricarica")
            }
        }
    }
}

struct BrowserView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: WebState
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // Persistent cookies, cache and site storage.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        state.view = webView
        webView.load(URLRequest(url: url))
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: WebState
        init(state: WebState) { self.state = state }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { state.error = nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
        func report(_ error: Error) { if (error as NSError).code != NSURLErrorCancelled { state.error = "Caricamento non riuscito. Controlla la connessione e riprova." } }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { state.error = "Pagina interrotta. Premi Ricarica per riprovare." }
        private func present(_ alert: UIAlertController, webView: WKWebView) {
            guard let root = webView.window?.rootViewController else { return }
            var top = root
            while let next = top.presentedViewController { top = next }
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "Messaggio del sito", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert, webView: webView)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "Conferma del sito", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(alert, webView: webView)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: "Richiesta del sito", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            present(alert, webView: webView)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased(), ["https", "about", "blob", "data"].contains(scheme) else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url, url.scheme?.lowercased() == "https" { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}
