# RecDrive 🎥☁️

**RecDrive** è un'applicazione nativa per macOS (supporto macOS 13+) progettata per essere ultra-leggera, performante e priva di qualsiasi overhead di sistema. Funziona esclusivamente come icona nella Menu Bar (`LSUIElement = true`), senza icona nel Dock o finestre persistenti, registrando lo schermo e l'audio con accelerazione hardware Apple Silicon e caricando i video in background su Google Drive tramite sessioni resumable conformi alle REST API v3.

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
│   └── RecDrive.entitlements           # Entitlements di sicurezza (Network, Mic, Movies)
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
│       ├── Drive/
│       │   ├── DriveService.swift      # Upload resumable a chunk (2MB) Google Drive v3
│       │   ├── OAuthManager.swift      # Google OAuth 2.0 PKCE con loopback server locale
│       │   ├── AuthConfig.swift        # Configurazione endpoint Google e scope least-privilege
│       │   └── DriveModels.swift       # Modelli JSON (DriveFile, Tokens, Progress)
│       ├── Storage/
│       │   ├── KeychainHelper.swift    # Wrapper sicuro per macOS Keychain Services
│       │   ├── PreferencesStorage.swift# Persistenza opzioni con UserDefaults
│       │   └── LocalStorageManager.swift# Gestione file disco locale (~/Movies/RecDrive/)
│       └── UI/
│           ├── MenuBarView.swift       # Popover SwiftUI principale per la Menu Bar
│           ├── StatusItemController.swift # Gestione dinamica NSStatusItem con animazioni
│           ├── SourcePickerView.swift  # Selettore visivo di Schermi e Singole Finestre
│           └── SettingsView.swift      # Finestra preferenze (Account, Cartella, Codec)
└── docs/
    └── plans/
        ├── task.md                     # Tabella di tracciamento avanzamento
        ├── 2026-09-24-recdrive-design.md
        └── 2026-09-24-recdrive-implementation.md
```

---

## 🔒 Entitlements & Permissions (`Info.plist` & `.entitlements`)

### 1. `Info.plist`
- `LSUIElement = true`: garantisce che l'applicazione risieda unicamente nella barra dei menu (nessuna icona nel Dock, nessun focus rubato in Cmd+Tab).
- `NSScreenCaptureUsageDescription`: messaggio di sistema richiesto per catturare display e finestre (`CGRequestScreenCaptureAccess`).
- `NSMicrophoneUsageDescription`: richiesta esplicita di accesso al microfono per registrare il commento audio.

### 2. `RecDrive.entitlements`
- `com.apple.security.network.client`: connessioni in uscita verso le API di Google Drive.
- `com.apple.security.network.server`: apertura socket loopback locale (`127.0.0.1`) per ricevere il codice di redirect OAuth 2.0.
- `com.apple.security.device.audio-input`: accesso hardware all'input microfonico.
- `com.apple.security.assets.movies.read-write`: permessi di scrittura nella cartella filmati utente (`~/Movies/RecDrive/`).

---

## ⚡ Componenti Chiave del Motore

### 1. `ScreenCaptureManager.swift` (`ScreenCaptureKit`)
- Interroga `SCShareableContent` per enumerare schermi (`SCDisplay`) e finestre applicative aperte (`SCWindow`), escludendo dock e barre di sistema.
- Inizializza `SCStream` configurato a 60 FPS o 30 FPS con pixel format nativo `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (NV12).
- Gestisce i callback `SCStreamOutput` smistando i sample buffer video (`.screen`), audio di sistema (`.audio`) e microfono (`.microphone`).

### 2. `MediaWriter.swift` (`AVAssetWriter` Hardware Encoding)
- Scrive file `.mp4` non bloccanti su disco con pipeline asincrona su code seriali GCD.
- Video: Compressione hardware **HEVC / H.265** (o H.264) tramite Apple Silicon `VideoToolbox`.
- Audio: Compressione **AAC Stereo a 48 kHz** (192 kbps per l'audio di sistema, 128 kbps per la traccia vocale del microfono).
- Sincronizzazione: sincronizza i sample buffer di presentazione (`CMSampleBufferGetPresentationTimeStamp`), avviando la sessione al primo frame video valido ed evitando drift o sfasamento labiale.

### 3. `DriveService.swift` (Google Drive Resumable Upload Engine)
- Conforme allo standard RFC e documentazione Google Drive REST API v3:
  1. Avvia la sessione con `POST https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable`.
  2. Cattura l'header di risposta `Location` (Upload Session URI).
  3. Trasferisce il file a chunk di **2 MB** (multipli esatti di 256 KB) con header `Content-Range: bytes START-END/TOTAL`.
  4. In caso di disconnessione di rete, interroga lo stato parziale con `Content-Range: bytes */TOTAL`, legge l'header `Range: bytes=0-LAST_BYTE` e riprende automaticamente senza ricominciare da zero.
- Automazioni post-upload:
  - Copia automatica negli appunti del link web condivisibile (`https://drive.google.com/file/d/<id>/view`).
  - Eliminazione opzionale del file locale su disco per liberare spazio.

### 4. `OAuthManager.swift` & `KeychainHelper.swift`
- Protocollo **OAuth 2.0 con standard PKCE** (RFC 7636):
  - Generazione crittografica di `code_verifier` casuale (32 byte crittografici) e `code_challenge` SHA-256.
  - Server HTTP temporaneo su socket locale effimero (`127.0.0.1:<port>/oauth2callback`) via `Network.framework` (senza dipendenze web esterne).
  - Memorizzazione sicura del Refresh Token nel **Keychain di macOS** con classe `kSecClassGenericPassword`.
  - Rinnovo automatico e trasparente dell'Access Token scaduto prima di ogni chiamata di upload.

---

## 🛠️ Istruzioni di Build ed Esecuzione

### A. Packaging 1-Click in App Bundle macOS (Consigliato)
Esegui lo script incluso per compilare la versione Release ottimizzata e creare il bundle nativo `RecDrive.app`:

```bash
./scripts/bundle_app.sh
```

L'applicazione verrà creata in:
```
build/RecDrive.app
```
Per avviarla:
```bash
open build/RecDrive.app
```

### B. Compilazione via Swift CLI (`swift build`)
Puoi compilare direttamente da terminale usando Swift Package Manager:

```bash
swift build -c release
```

### C. Apertura in Xcode IDE
Puoi aprire il progetto direttamente in Xcode:
1. Apri Xcode.
2. Seleziona **File > Open...** e scegli la cartella `_SCREEN_CAPTURER` (o fai doppio clic su `Package.swift`).
3. Xcode caricherà automaticamente lo schema **RecDrive**.
4. Premi **Cmd + R** per compilare ed eseguire.

---

## ⚙️ Configurazione Credenziali Google Drive

RecDrive supporta il **doppio canale** di configurazione OAuth:

1. **Tramite UI Preferenze (Senza Ricompilare)**:
   - Clicca sull'icona RecDrive nella Menu Bar.
   - Clicca sull'icona a forma di ingranaggio in basso (Preferenze).
   - Vai nella scheda **Google Drive** ed espandi **Configure Google Cloud Client ID**.
   - Inserisci il tuo **Client ID** e **Client Secret** generati da [Google Cloud Console](https://console.cloud.google.com/).

2. **Tramite Codice Sorgente**:
   - Apri `Sources/RecDrive/Drive/AuthConfig.swift`.
   - Modifica `defaultClientId` e `defaultClientSecret` con le tue credenziali prima della compilazione.
