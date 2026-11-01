# phplus 1.3.2 — Analisi regressioni prima della build Release

## Commit confrontati

| Versione | Commit GitHub |
| --- | --- |
| 1.2, funzionante su iPhone secondo l'utente | `e9fd71db106835934cc7c879443a978617520d15` |
| 1.3 | `af0913b09a42cea7840c4df8c7e896f1913789cf` |
| 1.3.1 finale | `c485f05d542f00b554c58c8806d6196e089bf5c4` |

Confrontati via GitHub 1 commit fra 1.2 e 1.3, 3 fra 1.3 e 1.3.1, 4 complessivi. I blob di PrivateHubApp.swift corrispondono alle copie esaminate. Controllate anche le Info.plist delle tre IPA consegnate: NSCameraUsageDescription, NSMicrophoneUsageDescription e NSFaceIDUsageDescription sono presenti e identiche. Nessuna rimozione delle descrizioni permessi è stata rilevata.

## Regressioni individuate e correzioni

### Dominio condiviso scambiato per metodo AgeKey

In `PrivateHub/PrivateHubApp.swift` 1.3.1, `permitsRecoveryNavigation` e i due `decidePolicyFor` usavano `SystemBrowserPolicy.isAgeProvider` per classificare ui.prod.ageapi.org e altri host OpenAge. Il dominio non distingue Face Scan da AgeKey, iframe e callback. Dopo Torna al portale, `cancellingVerification` rimaneva attivo fino alla riapertura: anche redirect Face Scan potevano essere cancellati. È un difetto accertato del codice; il ramo preciso eseguito sull'iPhone segnalato non è osservabile qui.

La 1.3.2 elimina classificatore, flag persistente e veti di navigazione/risposta. `WebNavigationPolicy` mantiene la lista di schemi della 1.2: https, about, blob, data. Non distingue metodi di verifica, domini, query o stato di recupero. Nessuna navigazione viene inviata automaticamente a browser esterno o homepage. Le risposte HTTP non vengono cancellate in base al dominio.

### Popup e dialoghi negati dopo annullamento

Nella 1.3.1 `createWebViewWith` rifiutava tutti i popup quando `cancellingVerification` era attivo; `presenter(for:)` negava i dialoghi nello stesso stato. `embeddedProvider` presumeva AgeKey dalla presenza di un iframe OpenAge, senza conoscere il metodo realmente scelto.

Eliminati questi veti e l'euristica iframe. Rimangono il limite originale di quattro finestre, gli schemi consentiti e i controlli di visibilità/autorizzazione. I popup usano la configurazione WebKit fornita, preservando cookie e opener. I dialoghi conservano un comando nativo Torna al portale. Il solo pannello nativo di recupero coperto non consente cattura/dialoghi fino alla ripresa esplicita: non è più un blocco persistente del fornitore.

### Sospensione persistente della preview video

La 1.3 aggiunse `setAllMediaPlaybackSuspended(true)` in `Coordinator.suspendCapture`, assente nella 1.2. Apple documenta che né la pagina né l'utente possono riprendere fino alla corrispondente chiamata false. Il ripristino dipendeva da finestra già montata, stato attivo, autorizzazione, recupero e browser esterno. `onDisappear` e `dismantleUIView` potevano sospendere senza un evento affidabile di riapparizione. Ciò può impedire la preview della scansione anche se getUserMedia e il permesso OS sono disponibili. È un meccanismo causale probabile, non una misurazione della camera sul dispositivo.

Nella 1.3.2 non esiste alcuna chiamata setAllMediaPlaybackSuspended. Conservati lo stop di camera/microfono della 1.2 e una pausa singola solo per background, blocco, uscita effettiva dal portale o recupero esplicito. Nessun flag locale impedisce alla pagina visibile di acquisire nuovamente la camera. Non viene forzato play né creato uno stream al posto del sito. Uno stream terminato in background può richiedere un nuovo tentativo del servizio.

### Hook visibilitychange/pagehide della 1.3

`MediaPrivacyScript.install` in `PrivateHub/MediaPrivacy.swift` veniva iniettato in tutti i frame e metteva in pausa video/audio su eventi di visibilità. Questi eventi non provano un vero background e possono accompagnare prompt, presentazioni o navigazioni del servizio.

Script rimosso interamente. Il wrapper diagnostico `media-diagnostics.js`, identico alla 1.2, rimane: inoltra argomenti, stream ed errori originali e non registra immagini o credenziali. Nessun nuovo codice riscrive getUserMedia o richiede la camera per conto del sito.

### Ripresa della WebView conservata

La ripresa 1.3 poteva arrivare quando host.window era ancora nil. Con Face ID disabilitato, unlocked non cambiava al foreground e il relativo onChange non garantiva la ripresa.

`BrowserHost` osserva il montaggio effettivo. Un distacco/riattacco nel medesimo aggiornamento SwiftUI non ferma la camera. Gli eventi inactive dei prompt iOS oscurano soltanto la vista; il vero background ferma la cattura. Il foreground aggiorna l'autorizzazione anche con blocco disabilitato e non chiama load della homepage di una sessione già avviata. Le pause ripetute sono idempotenti e non lasciano callback asincroni di sospensione permanente.

### Recupero e ripetizione della stessa schermata

Il recupero 1.3.1 combinava ritorno nella cronologia, blocchi OpenAge e ripartenza dal portale, che il server può legittimamente reindirizzare ancora alla verifica.

Torna al portale ora interrompe una volta il caricamento e chiude i popup, mostrando il padre conservato. Per flussi nella stessa vista/iframe mostra scelte native: ripresa senza load, cronologia sicura se ancora disponibile, homepage esplicita, browser esterno e Chiudi. Nessun ciclo automatico di back/reload o veto del dominio è introdotto. Il sito può ancora chiedere la verifica; il pannello resta raggiungibile senza dichiarare modificato lo stato server. Un selettore metodi SPA può non avere una voce di cronologia: non viene forzato o falsificato.

## Componenti preservati

`CapturePolicy.swift`, `media-diagnostics.js`, `SecurityController.swift` e `Restoration.swift` sono identici alla 1.2. Il consenso resta .prompt, mai .grant, con rifiuto per contesto non HTTPS, origine/frame incoerenti, pagina non visibile/sbloccata o permesso iOS negato/limitato. La sola decisione denied/restricted della 1.2 è isolata in CaptureConsentPolicy per i test, senza cambiare il consenso effettivo.

Conservati WKWebsiteDataStore.default(), root/popup, cookie/localStorage/IndexedDB, Face ID/codice automatico e impostazioni protette, finestra privacy opaca, no PiP/AirPlay/Live Activities/background audio e ripristino sicuro. Nessuna cancellazione dei dati web. Nessun token viene intercettato, trasferito, riscritto o prolungato.

AgeKey non riceve nuove integrazioni. L'apertura esterna è solo un comando esplicito del menu sull'ingresso configurato. Nessuna osservazione del traffico WebView la attiva. Cookie/esito esterni restano separati; Face ID di phplus non protegge browser, schede, anteprime o media esterni.

## Test e limiti delle evidenze

Controlli nativi/JavaScript e test iOS su macOS precedono la build Release iphoneos. Sono verificati: decisioni permessi; frame HTTPS reali principale e cross-origin nel delegato; assenza veto OpenAge dopo recupero; redirect 302 cross-origin e POST/303; popup reale; errore rete e recupero; video sintetico riproducibile dopo inactive/visibility e pausa/ripresa; identità WebView e dati conservati; storage in due processi; autenticazione simulata e copertura UIKit. La compilazione del solo simulatore usa target 18.4 per WebKit 293831 su iOS 18.5; IPA fisica iOS 17+.

La fixture scan-complete è una rotta sintetica, non un risultato di verifica. I test del delegato non concedono consenso OS e non acquisiscono un volto; il video non è una camera. Conteggi/esiti effettivi e ispezione IPA sono allegati al rapporto finale.

**Criterio Face Scan su iPhone reale: non ancora verificato.** La segnalazione dell'utente prova il problema della 1.3.1. Non è disponibile qui un iPhone con il relativo servizio/account: non sono dichiarati superati Face Scan, consenso OS camera reale, risultato del servizio, Face ID fisico, anteprime iOS o Dynamic Island.

Dopo aggiornamento senza disinstallazione provare: Face Scan e preview; concedere/negare e riabilitare la camera; completamento e ritorno al portale; annullamento e nuova scelta Face Scan; background/foreground; chiusura completa; popup; Torna al portale/Home/Indietro/Chiudi durante redirect ed errore. Una nuova verifica imposta dal server non viene aggirata.

## Riferimenti

- https://github.com/dannytesta1981/phplus-ios/compare/e9fd71db106835934cc7c879443a978617520d15...af0913b09a42cea7840c4df8c7e896f1913789cf
- https://github.com/dannytesta1981/phplus-ios/compare/af0913b09a42cea7840c4df8c7e896f1913789cf...c485f05d542f00b554c58c8806d6196e089bf5c4
- https://developer.apple.com/documentation/webkit/wkwebview/setallmediaplaybacksuspended(_:completionhandler:)
