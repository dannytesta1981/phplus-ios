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
    let curtain = PrivacyCurtain()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationCenter.default.addObserver(self, selector: #selector(hideContent(_:)), name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showContent(_:)), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(backgrounded), name: UIApplication.didEnterBackgroundNotification, object: nil)
        return true
    }
    @objc private func hideContent(_ notification: Notification) {
        if let scene = notification.object as? UIWindowScene { curtain.hide(in: scene) }
    }
    @objc private func showContent(_ notification: Notification) {
        if let scene = notification.object as? UIWindowScene { curtain.reveal(in: scene) }
        MediaPrivacyHub.shared.resumeVisible()
    }
    @objc private func backgrounded() { MediaPrivacyHub.shared.suspendAll() }
}

struct Portal: Codable, Identifiable, Equatable, Hashable {
    var id: Int
    var title: String
    var url: String
}

@MainActor final class PortalStore: ObservableObject {
    @Published private(set) var portals: [Portal] = []
    @Published var storageError: String?
    private var sessions: [Int: WebState] = [:]
    private let files: ProtectedFiles
    private var resume = ResumeState()
    private var writable = true
    private var authorized = false
    private var coldPortalID: Int?
    init(files: ProtectedFiles = .application, defaults: UserDefaults = .standard) {
        self.files = files
        do {
            if let saved = try files.read("portals.json", as: [Portal].self) { portals = saved; defaults.removeObject(forKey: "privatehub.portals.v1") }
            else if let legacy = defaults.data(forKey: "privatehub.portals.v1"), let saved = try? JSONDecoder().decode([Portal].self, from: legacy) {
                portals = saved
                try files.write(saved, name: "portals.json")
                defaults.removeObject(forKey: "privatehub.portals.v1")
            } else { portals = (1...3).map { Portal(id: $0, title: "Portale \($0)", url: "") } }
            resume = try files.read("resume.json", as: ResumeState.self) ?? ResumeState()
            coldPortalID = resume.activePortal
        } catch {
            writable = false
            storageError = "Dati locali non accessibili. Chiudi e riapri dopo aver sbloccato iPhone; i file esistenti non saranno sovrascritti."
        }
    }
    func update(_ portal: Portal) {
        guard writable, let index = portals.firstIndex(where: { $0.id == portal.id }) else { return }
        var updated = portals; updated[index] = portal
        do {
            try files.write(updated, name: "portals.json")
            if portals[index].url != portal.url {
                sessions.removeValue(forKey: portal.id)?.dispose()
                resume.pages.removeValue(forKey: portal.id)
                resume.evidence.removeValue(forKey: portal.id)
            }
            portals = updated; persistResume()
        } catch { storageError = "Impossibile salvare le impostazioni del portale." }
    }
    var restoredPortal: Portal? { portals.first { $0.id == resume.activePortal && !$0.url.isEmpty } }
    func activate(_ id: Int?) { resume.activePortal = id; persistResume() }
    func session(for portal: Portal) -> WebState {
        if let existing = sessions[portal.id] { return existing }
        let state = WebState()
        state.entry = URL(string: portal.url)
        state.authorized = authorized
        state.coldRestoration = coldPortalID == portal.id
        if state.coldRestoration { coldPortalID = nil }
        if let entry = state.entry, let saved = resume.pages[portal.id], let url = URL(string: saved) {
            state.restoredURL = RestorationPolicy.restorable(url, entry: entry)
        }
        state.previousEvidence = resume.evidence[portal.id]
        state.onCheckpoint = { [weak self] url, evidence in
            guard let self = self else { return }
            if let url = url { self.resume.pages[portal.id] = url.absoluteString }
            else { self.resume.pages.removeValue(forKey: portal.id) }
            if let evidence = evidence { self.resume.evidence[portal.id] = evidence }
            self.persistResume()
        }
        sessions[portal.id] = state
        return state
    }
    func setAuthorization(_ allowed: Bool) {
        authorized = allowed
        for state in sessions.values { state.setAuthorization(allowed) }
    }
    func backgrounded() {
        for state in sessions.values { state.systemBrowser.backgrounded(); state.suspendAndCheckpoint() }
    }
    private func persistResume() {
        guard writable else { return }
        do { try files.write(resume, name: "resume.json") }
        catch { storageError = "Impossibile salvare il punto di ripresa. I dati web restano gestiti da WebKit." }
    }
}

struct RootView: View {
    @EnvironmentObject private var security: SecurityController
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PortalStore()
    @State private var selected: Portal?
    @State private var editing: Portal?
    @State private var settings = false
    @State private var restored = false
    var body: some View {
        ZStack {
            NavigationStack {
                List {
                    Section("Portali") {
                        ForEach(store.portals) { portal in
                            HStack {
                                Button { if !portal.url.isEmpty { selected = portal } else { editing = portal } } label: {
                                    Label(portal.title, systemImage: "globe").foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.borderless)
                                Button { editing = portal } label: { Image(systemName: "pencil").foregroundStyle(.secondary) }
                                    .buttonStyle(.borderless).accessibilityLabel("Modifica \(portal.title)")
                            }
                        }
                    }
                    Section {
                        Button("Impostazioni", systemImage: "gearshape") { settings = true }
                        if security.enabled { Button("Blocca ora", systemImage: "lock.fill") { security.lock() } }
                    }
                    if let message = store.storageError { Section { Text(message).foregroundStyle(.red) } }
                }
                .navigationTitle("phplus")
                .sheet(item: $editing) { portal in PortalEditor(portal: portal) { store.update($0) } }
                .sheet(isPresented: $settings) { SecuritySettings().environmentObject(security) }
                .navigationDestination(item: $selected) { portal in PortalBrowser(portal: portal, state: store.session(for: portal)) }
            }
            .allowsHitTesting(security.unlocked && scenePhase == .active)
            .accessibilityHidden(!security.unlocked || scenePhase != .active)
            if !security.unlocked {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield").font(.system(size: 55))
                    Text("phplus").font(.title.bold())
                    if security.busy { ProgressView("Autenticazione in corso…") }
                    if let message = security.errorMessage {
                        Text(message).font(.footnote).multilineTextAlignment(.center)
                        Button("Riprova Face ID / codice iPhone") { security.unlock() }.buttonStyle(.borderedProminent)
                    }
                }.padding()
            }
        }
        .overlay { if scenePhase != .active { Color(uiColor: .systemBackground).ignoresSafeArea() } }
        .task {
            if !restored { selected = store.restoredPortal; restored = true }
            store.setAuthorization(security.unlocked)
            if scenePhase == .active { security.becameActive() }
        }
        .onChange(of: security.unlocked) { _, unlocked in store.setAuthorization(unlocked) }
        .onChange(of: selected) { _, portal in store.activate(portal?.id) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // Keep the selected portal and the same WKWebView hierarchy alive.
                // Dismiss sheets so no configuration screen bypasses the lock overlay.
                editing = nil; settings = false
                security.backgrounded(); store.setAuthorization(security.unlocked); store.backgrounded()
            } else if phase == .active { security.becameActive(); store.setAuthorization(security.unlocked) }
        }
    }
}

struct SecuritySettings: View {
    @EnvironmentObject private var security: SecurityController
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Sicurezza") {
                    Toggle("Blocco Face ID / codice iPhone", isOn: Binding(get: { security.enabled }, set: { security.setEnabled($0) })).disabled(security.busy)
                    Text("Attivo per impostazione predefinita. Lo sblocco parte automaticamente all’avvio e dopo il background. Ogni modifica richiede Face ID o il codice iPhone.").font(.footnote)
                    if security.busy { ProgressView("Conferma la modifica con iOS…") }
                    if let message = security.errorMessage { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Impostazioni")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
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
    @Published var recoveryVisible = false
    let systemBrowser = SystemBrowserController()
    var mediaSuspended = false
    var closePopup: (() -> Void)?
    var entry: URL?
    var restoredURL: URL?
    var previousEvidence: StorageEvidence?
    var onCheckpoint: ((URL?, StorageEvidence?) -> Void)?
    var retainedHost: UIView?
    var retainedCoordinator: BrowserView.Coordinator?
    var navigationMethods: [ObjectIdentifier: String] = [:]
    var restoreCandidates: [ObjectIdentifier: URL] = [:]
    var authorized = false
    var coldRestoration = false
    private(set) var initialLoadCount = 0
    private(set) var creationCount = 0
    func setAuthorization(_ allowed: Bool) {
        authorized = allowed
        if allowed { loadInitialIfNeeded(); retainedCoordinator?.resumeMediaIfAllowed() }
        else { retainedCoordinator?.suspendCapture() }
    }
    func loadInitialIfNeeded() {
        guard authorized, initialLoadCount == 0, let view = retainedCoordinator?.windows.first, let url = restoredURL ?? entry else { return }
        if coldRestoration && restoredURL == nil && RestorationPolicy.restorable(url, entry: url) == nil {
            Task { @MainActor [weak self] in self?.error = "Ripresa automatica non consentita per questa pagina. Usa Pagina iniziale per aprirla esplicitamente." }
            return
        }
        initialLoadCount += 1
        view.load(URLRequest(url: url))
    }
    func openEntry() {
        guard authorized else { return }
        recoveryVisible = false
        let coordinator = coordinator()
        coordinator.stopForRecovery()
        guard let entry = entry, let view = coordinator.windows.first else { return }
        initialLoadCount = max(initialLoadCount, 1)
        error = nil
        coordinator.resumeMediaIfAllowed()
        view.load(URLRequest(url: entry))
    }
    func resumePage() {
        recoveryVisible = false; error = nil
        retainedCoordinator?.resumeMediaIfAllowed()
    }
    func returnToPortal() { coordinator().returnToPortal() }
    func navigateBack() { coordinator().navigateBack() }

    func coordinator() -> BrowserView.Coordinator {
        if let value = retainedCoordinator { return value }
        let value = BrowserView.Coordinator(state: self)
        retainedCoordinator = value
        return value
    }
    func prepareHost(url: URL) -> UIView {
        if let host = retainedHost { return host }
        if entry == nil { entry = url }
        let host = BrowserHost(); retainedHost = host
        host.onWindowChange = { [weak self, weak host] visible in
            if visible { self?.retainedCoordinator?.resumeMediaIfAllowed() }
            else {
                // Ignore detach/reattach within one SwiftUI update. Real background
                // and explicit Close/lock still stop capture synchronously.
                Task { @MainActor [weak self, weak host] in
                    guard host?.window == nil else { return }
                    self?.retainedCoordinator?.suspendCapture()
                }
            }
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.userContentController.addUserScript(WKUserScript(source: MediaDiagnostics.script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        configuration.userContentController.add(coordinator(), name: "phplusMedia")
        let webView = WKWebView(frame: host.bounds, configuration: configuration)
        didCreate(); coordinator().attach(webView, to: host)
        loadInitialIfNeeded()
        Task { @MainActor [weak self] in self?.captureStatus() }
        return host
    }
    func didCreate() { creationCount += 1 }
    func suspendAndCheckpoint() {
        retainedCoordinator?.suspendCapture()
        checkpoint()
    }
    func dispose() {
        onCheckpoint = nil
        systemBrowser.close()
        retainedCoordinator?.cleanup()
        retainedCoordinator = nil; retainedHost = nil
    }
    func checkpoint() {
        guard let view = view else { return }
        retainedCoordinator?.updateRestoreCandidate(view)
        let safe = restoreCandidates[ObjectIdentifier(view)]
        // Persist the navigation decision immediately; the cookie inspection below
        // is asynchronous observation, NOT a public WebKit disk-flush API.
        onCheckpoint?(safe, nil)
        let task = BackgroundCheckpoint()
        task.start()
        Task { @MainActor [weak self, weak view] in
            defer { task.finish() }
            guard let self = self, let view = view else { return }
            let inspectedURL = view.url
            let cookies = await view.configuration.websiteDataStore.httpCookieStore.phplusCookieSnapshot()
            guard view.url == inspectedURL else { return }
            let host = inspectedURL?.host?.lowercased() ?? ""
            let relevant = cookies.filter { cookie in let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")); return host == domain || host.hasSuffix("." + domain) }
            let counts = try? await view.callAsyncJavaScript("let local = null; let databases = null; try { local = localStorage.length; } catch (_) {} try { if (indexedDB.databases) databases = (await indexedDB.databases()).length; } catch (_) {} return {local, databases};", arguments: [:], in: nil, contentWorld: .defaultClient) as? [String: Any]
            guard view.url == inspectedURL else { return }
            let evidence = StorageEvidence(origin: host, cookies: relevant.count, persistentCookies: relevant.filter { !$0.isSessionOnly }.count, localKeys: counts?["local"] as? Int, databases: counts?["databases"] as? Int)
            self.record("DATI WEB", "Store persistente; cookie visibili: \(evidence.cookies), persistenti: \(evidence.persistentCookies); localStorage: \(evidence.localKeys.map(String.init) ?? "non osservabile"), IndexedDB: \(evidence.databases.map(String.init) ?? "non osservabile"). Nessun valore copiato")
            if let old = self.previousEvidence, old.origin == evidence.origin {
                if old.cookies > evidence.cookies || (old.localKeys ?? 0) > (evidence.localKeys ?? 0) || (old.databases ?? 0) > (evidence.databases ?? 0) {
                    self.record("CONFRONTO DATI", "Quantità locali diminuite: possibile scadenza, modifica del sito o perdita locale; causa non determinabile dai soli conteggi")
                } else { self.record("CONFRONTO DATI", "Conteggi presenti: non provano che la verifica sia ancora valida. Una nuova richiesta può dipendere dal servizio o da stato effimero") }
            }
            self.previousEvidence = evidence
            // Do not let an older asynchronous completion overwrite a newer URL.
            self.onCheckpoint?(self.view.flatMap { self.restoreCandidates[ObjectIdentifier($0)] }, evidence)
        }
    }
    func record(_ category: String, _ detail: String) {
        events.append("[\(category)] \(detail)")
        if events.count > 80 { events.removeFirst(events.count - 80) }
    }
    func inspectPasskeyAvailability() {
        guard let view = view else { return }
        Task { @MainActor [weak self] in
            let result = try? await view.callAsyncJavaScript("const api = typeof PublicKeyCredential !== 'undefined'; let platform = null; try { if (api && PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable) platform = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable(); } catch (_) {} return {api, platform};", arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
            self?.record("PASSKEY", "API WebAuthn: \((result?["api"] as? Bool) == true ? "presente" : "non osservabile"); disponibilità piattaforma: \((result?["platform"] as? Bool).map { $0 ? "sì" : "no" } ?? "non osservabile"). Non verifica AgeKey, dominio associato o credenziali salvate. Usa il browser di sistema per domini esterni")
        }
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var security: SecurityController
    let portal: Portal
    @ObservedObject var state: WebState
    @ObservedObject private var browser: SystemBrowserController
    init(portal: Portal, state: WebState) {
        self.portal = portal
        self._state = ObservedObject(wrappedValue: state)
        self._browser = ObservedObject(wrappedValue: state.systemBrowser)
    }
    @State private var startSystemBrowser = false
    @State private var diagnostics = false
    @State private var ageKey = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Torna al portale") { state.returnToPortal() }.accessibilityIdentifier("returnToPortal")
                Spacer()
                Button("Chiudi") { state.retainedCoordinator?.suspendCapture(); dismiss() }
            }.padding(10)
            if let message = state.error { Text(message).font(.footnote).padding().accessibilityIdentifier("webError") }
            if let status = browser.status { Text(status).font(.footnote).padding(8) }
            ZStack {
                if let url = URL(string: portal.url) { BrowserView(url: url, state: state) }
                if state.recoveryVisible {
                    VStack(spacing: 18) {
                        Text("Recupero del portale").font(.headline)
                        Text("La pagina e i cookie sono conservati. Non è stata avviata una nuova verifica né ricaricata la pagina iniziale.")
                        Button("Riprendi pagina conservata") { state.resumePage() }
                        if state.coordinator().canReturnThroughHistory {
                            Button("Pagina precedente del portale") { state.coordinator().returnThroughHistory() }
                        }
                        Button("Riapri pagina iniziale") { state.openEntry() }
                        Button("Apri portale nel browser esterno") { ageKey = true }
                        Text("Se il sito continua a richiedere la verifica, usa i suoi comandi per scegliere Face Scan. La riapertura può riproporre la stessa richiesta del servizio.").font(.footnote)
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(uiColor: .systemBackground))
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { diagnostics = false; startSystemBrowser = false; ageKey = false } }
        .onChange(of: security.unlocked) { _, unlocked in if !unlocked { diagnostics = false; startSystemBrowser = false; ageKey = false } }
        .navigationTitle(portal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Diagnostica", systemImage: "stethoscope") { state.captureStatus(); state.inspectPasskeyAvailability(); diagnostics = true }
                    Button("AgeKey / browser di sistema", systemImage: "key") { ageKey = true }
                    if state.hasPopup { Button("Chiudi finestra del sito", systemImage: "xmark") { state.closePopup?() } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { state.navigateBack() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Indietro")
                Button { state.view?.goForward() } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Avanti")
                Spacer()
                Button { state.openEntry() } label: { Image(systemName: "house") }.accessibilityLabel("Pagina iniziale")
                Button { state.error = nil; state.view?.reload() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Ricarica")
            }
        }
        .sheet(isPresented: $ageKey, onDismiss: {
            guard startSystemBrowser else { return }
            startSystemBrowser = false
            guard security.unlocked, state.authorized, UIApplication.shared.applicationState == .active else { return }
            state.retainedCoordinator?.suspendCapture()
            browser.open(portal: state.entry)
            state.record("AGEKEY", "Apertura esplicita dell’ingresso del portale nel browser esterno richiesta. Nessun esito o sessione trasferito")
        }) {
            AgeKeyBrowserHelp(browser: browser) { startSystemBrowser = true }
        }
        .onChange(of: browser.active) { _, active in if !active { state.retainedCoordinator?.resumeMediaIfAllowed() } }
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
                .navigationTitle("Diagnostica 1.3.2")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { diagnostics = false } } }
            }
        }

    }
}

@MainActor final class BrowserHost: UIView {
    var onWindowChange: ((Bool) -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }
}

struct BrowserView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: WebState
    func makeUIView(context: Context) -> UIView { state.prepareHost(url: url) }
    func updateUIView(_ uiView: UIView, context: Context) {}
    // Actual attachment changes are observed by BrowserHost. SwiftUI may dismantle
    // a representation while the retained host is still visible (e.g. a sheet).
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {}
    func makeCoordinator() -> Coordinator { state.coordinator() }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, PrivacyMediaParticipant {
        let state: WebState
        weak var host: UIView?
        var windows: [WKWebView] = []
        var portalItem: WKBackForwardListItem?
        private var cancelDialog: (() -> Void)?
        private weak var dialog: UIAlertController?
        func cancelPendingDialog() {
            dialog?.dismiss(animated: false)
            cancelDialog?()
            cancelDialog = nil; dialog = nil
        }
        init(state: WebState) { self.state = state; super.init(); MediaPrivacyHub.shared.register(self) }
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
            if state.hasPopup != (windows.count > 1) { state.hasPopup = windows.count > 1 }
            state.closePopup = { [weak self] in if let view = self?.windows.last { self?.close(view) } }
        }
        func close(_ webView: WKWebView) {
            guard let index = windows.firstIndex(where: { $0 === webView }), index > 0 else { return }
            // Descendants belong to the popup too.
            for view in windows[index...] { view.setCameraCaptureState(.none, completionHandler: nil); view.setMicrophoneCaptureState(.none, completionHandler: nil); view.stopLoading(); view.removeFromSuperview(); view.navigationDelegate = nil; view.uiDelegate = nil }
            windows.removeSubrange(index...)
            state.view = windows.last
            if state.hasPopup != (windows.count > 1) { state.hasPopup = windows.count > 1 }
            state.record("POPUP", "Finestra chiusa; sessione del sito conservata")
        }
        // Recovery never clears storage or replaces the retained root WebView.
        func stopForRecovery() {
            cancelPendingDialog()
            for view in windows { view.stopLoading() }
            if windows.count > 1 { close(windows[1]) }
            suspendCapture()
        }
        func returnToPortal() {
            let hadPopup = windows.count > 1
            stopForRecovery()
            state.error = nil
            // Closing a child exposes its retained parent without issuing a load.
            // A same-view or iframe flow cannot safely be reset by host heuristics.
            // Offer explicit choices instead of another redirect/load/back cycle.
            state.recoveryVisible = !hadPopup
            if hadPopup { resumeMediaIfAllowed() }
            state.record("RECUPERO", "Pagina conservata; nessun dominio bloccato e nessuna riapertura automatica")
        }
        var canReturnThroughHistory: Bool {
            guard let root = windows.first, let item = portalItem else { return false }
            return root.backForwardList.backList.contains { $0 === item }
        }
        func returnThroughHistory() {
            guard state.authorized, canReturnThroughHistory, let root = windows.first, let item = portalItem else { return }
            stopForRecovery()
            state.resumePage()
            root.go(to: item) // One explicit user action; any legitimate redirect is allowed.
        }
        func navigateBack() {
            cancelPendingDialog()
            guard let current = windows.last else { returnToPortal(); return }
            current.stopLoading()
            if current.canGoBack {
                state.resumePage()
                current.goBack() // Allows the provider's preceding method page when in history.
            } else { returnToPortal() }
        }
        func resumeMediaIfAllowed() {
            guard state.authorized, !state.recoveryVisible, UIApplication.shared.applicationState == .active, host?.window?.isHidden == false else { return }
            state.mediaSuspended = false
            // Do not force-play the site's previous stream or obtain a new stream.
            // No persistent WebKit suspension is used; the page may request capture.
        }
        func suspendCapture() {
            guard !state.mediaSuspended else { return }
            state.mediaSuspended = true
            cancelPendingDialog()
            for view in windows {
                view.closeAllMediaPresentations(completionHandler: nil)
                view.pauseAllMediaPlayback(completionHandler: nil)
                view.setCameraCaptureState(.none, completionHandler: nil)
                view.setMicrophoneCaptureState(.none, completionHandler: nil)
            }
            MediaPrivacyHub.shared.clearOwnSystemMedia()
        }
        func cleanup() {
            (host as? BrowserHost)?.onWindowChange = nil
            suspendCapture()
            for view in windows {
                view.stopLoading()
                view.closeAllMediaPresentations(completionHandler: nil)
                view.pauseAllMediaPlayback(completionHandler: nil)
                view.setCameraCaptureState(.none, completionHandler: nil)
                view.setMicrophoneCaptureState(.none, completionHandler: nil)
                view.configuration.userContentController.removeScriptMessageHandler(forName: "phplusMedia")
                view.navigationDelegate = nil; view.uiDelegate = nil
            }
            windows.removeAll()
            state.closePopup = nil
            state.view = nil
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { state.error = nil; state.restoreCandidates.removeValue(forKey: ObjectIdentifier(webView)); state.onCheckpoint?(nil, nil); state.record("NAVIGAZIONE", "Caricamento iniziato") }
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) { state.record("REDIRECT", "Reindirizzamento del sito; archivio cookie persistente invariato") }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.record("NAVIGAZIONE", "Documento caricato")
            updateRestoreCandidate(webView)
            if webView === windows.first, let entry = state.entry,
               RestorationPolicy.restorable(webView.url, entry: entry, method: state.navigationMethods[ObjectIdentifier(webView)] ?? "GET") != nil {
                portalItem = webView.backForwardList.currentItem
            }
            state.checkpoint()
        }
        func updateRestoreCandidate(_ webView: WKWebView) {
            let key = ObjectIdentifier(webView)
            if let entry = state.entry, let safe = RestorationPolicy.restorable(webView.url, entry: entry, method: state.navigationMethods[key] ?? "GET") {
                state.restoreCandidates[key] = safe
                state.record("RIPRESA", "Pagina GET ammessa per il riavvio completo")
            } else {
                state.restoreCandidates.removeValue(forKey: key)
                state.record("RIPRESA", "Pagina esclusa dal riavvio automatico: percorso non ammesso, query, fragment, origine o operazione sensibile. In memoria resta intatta")
            }
        }
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
            guard state.authorized, !state.recoveryVisible, UIApplication.shared.applicationState == .active, let root = webView.window?.rootViewController else { return nil }
            var top = root
            while let next = top.presentedViewController { top = next }
            return top.presentedViewController == nil && !top.isBeingDismissed ? top : nil
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            guard let top = presenter(for: webView) else { completionHandler(); return }
            let alert = UIAlertController(title: "Messaggio del sito", message: message, preferredStyle: .alert)
            var resolved = false
            let finish: () -> Void = { [weak self] in
                guard !resolved else { return }; resolved = true
                self?.cancelDialog = nil; self?.dialog = nil; completionHandler()
            }
            dialog = alert; cancelDialog = finish
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in finish() })
            alert.addAction(UIAlertAction(title: "Torna al portale", style: .destructive) { [weak self] _ in self?.returnToPortal() })
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            guard let top = presenter(for: webView) else { completionHandler(false); return }
            let alert = UIAlertController(title: "Conferma del sito", message: message, preferredStyle: .alert)
            var resolved = false
            let finish: (Bool) -> Void = { [weak self] result in
                guard !resolved else { return }; resolved = true
                self?.cancelDialog = nil; self?.dialog = nil; completionHandler(result)
            }
            dialog = alert; cancelDialog = { finish(false) }
            alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in finish(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in finish(true) })
            alert.addAction(UIAlertAction(title: "Torna al portale", style: .destructive) { [weak self] _ in self?.returnToPortal() })
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard let top = presenter(for: webView) else { completionHandler(nil); return }
            let alert = UIAlertController(title: "Richiesta del sito", message: prompt, preferredStyle: .alert)
            var resolved = false
            let finish: (String?) -> Void = { [weak self] result in
                guard !resolved else { return }; resolved = true
                self?.cancelDialog = nil; self?.dialog = nil; completionHandler(result)
            }
            dialog = alert; cancelDialog = { finish(nil) }
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in finish(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in finish(alert.textFields?.first?.text) })
            alert.addAction(UIAlertAction(title: "Torna al portale", style: .destructive) { [weak self] _ in self?.returnToPortal() })
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            guard CapturePolicy.allows(requestScheme: origin.protocol, requestHost: origin.host, requestPort: origin.port, frameScheme: frame.securityOrigin.protocol, frameHost: frame.securityOrigin.host, framePort: frame.securityOrigin.port, pageScheme: webView.url?.scheme, active: state.authorized && !state.recoveryVisible && UIApplication.shared.applicationState == .active), windows.last === webView, webView.window?.isHidden == false else {
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
            guard CaptureConsentPolicy.decision(statuses) == .prompt else {
                state.record("PERMESSO NEGATO", "Fotocamera o microfono negato/limitato in iOS; controlla Impostazioni di phplus")
                decisionHandler(.deny); return
            }
            // Never auto-grant. WebKit presents its trusted, origin-specific user prompt
            // and obtains any first-use iOS capture consent using the compiled usage keys.
            state.record("CONSENSO SITO", "\(origin.host): richiesta \(camera ? "fotocamera" : "")\(microphone ? " microfono" : ""); \(frame.isMainFrame ? "pagina principale" : "pagina incorporata"). Decisione affidata al prompt WebKit")
            decisionHandler(.prompt)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard WebNavigationPolicy.allows(navigationAction.request.url) else {
                state.record("LIMITAZIONE", "Protocollo non supportato; nessuna regola AgeKey applicata")
                decisionHandler(.cancel); return
            }
            if navigationAction.targetFrame?.isMainFrame == true {
                let key = ObjectIdentifier(webView)
                state.navigationMethods[key] = navigationAction.request.httpMethod ?? "GET"
                state.restoreCandidates.removeValue(forKey: key)
                state.onCheckpoint?(nil, nil)
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
            configuration.allowsPictureInPictureMediaPlayback = false
            configuration.allowsAirPlayForMediaPlayback = false
            let popup = WKWebView(frame: host.bounds, configuration: configuration)
            state.navigationMethods[ObjectIdentifier(popup)] = navigationAction.request.httpMethod ?? "GET"
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
