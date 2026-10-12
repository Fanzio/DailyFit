# DailyFit

App nativa per palestra e nutrizione. **Il codice è stato generato con l'aiuto di ChatGPT 6.1Sol e la revisione di GPT6 Astra**, attraverso un processo di richieste, prove e correzioni. Due implementazioni indipendenti: **SwiftUI per iOS** e **Java per Android**. Interfaccia scura e verde lime; funzioni principali offline, senza account o sincronizzazione.

## Funzionalità

- Schede di allenamento con più giornate, esercizi e serie personalizzate: ripetizioni, intervalli, durata, carico e recupero.
- Catalogo esercizi con immagini locali, descrizione, gruppo muscolare e link video; diario con appunti liberi.
- Un timer di recupero alla volta, con pausa/ripresa e avviso alla scadenza.
- Dieta settimanale base e modifiche per singola data indipendenti; pasti espandibili e spuntini facoltativi.
- Alimenti per 100 g, calcolo di kcal e macro, obiettivi liberi e lista della spesa.
- Backup JSON, ripristino ed esportazione Excel per la consultazione anche in Google Fogli.
- Collegamento esterno a ChatGPT, senza invio automatico dei dati dell’app.

Al primo avvio sono inclusi 15 esercizi con 30 immagini, una scheda di quattro giorni e 6 alimenti modificabili. Carichi, recuperi, dieta e obiettivi vanno personalizzati.

## Struttura

```text
DailyFit/
├── iOS/         Progetto Xcode, sorgenti, risorse e XCTest
├── android/     Progetto Gradle, sorgenti, risorse e test JUnit
├── .gitignore
└── README.md
```

Le icone e le immagini necessarie sono già all’interno dei progetti. I test sono inclusi nei sorgenti, ma non nelle app distribuite.

## Avviare su iPhone

Richiede un Mac con Xcode e supporto a iOS 17 o successivo.

1. Apri `iOS/DailyFit.xcodeproj` in Xcode.
2. Seleziona lo schema **DailyFit** e un simulatore iPhone.
3. Premi **⌘U** per i test e **⌘R** per avviare l’app.
4. Per un iPhone reale, configura il tuo Team in **Signing & Capabilities**, collega il telefono e selezionalo come destinazione. Abilita Modalità sviluppatore se richiesta.

Bundle Identifier: `it.dailyfit.app`. Un identificativo personalizzato può essere necessario per la firma con il proprio account.

## Avviare su Android

Richiede Android Studio, Android SDK 36 e JDK 17 compatibile con il progetto. Il wrapper Gradle è incluso. Destinazione minima: Android 8.0 (API 26).

1. Apri in Android Studio la cartella `android`, non la sola sottocartella `app`.
2. Completa la sincronizzazione Gradle e seleziona un emulatore o telefono.
3. Avvia il modulo **app** con Run.
4. Per compilare ed eseguire i test dal terminale del progetto:

   - Windows: `.\gradlew.bat testDebugUnitTest assembleDebug`
   - macOS/Linux: `chmod +x gradlew`, poi `./gradlew testDebugUnitTest assembleDebug`

Application ID: `it.dailyfit.app`. L’APK debug Gradle viene scritto in `app/build/outputs/apk/debug/app-debug.apk`.

## Dati e architettura

Interfaccia, regole di dominio e archivio sono separati. I salvataggi usano SQLite con aggiornamenti incrementali; le foto sono conservate in file privati e caricate su richiesta. I timer calcolano il tempo dalla scadenza e usano gli avvisi di sistema, senza lavoro continuo in background.

I dati restano nel contenitore locale dell’app. Video e ChatGPT possono richiedere Internet. Le esportazioni manuali sono copie condivise volontariamente dall’utente; non esiste sincronizzazione automatica. DailyFit usa un contenitore separato dalle precedenti installazioni con un altro identificativo.

## Verifiche

Versione 1.4.0: su Windows sono stati compilati i sorgenti Android con SDK 36, generati APK debug/release e superati **125 test JUnit**. La verifica è stata eseguita tramite strumenti SDK diretti; il percorso Gradle/Android Studio non è stato eseguito in quella verifica.

Per iOS sono stati verificati struttura del progetto, schema, riferimenti, risorse e **114 dichiarazioni XCTest**. La compilazione Swift e l’esecuzione dei test di questa versione devono essere effettuate sul Mac. I controlli strutturali non sostituiscono la compilazione o il collaudo sui dispositivi.

I metadati dell’archivio rimangono in memoria; backup e ripristino elaborano l’intero archivio. Non sono presenti paginazione completa o test grafici automatici. Le misure di consumo e latenza richiedono prove sui telefoni.

## Caso studio: dall’idea alle app con l’AI

Il progetto nasce dall’esigenza di organizzare allenamenti e alimentazione in un’app personale, semplice da consultare e utilizzabile offline. Lo sviluppo è avvenuto attraverso un dialogo iterativo: definizione dei requisiti, prototipo HTML del design, implementazione nativa iOS, versione Android, prove e correzioni.

## Crediti e licenza

DailyFit è un progetto ideato e guidato da Luca Venceslai.
Il codice delle app iOS e Android, il prototipo e i test automatici sono stati generati con l'aiuto di ChatGPT 6.1 Sol.
Anche le immagini degli esercizi e l’icona sono state generate con AI.

Il progetto è distribuito con licenza MIT.
Consulta il file [LICENSE](LICENSE) per maggiori informazioni.

Copyright (c) 2026 Luca Venceslai.
