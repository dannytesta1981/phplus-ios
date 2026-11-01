# phplus 1.3.2

Aggiornamento dell'app nativa esistente per iPhone iOS 17+, bundle `com.phplus.app`, build 6. Firmare phplus-1.3.2-unsigned.ipa con Feather come aggiornamento, mantenendo bundle/identità coerenti e senza disinstallare o cancellare dati.

## Face Scan e navigazione

Eliminati i veti per i domini OpenAge, il flag di annullamento che negava popup/dialoghi/redirect, l'euristica iframe AgeKey, la sospensione persistente dei media e lo script visibilitychange/pagehide. Consenso camera/microfono con semantica 1.2: controlli HTTPS/frame/visibilità, rispetto dei rifiuti iOS, .prompt WebKit e nessuna concessione automatica.

Il sito gestisce Face Scan e i suoi redirect. Nessuna apertura esterna automatica. Camera/microfono si fermano su vero background/blocco/uscita dal portale o recupero scelto dall'utente; nessun blocco persistente impedisce nuove richieste al ritorno. Uno stream interrotto può richiedere un nuovo tentativo del sito: non viene simulato.

Torna al portale e Chiudi restano fuori dalla WebView. Il recupero chiude i popup e mostra il padre conservato oppure offre un pannello con ripresa senza load, cronologia sicura disponibile, homepage esplicita e browser esterno. Nessun ciclo automatico di back/reload. Un server può riproporre la verifica: rimangono le uscite native senza alterarne lo stato.

AgeKey esterna resta un'opzione separata del menu. Usa l'ingresso configurato e non trasferisce URL temporanei, cookie o risultati alla WebView. Face ID di phplus non controlla schede, cronologia, anteprime o media del browser esterno. Nessuna nuova integrazione AgeKey.

## Privacy e persistenza

Face ID/codice automatico configurabile, blocco background, finestra opaca, no PiP/AirPlay/Live Activities/background audio conservati. I prompt iOS inactive non fermano la scansione tramite script o sparizione SwiftUI. WKWebsiteDataStore.default(), WebView conservate e dati web non vengono cancellati o ricreati al ritorno. Ripristino a freddo ristretto ai percorsi consentiti, senza token/query/operazioni sensibili. Le scadenze del servizio rimangono valide.

## Analisi e verifica

[REGRESSIONS-1.3.2.md](REGRESSIONS-1.3.2.md) documenta i commit 1.2/1.3/1.3.1, cause accertate nel codice, ipotesi sul dispositivo e correzioni. Le descrizioni camera/microfono/Face ID sono state controllate nelle IPA precedenti e vengono ispezionate nell'IPA finale.

GitHub Actions macOS esegue controlli nativi/JavaScript, XCTest su iPhone 16 Pro/iOS 18.5 simulatore, poi Release iphoneos ARM64 e IPA/ZIP Xcode. Target minimo del solo simulatore 18.4 per WebKit 293831; IPA fisica iOS 17+. I test includono delegato con frame HTTPS reali, redirect cross-origin/POST/popup, errori/recupero, video sintetico, autenticazione simulata e persistenza in due processi. Nessun account o dato personale è incluso.

**Face Scan e consenso camera su iPhone reale non sono dichiarati verificati.** Video e rotta scan-complete sono solo fixture, senza camera o risultati di identità/età. Il criterio di accettazione richiede prova sul dispositivo con il servizio. Log, SHA e rapporto accompagnano l'IPA.
