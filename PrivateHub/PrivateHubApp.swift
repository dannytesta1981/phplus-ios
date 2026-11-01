import SwiftUI
import LocalAuthentication
import WebKit
import AVFoundation

@main
struct phplusApp: App {
    @UIApplicationDelegateAdaptor(PrivacyDelegate.self) private var privacy
    @StateObject private var security = SecurityController()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(security)
        }
    }
}

@MainActor final class PrivacyDelegate: NSObject, UIApplicationDelegate {
    private var covers: [ObjectIdentifier: UIView] = [:]
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationCenter.default.addObserver(self, selector: #selector(hideContent(_:)), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showContent(_:)), name: UIScene.didActivateNotification, object: nil)
        return true
    }
    @objc private func hideContent(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        for window in scene.windows where covers[ObjectIdentifier(window)] == nil {
            let cover = UIView(frame: window.bounds)
            cover.backgroundColor = .systemBackground
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(cover)
            covers[ObjectIdentifier(window)] = cover
        }
    }
    @objc private func showContent(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene else { return }
        for window in scene.windows { covers.removeValue(forKey: ObjectIdentifier(window))?.removeFromSuperview() }
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
                                    .buttonStyle(.borderless)
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
        .onChange(of: scenePhase) { _, phase in
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
    @Published var events: [String] = []
    @Published var hasPopup = false
    var closePopup: (() -> Void)?
    func record(_ category: String, _ detail: String) {
        events.append("[\(category)] \(detail)")
        if events.count > 80 { events.removeFirst(events.count - 80) }
    }
    func captureStatus() {
        func label(_ status: AVAuthorizationStatus) -> String {
            switch status {
            case .authorized: return "autorizzato"
            case .denied: return "negato: abilita in Impostazioni iOS"
            case .restricted: return "limitato da iOS"
            case .notDetermined: return "da richiedere al primo utilizzo"
            @unknown default: return "sconosciuto"
            }
        }
        record("iOS", "Fotocamera: \(label(AVCaptureDevice.authorizationStatus(for: .video))); microfono: \(label(AVCaptureDevice.authorizationStatus(for: .audio)))")
    }
}

struct PortalBrowser: View {
    let portal: Portal
    @StateObject private var state = WebState()
    @State private var diagnostics = false
    @State private var safari = false
    var body: some View {
        VStack(spacing: 0) {
            if let message = state.error { Text(message).font(.footnote).padding().accessibilityIdentifier("webError") }
            if let url = URL(string: portal.url) { BrowserView(url: url, state: state) }
        }
        .navigationTitle(portal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Diagnostica", systemImage: "stethoscope") { state.captureStatus(); diagnostics = true }
                    Button("Apri in Safari", systemImage: "safari") { safari = true }
                    if state.hasPopup { Button("Chiudi finestra del sito", systemImage: "xmark") { state.closePopup?() } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { state.view?.goBack() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Indietro")
                Button { state.view?.goForward() } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Avanti")
                Spacer()
                Button { if let url = URL(string: portal.url) { state.view?.load(URLRequest(url: url)) } } label: { Image(systemName: "house") }.accessibilityLabel("Pagina iniziale")
                Button { state.error = nil; state.view?.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Ricarica")
            }
        }
        .sheet(isPresented: $diagnostics) {
            NavigationStack {
                List {
                    Section { Text("Solo eventi tecnici locali. Nessuna foto, credenziale, percorso URL o testo delle pagine viene registrato. Le origini dei siti sono visibili solo qui. I segnali JavaScript sono indicativi: il sito può alterarli.") }
                    Section("Eventi recenti") {
                        ForEach(Array(state.events.enumerated()), id: \.offset) { _, event in Text(event).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    Section {
                        Button("Aggiorna stato iOS") { state.captureStatus() }
                        Button("Impostazioni di phplus") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        Button("Cancella diagnostica") { state.events.removeAll() }
                    }
                }
                .navigationTitle("Diagnostica 1.1")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { diagnostics = false } } }
            }
        }
        .confirmationDialog("Aprire la pagina corrente in Safari?", isPresented: $safari, titleVisibility: .visible) {
            Button("Apri in Safari") {
                guard let url = state.view?.url, url.scheme?.lowercased() == "https" else { return }
                UIApplication.shared.open(url)
            }
        } message: {
            Text("Alcuni servizi richiedono Safari. Cookie e sessioni della WebView non vengono trasferiti: potrebbe essere necessario accedere di nuovo. phplus si bloccherà in background.")
        }
    }
}

struct BrowserView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: WebState
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.addUserScript(WKUserScript(source: MediaDiagnostics.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.add(context.coordinator, name: "phplusMedia")
        let webView = WKWebView(frame: host.bounds, configuration: configuration)
        context.coordinator.attach(webView, to: host)
        webView.load(URLRequest(url: url))
        state.captureStatus()
        return host
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.cleanup() }
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let state: WebState
        weak var host: UIView?
        var windows: [WKWebView] = []
        init(state: WebState) { self.state = state }
        func attach(_ webView: WKWebView, to host: UIView) {
            self.host = host
            webView.frame = host.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.allowsBackForwardNavigationGestures = true
            host.addSubview(webView)
            windows.append(webView)
            state.view = webView
            state.hasPopup = windows.count > 1
            state.closePopup = { [weak self] in if let view = self?.windows.last { self?.close(view) } }
        }
        func close(_ webView: WKWebView) {
            guard let index = windows.firstIndex(where: { $0 === webView }), index > 0 else { return }
            // Descendants belong to the popup too.
            for view in windows[index...] { view.setCameraCaptureState(.none, completionHandler: nil); view.setMicrophoneCaptureState(.none, completionHandler: nil); view.stopLoading(); view.removeFromSuperview(); view.navigationDelegate = nil; view.uiDelegate = nil }
            windows.removeSubrange(index...)
            state.view = windows.last
            state.hasPopup = windows.count > 1
            state.record("POPUP", "Finestra chiusa; sessione del sito conservata")
        }
        func cleanup() {
            for view in windows {
                view.stopLoading()
                view.setCameraCaptureState(.none, completionHandler: nil)
                view.setMicrophoneCaptureState(.none, completionHandler: nil)
                view.configuration.userContentController.removeScriptMessageHandler(forName: "phplusMedia")
                view.navigationDelegate = nil; view.uiDelegate = nil
            }
            windows.removeAll()
            state.closePopup = nil
            state.view = nil
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { state.error = nil; state.record("NAVIGAZIONE", "Caricamento iniziato") }
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) { state.record("REDIRECT", "Reindirizzamento del sito; archivio cookie persistente invariato") }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { state.record("NAVIGAZIONE", "Documento caricato") }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
        func report(_ error: Error) {
            let code = (error as NSError).code
            if code != NSURLErrorCancelled {
                state.error = "Caricamento non riuscito. Consulta Diagnostica dal menu."
                state.record("RETE", "Caricamento fallito, codice \(code)")
            }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { state.error = "Pagina interrotta. Premi Ricarica per riprovare."; state.record("WEBKIT", "Processo della pagina terminato") }
        func presenter(for webView: WKWebView) -> UIViewController? {
            guard UIApplication.shared.applicationState == .active, let root = webView.window?.rootViewController else { return nil }
            var top = root
            while let next = top.presentedViewController { top = next }
            return top.presentedViewController == nil && !top.isBeingDismissed ? top : nil
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let top = presenter(for: webView) else { completionHandler(); return }
            let alert = UIAlertController(title: "Messaggio del sito", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let top = presenter(for: webView) else { completionHandler(false); return }
            let alert = UIAlertController(title: "Conferma del sito", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let top = presenter(for: webView) else { completionHandler(nil); return }
            let alert = UIAlertController(title: "Richiesta del sito", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            guard CapturePolicy.allows(requestScheme: origin.protocol, requestHost: origin.host, requestPort: origin.port, frameScheme: frame.securityOrigin.protocol, frameHost: frame.securityOrigin.host, framePort: frame.securityOrigin.port, pageScheme: webView.url?.scheme, active: UIApplication.shared.applicationState == .active), windows.last === webView, webView.window != nil else {
                state.record("PERMESSO NEGATO", "Origine non HTTPS, frame incoerente o pagina non attiva")
                decisionHandler(.deny); return
            }
            let camera: Bool
            let microphone: Bool
            switch type {
            case .camera: camera = true; microphone = false
            case .microphone: camera = false; microphone = true
            case .cameraAndMicrophone: camera = true; microphone = true
            @unknown default: state.record("PERMESSO NEGATO", "Tipo di acquisizione non supportato"); decisionHandler(.deny); return
            }
            let statuses = (camera ? [AVCaptureDevice.authorizationStatus(for: .video)] : []) + (microphone ? [AVCaptureDevice.authorizationStatus(for: .audio)] : [])
            guard !statuses.contains(.denied), !statuses.contains(.restricted) else {
                state.record("PERMESSO NEGATO", "Fotocamera o microfono negato/limitato in iOS; controlla Impostazioni di phplus")
                decisionHandler(.deny); return
            }
            // Never auto-grant. WebKit presents its trusted, origin-specific user prompt
            // and obtains any first-use iOS capture consent using the compiled usage keys.
            state.record("CONSENSO SITO", "\(origin.host): richiesta \(camera ? "fotocamera" : "")\(microphone ? " microfono" : ""); \(frame.isMainFrame ? "pagina principale" : "pagina incorporata"). Decisione affidata al prompt WebKit")
            decisionHandler(.prompt)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let scheme = navigationAction.request.url?.scheme?.lowercased(), ["https", "about", "blob", "data"].contains(scheme) else {
                state.record("LIMITAZIONE", "Navigazione non HTTPS o protocollo esterno non supportato. Usa Apri in Safari se richiesto dal servizio")
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
                state.record("RISPOSTA SITO", "HTTP \(response.statusCode). Possibile rifiuto del servizio; non dimostra da solo un limite della WebView")
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let host = host, windows.count < 4, navigationAction.targetFrame == nil else { state.record("POPUP", "Finestra non aperta: limite massimo raggiunto"); return nil }
            if let scheme = navigationAction.request.url?.scheme?.lowercased(), !["https", "about"].contains(scheme) { state.record("POPUP", "Protocollo popup non consentito"); return nil }
            // Use WebKit's supplied configuration: keeps opener semantics and shared storage.
            let popup = WKWebView(frame: host.bounds, configuration: configuration)
            attach(popup, to: host)
            state.record("POPUP", "Finestra aperta con configurazione WebKit; chiusura disponibile nel menu")
            return popup
        }
        func webViewDidClose(_ webView: WKWebView) { close(webView) }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "phplusMedia", let body = message.body as? [String: Any], let code = body["code"] as? String, let detail = MediaDiagnostics.messages[code] else { return }
            let origin = message.frameInfo.securityOrigin
            let frame = message.frameInfo.isMainFrame ? "principale" : "incorporato"
            let site = origin.host.isEmpty ? "origine opaca" : origin.host
            state.record(detail.0, "\(site) [\(frame)]: \(detail.1)")
        }
    }
}
