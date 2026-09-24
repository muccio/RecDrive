# RecDrive 🎥🖥️

**RecDrive** è un'applicazione nativa per macOS (supporto macOS 13+) progettata per essere ultra-leggera, performante e priva di qualsiasi overhead di sistema. Funziona esclusivamente come icona nella Menu Bar (`LSUIElement = true`), senza icona nel Dock o finestre persistenti, registrando lo schermo e l'audio con accelerazione hardware Apple Silicon e salvando i video direttamente nella cartella locale desiderata (sincronizzabile con Google Drive, iCloud o OneDrive).

---

## ✨ Funzionalità Principali

- **Titolo Lezione Dinamico**: Campo dedicato per inserire il titolo della lezione o della registrazione. Il file salvato include automaticamente il titolo insieme a data e ora:
  `[TitoloLezione]_YYYY-MM-dd_HH-mm-ss.mp4` (es. `Algoritmi Lezione 1_2026-09-24_18-30-00.mp4`).
- **Registrazione Affidabile a 60/30 FPS**: Frame filtering nativo ScreenCaptureKit per evitare file vuoti o danneggiati.
- **Scrittura Diretta MP4**: Flusso hardware VideoToolbox senza file temporanei corrotti o blocchi su disco.
- **Sincronizzazione Diretta Cloud**: Salvataggio automatico nella cartella predefinita (`~/Movies/RecDrive/`) oppure in una qualsiasi cartella sincronizzata con Google Drive / iCloud Drive / Dropbox.
- **Accesso Rapido Post-Registrazione**: Pulsanti dedicati per "Mostra nel Finder" e "Apri video" subito dopo aver fermato la registrazione.
- **Selettore Sorgenti**: Cattura dell'intero schermo o di singole finestre applicative.
- **Audio Flessibile**: Cattura combinata o selettiva di Audio di Sistema e Microfono esterno.

---

## 🏛️ Architettura dei Moduli

Il progetto segue una separazione rigorosa delle responsabilità a zero dipendenze esterne:

```
_SCREEN_CAPTURER/
├── Package.swift                       # Definizione Swift Package Manager (macOS 13+)
├── scripts/
│   └── bundle_app.sh                   # Script di compilazione e packaging in RecDrive.app
├── Resources/
│   ├── Info.plist                      # LSUIElement = true, usage descriptions permessi
│   └── RecDrive.entitlements           # Entitlements di sicurezza (Mic, Movies)
├── Sources/
│   └── RecDrive/
│       ├── App/
│       │   ├── RecDriveApp.swift       # Entry point @main, NSApplicationDelegate, accessory policy
│       │   └── AppState.swift          # Reactive state manager (@MainActor ObservableObject)
│       ├── Capture/
│       │   ├── ScreenCaptureManager.swift # Gestione SCStream e query SCShareableContent
│       │   ├── MediaWriter.swift       # Encoding hardware HEVC/H.264 & AAC con AVAssetWriter
│       │   ├── MicrophoneEngine.swift  # Acquisizione microfono esterno via AVAudioEngine
│       │   └── CaptureModels.swift     # Modelli per Display, Window e metriche di cattura
│       ├── Storage/
│       │   ├── PreferencesStorage.swift# Persistenza opzioni con UserDefaults
│       │   └── LocalStorageManager.swift# Gestione file disco locale e denominazione lezioni
│       └── UI/
│           ├── MenuBarView.swift       # Popover SwiftUI principale per la Menu Bar
│           ├── StatusItemController.swift # Gestione dinamica NSStatusItem con animazioni
│           ├── SourcePickerView.swift  # Selettore visivo di Schermi e Singole Finestre
│           └── SettingsView.swift      # Finestra impostazioni (Cartella di salvataggio, Codec)
```

---

## 🔒 Entitlements & Permissions (`Info.plist` & `.entitlements`)

### 1. `Info.plist`
- `LSUIElement = true`: garantisce che l'applicazione risieda unicamente nella barra dei menu (nessuna icona nel Dock, nessun focus rubato in Cmd+Tab).
- `NSScreenCaptureUsageDescription`: messaggio di sistema richiesto per catturare display e finestre (`CGRequestScreenCaptureAccess`).
- `NSMicrophoneUsageDescription`: richiesta esplicita di accesso al microfono per registrare il commento audio.

### 2. `RecDrive.entitlements`
- `com.apple.security.device.audio-input`: accesso hardware all'input microfonico.
- `com.apple.security.assets.movies.read-write`: permessi di scrittura nella cartella filmati utente (`~/Movies/RecDrive/`).
- `com.apple.security.files.user-selected.read-write`: permessi di accesso per cartelle personalizzate scelte dall'utente.

---

## ⚡ Componenti Chiave del Motore

### 1. `ScreenCaptureManager.swift` (`ScreenCaptureKit`)
- Interroga `SCShareableContent` per enumerare schermi (`SCDisplay`) e finestre applicative aperte (`SCWindow`), escludendo dock e barre di sistema.
- Inizializza `SCStream` configurato a 60 FPS o 30 FPS con pixel format nativo `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (NV12).
- Filtra accuratamente gli stati dei frame (`SCFrameStatus.complete`) e la presenza del pixel buffer per prevenire errori nel multiplexer AVAssetWriter.

### 2. `MediaWriter.swift` (`AVAssetWriter` Hardware Encoding)
- Scrive file `.mp4` direttamente su disco senza creare file temporanei di rete o blocchi alla finalizzazione.
- Video: Compressione hardware **HEVC / H.265** (o H.264) tramite Apple Silicon `VideoToolbox`.
- Audio: Compressione **AAC Stereo a 48 kHz** (192 kbps per l'audio di sistema, 128 kbps per la voce microfonica).
- Sincronizzazione: sincronizza i timestamp di presentazione (`CMSampleBufferGetPresentationTimeStamp`), avviando la sessione al primo frame video valido ed evitando drift.

### 3. `LocalStorageManager.swift`
- Genera i file con formato: `[TitoloLezione]_YYYY-MM-dd_HH-mm-ss.mp4`.
- Pulisce automaticamente caratteri non consentiti nei percorsi di file.
- Permette di reindirizzare le registrazioni direttamente verso la cartella sincronizzata di Google Drive o qualsiasi altro servizio cloud.

---

## 🛠️ Istruzioni di Build ed Esecuzione

### Requisiti di Sistema
- Mac con **Apple Silicon (M1/M2/M3/M4)** o Intel.
- **macOS 13.0 Ventura** o successivo.
- Swift 5.9+ / Xcode Command Line Tools.

### Compilazione e Packaging del Bundle .app

Esegui lo script dedicato dalla directory del progetto:

```bash
./scripts/bundle_app.sh
```

Lo script:
1. Compila il binario in modalità release (`-O`).
2. Crea la struttura `build/RecDrive.app/Contents/MacOS`.
3. Inserisce `Info.plist`.
4. Firma ad-hoc il bundle con gli entitlements definiti.

### Avvio dell'Applicazione

Puoi aprire direttamente l'app creata:

```bash
open build/RecDrive.app
```
