# Android Remote Companion & Mac Receiver

Sistema autonomo di controllo remoto per macOS composto da:
1. **MacReceiver**: Applicazione `.app` per macOS (in Swift nativo) che si posiziona nella barra dei menu (Menu Bar), riceve comandi via TCP ed emula input tastiera/mouse (`CGEvent`).
2. **AndroidApp**: Applicazione Android moderna (Kotlin, Jetpack Compose, Material 3) con interfaccia ottimizzata per il controllo di presentazioni (Keynote, PowerPoint), trackpad virtuale, tasti multimediali e scorciatoie di sistema.

> [!NOTE]
> Questo modulo è **completamente indipendente** dall'applicazione principale RecDrive e non ne modifica in alcun modo il codice o le funzionalità.

---

## 📁 Struttura

```
AndroidCompanion/
├── MacReceiver/               # Ricevitore nativo macOS (.app)
│   ├── Package.swift
│   ├── build.sh               # Script per compilare MacReceiver.app
│   ├── MacReceiver.app        # Bundle applicazione pronto all'uso (doppio clic)
│   ├── bin/
│   │   ├── MacReceiver.app    # Bundle macOS
│   │   └── MacReceiver        # Eseguibile binario
│   ├── Resources/
│   │   ├── Info.plist         # Configurazione bundle (LSUIElement, permessi)
│   │   └── AppIcon.icns       # Icona applicazione
│   └── Sources/MacReceiver/
│       ├── main.swift         # AppKit Menu Bar app & UI
│       ├── InputSynthesizer.swift  # Sintesi eventi tastiera e mouse CGEvent
│       ├── RemoteServer.swift # Server TCP (Network.framework) + Bonjour NSD
│       └── RemoteProtocol.swift    # Definizione protocollo JSON
│
└── AndroidApp/                # Applicazione Android
    ├── build.gradle.kts
    ├── settings.gradle.kts
    ├── gradlew
    └── app/
        └── src/main/java/com/recdrive/remote/
            ├── MainActivity.kt
            ├── network/       # Connessione TCP e Bonjour Discovery
            └── ui/            # UI Compose: Presentazione, Trackpad, Scorciatoie
```

---

## 🖥️ 1. Mac Receiver (macOS)

### Requisiti
- macOS 13.0 o superiore
- **Permesso di Accessibilità**: Richiesto da macOS per consentire la sintesi dei tasti e del mouse via `CGEvent`. Al primo avvio, l'applicazione chiederà l'autorizzazione o puoi abilitarla in:
  *Impostazioni di Sistema → Privacy e Sicurezza → Accessibilità → Abilita MacReceiver.*

### Compilazione ed Esecuzione
L'applicazione è già compilata e pronta all'uso come applicazione macOS standard (`.app`):
- Puoi avviarla direttamente con un **doppio clic** su `AndroidCompanion/MacReceiver/MacReceiver.app` nel Finder.
- Oppure da terminale:
  ```bash
  open AndroidCompanion/MacReceiver/MacReceiver.app
  ```

Se desideri ricompilare il bundle `.app`:
```bash
cd AndroidCompanion/MacReceiver
./build.sh
```

### Funzionalità nel Menu Bar
- **Icona nel menu bar**: Mostra lo stato del server (es. `Mac Remote: In ascolto su 19850`).
- **Indirizzo IP visualizzato**: Mostra l'IP locale (es. `192.168.1.50`) con pulsante per copiarlo negli appunti con un clic.
- **Client connessi**: Contatore in tempo reale dei dispositivi Android collegati.
- **Test rapido**: Scorciatoie nel menu per testare Next Slide, Prev Slide o verificare i permessi di accessibilità.
- **Bonjour**: Il server si annuncia automaticamente sulla rete locale con il servizio `_recdrive-remote._tcp`.

---

## 📱 2. Android App

### Requisiti
- Dispositivo o emulatore Android con **Android 8.0 (API 26)** o superiore.
- Mac e dispositivo Android connessi alla **stessa rete Wi-Fi** (oppure collegati via USB con ADB forward).

### Compilazione APK
Dalla cartella `AndroidCompanion/AndroidApp`:

```bash
./gradlew assembleDebug
```
L'APK generato si troverà in:
`AndroidCompanion/AndroidApp/app/build/outputs/apk/debug/app-debug.apk`

Per installarlo direttamente su un dispositivo collegato:
```bash
./gradlew installDebug
```

Oppure apri semplicemente la cartella `AndroidCompanion/AndroidApp` in **Android Studio**.

### Connessione al Mac
All'apertura dell'app, tocca l'indicatore di connessione o il pulsante di configurazione in alto a destra:
1. **Ricerca Automatica (Bonjour / NSD)**: Se il Mac e l'Android sono sulla stessa rete Wi-Fi, il Mac apparirà automaticamente nella lista dei dispositivi trovati. Toccalo per connetterti.
2. **Connessione Manuale via IP**: Inserisci l'indirizzo IP mostrato nella barra dei menu del Mac (porta predefinita `19850`) e premi *Connetti*.
3. **Connessione cablata USB (senza Wi-Fi)**:
   Se colleghi il telefono via cavo USB con Debug USB attivo, puoi eseguire sul Mac:
   ```bash
   adb forward tcp:19850 tcp:19850
   ```
   E sull'app Android connetterti all'IP `127.0.0.1` (porta 19850).

---

## 🎛️ Modalità dell'App Android

### 1. Presentazione (Keynote & PowerPoint)
Ottimizzata per l'uso a una mano con ampie aree touch:
- **Slide Successiva** (tasto freccia destra / Spazio) con feedback aptico.
- **Slide Precedente** (tasto freccia sinistra).
- **Avvia Presentazione** (⌥⌘P per Keynote / F5 per PowerPoint).
- **Fine Presentazione** (tasto Esc).
- **Schermo Nero (B)**: Oscura lo schermo durante la presentazione per attirare l'attenzione sul relatore.
- **Schermo Bianco (W)**: Sbianca lo schermo proiettato.

### 2. Trackpad Virtuale
- **Movimento cursore**: Fai scorrere un dito sul trackpad.
- **Click sinistro**: Tocca rapidamente con un dito.
- **Click destro**: Tocca con due dita oppure usa il pulsante dedicato "Click Destro".
- **Scorrimento (Scroll)**: Trascina con due dita verso l'alto o verso il basso.

### 3. Scorciatoie & Multimediale
- **Volume & Media**: Volume Su, Volume Giù, Mute, Play/Pausa, Traccia precedente/successiva.
- **Gestione Finestre & Spazi**: Spazio a sinistra/destra (Ctrl+← / Ctrl+→), Mission Control (Ctrl+↑), Cambio applicazione (Cmd+Tab).
- **Invio Testo**: Permette di digitare una stringa o URL sullo smartphone e inviarla direttamente come battitura testo nel campo attivo sul Mac.
- **Combinazioni personalizzate**: Invio di combinazioni tasto modificatore (Cmd, Option, Ctrl, Shift) + tasto.

---

## 🔒 Sicurezza e Privacy
- La comunicazione avviene solo all'interno della rete locale (LAN/Wi-Fi) o su loopback USB.
- Nessun dato viene trasmesso a server esterni o cloud.
- Il Mac richiede autorizzazione esplicita di Accessibilità per motivi di sicurezza del sistema operativo.
