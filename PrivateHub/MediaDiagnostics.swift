import Foundation

enum MediaDiagnostics {
    static let script: String = {
        guard let url = Bundle.main.url(forResource: "media-diagnostics", withExtension: "js"), let script = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return script
    }()
    // Only these fixed codes enter the local log. Never accept site-supplied text,
    // constraints, device IDs, URLs, error messages or captured media.
    static let messages: [String: (String, String)] = [
        "secure": ("CONTESTO", "Contesto sicuro disponibile"),
        "insecure": ("LIMITAZIONE SITO", "Contesto non sicuro: acquisizione non disponibile"),
        "available": ("API", "navigator.mediaDevices.getUserMedia disponibile"),
        "unavailable": ("API NON DISPONIBILE", "getUserMedia assente in questo frame"),
        "policyCameraDenied": ("LIMITAZIONE SITO", "Permissions Policy del documento blocca la fotocamera; phplus non può forzarla"),
        "policyMicDenied": ("LIMITAZIONE SITO", "Permissions Policy del documento blocca il microfono"),
        "policyCameraAllowed": ("POLICY", "Policy del documento consente fotocamera; il consenso utente resta necessario"),
        "policyUnknown": ("POLICY", "API di ispezione Permissions Policy non disponibile"),
        "request": ("ACQUISIZIONE", "getUserMedia invocato dal sito"),
        "success": ("ACQUISIZIONE", "getUserMedia ha restituito uno stream; non prova l'esito della verifica d'identità"),
        "NotAllowedError": ("PERMESSO NEGATO", "getUserMedia rifiutato: consenso utente, impostazioni iOS o policy del sito; confronta gli altri eventi"),
        "SecurityError": ("LIMITAZIONE SITO", "API di acquisizione disabilitata dal contesto o da WebKit"),
        "NotFoundError": ("DISPOSITIVO", "Nessuna sorgente compatibile disponibile"),
        "NotReadableError": ("DISPOSITIVO", "Fotocamera/microfono non utilizzabile o occupato"),
        "OverconstrainedError": ("VINCOLI SITO", "Requisiti di acquisizione non soddisfatti dal dispositivo"),
        "AbortError": ("ACQUISIZIONE", "Acquisizione interrotta"),
        "TypeError": ("ERRORE JAVASCRIPT", "Richiesta multimediale non valida o contesto non supportato"),
        "otherMediaError": ("ACQUISIZIONE", "Errore multimediale non classificato"),
        "jsError": ("ERRORE JAVASCRIPT", "Errore runtime del sito (messaggio e contenuto omessi)"),
        "promiseError": ("ERRORE JAVASCRIPT", "Promise non gestita nel sito (contenuto omesso)"),
        "instrumentationUnavailable": ("DIAGNOSTICA", "Impossibile osservare getUserMedia; funzionalità originale conservata")
    ]
}
