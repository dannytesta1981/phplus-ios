import SwiftUI
import LocalAuthentication

@MainActor protocol DeviceAuthenticating: AnyObject {
    func evaluate(reason: String, completion: @escaping (Bool, String?) -> Void)
    func cancel()
}
@MainActor final class DeviceAuthenticator: DeviceAuthenticating {
    private var context: LAContext?
    func evaluate(reason: String, completion: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        self.context = context
        context.localizedFallbackTitle = "Usa codice iPhone"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            self.context = nil
            completion(false, "Configura Face ID o il codice iPhone nelle impostazioni di iOS.")
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            Task { @MainActor in completion(success, error?.localizedDescription) }
        }
    }
    func cancel() { context?.invalidate(); context = nil }
}
@MainActor final class SecurityController: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var unlocked: Bool
    @Published private(set) var busy = false
    @Published var errorMessage: String?
    private let defaults: UserDefaults
    private let authenticator: DeviceAuthenticating
    private var automaticPending = true
    private var generation = 0
    init(defaults: UserDefaults = .standard, authenticator: DeviceAuthenticating? = nil) {
        self.defaults = defaults
        self.authenticator = authenticator ?? DeviceAuthenticator()
        enabled = defaults.object(forKey: "phplus.security.lockEnabled") as? Bool ?? true
        unlocked = !enabled
    }
    func becameActive() {
        guard automaticPending, !busy else { return }
        automaticPending = false
        if enabled && !unlocked { unlock() }
    }
    func backgrounded() {
        generation += 1
        authenticator.cancel()
        busy = false
        automaticPending = true
        unlocked = !enabled
        errorMessage = nil
    }
    func lock() {
        guard enabled else { return }
        generation += 1; authenticator.cancel(); busy = false
        automaticPending = false; unlocked = false
        errorMessage = "App bloccata. Autenticati per continuare."
    }
    func unlock() {
        authenticate(reason: "Sblocca phplus") { [weak self] in self?.unlocked = true }
    }
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        authenticate(reason: "Autorizza la modifica del blocco di phplus") { [weak self] in
            guard let self = self else { return }
            self.enabled = value
            self.defaults.set(value, forKey: "phplus.security.lockEnabled")
            self.unlocked = true
            self.automaticPending = false
        }
    }
    private func authenticate(reason: String, success: @escaping () -> Void) {
        guard !busy else { return }
        busy = true; errorMessage = nil
        let attempt = generation
        authenticator.evaluate(reason: reason) { [weak self] accepted, message in
            guard let self = self, attempt == self.generation else { return }
            self.busy = false
            if accepted { self.errorMessage = nil; success() }
            else { self.errorMessage = message ?? "Autenticazione annullata o non riuscita. Puoi riprovare." }
        }
    }
}
