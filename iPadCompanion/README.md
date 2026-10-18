# RecDrive Companion per iPad (Screen Mirroring & Apple Pencil Overlay)

Companion app nativa per iPadOS (16.0+) che trasforma l'iPad in una tavoletta grafica wireless o via cavo per **RecDrive**. Permette di visualizzare lo schermo del Mac in tempo reale (streaming JPEG 30 FPS scalato) e disegnare direttamente sull'overlay di registrazione utilizzando **Apple Pencil** con feedback a latenza zero.

---

## 🏗️ Architettura del Modulo

```
iPadCompanion/
├── SharedProtocol/
│   └── CompanionProtocol.swift       # Framing TCP [5 byte header] e modelli PencilDrawEvent
├── MacBridge/
│   ├── iPadBridgeServer.swift        # NWListener Bonjour _recdrive-pad._tcp su Mac
│   ├── ScreenMirrorStreamer.swift    # ScreenCaptureKit JPEG streamer (30 FPS, max 1280px)
│   └── RecDriveOverlayAdapter.swift  # Iniezione nativa dei tratti sull'overlay RecDrive
├── RecDrivePadApp/
│   ├── App/
│   │   └── RecDrivePadApp.swift      # Entry point SwiftUI per iPadOS
│   ├── Networking/
│   │   └── MacConnectionClient.swift # NWBrowser Bonjour e ricevitore streaming
│   ├── Views/
│   │   ├── PencilCanvasView.swift    # Cattura Apple Pencil 120Hz & disegno immediato
│   │   └── MirrorWorkspaceView.swift # Render video aspect-fit 1:1 e HUD toolbar
│   ├── Info.plist                    # Permessi Bonjour e Rete Locale
│   └── project.yml                   # Configurazione per XcodeGen
└── README.md
```

---

## 🚀 I 3 Passaggi di Installazione e Avvio

### Passaggio 1: Integrare il Modulo Bridge nel Progetto Mac RecDrive

I file di ponte Mac vivono in `iPadCompanion/MacBridge/` e `iPadCompanion/SharedProtocol/`:

- **Se compili con lo script di build / SPM (`bundle_app.sh`)**:
  I file sono già mappati in `Sources/RecDrive/iPadBridge` e il server bridge Bonjour viene avviato automaticamente in `AppDelegate.applicationDidFinishLaunching(_:)`:
  ```swift
  iPadBridgeServer.shared.start()
  ```
- **Se utilizzi un progetto Xcode nativo (.xcodeproj) per il Mac**:
  1. Trascina le cartelle `iPadCompanion/SharedProtocol` e `iPadCompanion/MacBridge` nella finestra di progetto di Xcode.
  2. Assicurati che sia selezionata l'opzione **"Create folder references"** (o "Create groups") e che sia spuntato il target **RecDrive**.
  3. Verifica che nei Build Phases -> *Link Binary with Libraries* siano presenti: `Network.framework`, `ScreenCaptureKit.framework`, `CoreImage.framework`.

---

### Passaggio 2: Generare il Progetto Xcode per l'App iPad (RecDrivePad)

L'applicazione iPad è configurata tramite [XcodeGen](https://github.com/yonaskolb/XcodeGen) in modo dichiarativo e pulito:

```bash
# Entra nella cartella dell'app iPad
cd iPadCompanion/RecDrivePadApp

# Genera il file RecDrivePad.xcodeproj
xcodegen generate
```

> Se non hai `xcodegen` installato, puoi installarlo rapidamente via Homebrew:
> `brew install xcodegen`

---

### Passaggio 3: Compilazione ed Esecuzione sull'iPad

1. Apri il progetto generato in Xcode:
   ```bash
   open iPadCompanion/RecDrivePadApp/RecDrivePad.xcodeproj
   ```
2. Collega il tuo iPad al Mac (tramite cavo USB-C / Lightning oppure assicurati che entrambi siano connessi alla stessa rete Wi-Fi).
3. Seleziona il tuo iPad fisico come dispositivo di destinazione (Target: **RecDrivePad** -> **Tuo iPad**).
4. Nel tab **Signing & Capabilities**, seleziona il tuo *Personal Team* Apple Developer.
5. Premi **Run (⌘R)** per installare e avviare l'app sull'iPad.
6. Avvia **RecDrive** sul Mac: l'iPad rileverà istantaneamente il Mac via Bonjour (`_recdrive-pad._tcp`), visualizzerà lo schermo con corrispondenza 1:1 dei pixel e potrai disegnare con la tua Apple Pencil!

---

## ⚙️ Dettagli Tecnici

- **Trasporto di Rete**: `Network.framework` (`NWListener` su Mac, `NWBrowser` + `NWConnection` su iPad) con supporto `includePeerToPeer = true` per connessione diretta wireless ad alte prestazioni o tramite cavo USB (Apple Virtual Network).
- **Framing a Basso Overhead**: Header fisso di 5 byte:
  - `Byte 0` (`UInt8`): Tipo messaggio (`0x01` = VideoFrame JPEG dal Mac, `0x02` = PencilEvent JSON dall'iPad).
  - `Byte 1..4` (`UInt32` big-endian): Lunghezza in byte del payload.
- **Screen Mirroring Efficente**: ScreenCaptureKit a 30 FPS scalato a max 1280px maintaining aspect ratio con compressione JPEG (`CIContext`, qualità `0.65`). Lo streaming si attiva solo a client connesso e si interrompe istantaneamente alla disconnessione.
- **Iniezione Tratti Non Invasiva**: L'adapter converte le coordinate normalizzate `0.0...1.0` nelle coordinate native dell'overlay `AnnotationCanvasView` (`isFlipped = true`) senza muovere il puntatore hardware del mouse di macOS.
