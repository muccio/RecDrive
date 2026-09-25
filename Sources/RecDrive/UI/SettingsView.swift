import SwiftUI
import AppKit

@MainActor
final class SettingsUIState: ObservableObject {
    @Published var isRecordingShortcut: Bool = false
    var keyMonitor: Any? = nil
}

/// Preferences and settings window for RecDrive.
struct SettingsView: View {
    @ObservedObject var preferences = PreferencesStorage.shared
    @StateObject private var uiState = SettingsUIState()
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("Generale", systemImage: "gearshape")
                }
            
            captureTab
                .tabItem {
                    Label("Cattura & Audio", systemImage: "video")
                }
            
            annotationTab
                .tabItem {
                    Label("Annotazione", systemImage: "pencil.and.outline")
                }
        }
        .frame(width: 520, height: 400)
        .padding()
        .onDisappear {
            stopListeningForShortcut()
        }
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    if let appIcon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("RecDrive")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                        }
                        Text("Registratore schermo e annotazione live con sincronizzazione cloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            
            Section(header: Text("Cartella di Salvataggio").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("I video registrati verranno salvati in:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(LocalStorageManager.shared.recordingsDirectory.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    
                    HStack(spacing: 10) {
                        Button("Mostra nel Finder") {
                            let url = LocalStorageManager.shared.recordingsDirectory
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                        
                        Button("Cambia cartella...") {
                            selectCustomFolder()
                        }
                        
                        if !preferences.customRecordingsPath.isEmpty {
                            Button("Ripristina predefinita") {
                                preferences.customRecordingsPath = ""
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("💡 Suggerimento: Seleziona qui la cartella sincronizzata da Google Drive, Dropbox o iCloud per caricare automaticamente le lezioni.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            Section(header: Text("Formato Nome File").font(.headline)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nome generato: [TitoloLezione]_YYYY-MM-dd_HH-mm-ss.mp4")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("Se il campo titolo viene lasciato vuoto, verrà usato il prefisso 'Lezione'.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Capture Tab
    
    private var captureTab: some View {
        Form {
            Section(header: Text("Codifica Video Hardware").font(.headline)) {
                Picker("Codec Video:", selection: $preferences.videoCodec) {
                    Text("HEVC / H.265 (Consigliato - Apple Silicon)").tag("hevc")
                    Text("H.264 (Massima compatibilità)").tag("h264")
                }
                
                Picker("Frequenza fotogrammi:", selection: $preferences.targetFrameRate) {
                    Text("60 FPS (Fluidità massima)").tag(60)
                    Text("30 FPS (Risparmio spazio)").tag(30)
                }
            }
            
            Section(header: Text("Ingressi Audio Predefiniti").font(.headline)) {
                Toggle("Cattura Audio di Sistema", isOn: $preferences.captureSystemAudio)
                Toggle("Cattura Microfono Esterno", isOn: $preferences.captureMicrophone)
            }
        }
        .padding()
    }
    
    private func selectCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Seleziona cartella"
        panel.message = "Scegli la cartella in cui salvare le registrazioni dello schermo"
        
        if panel.runModal() == .OK, let selectedURL = panel.url {
            preferences.customRecordingsPath = selectedURL.path
        }
    }
    
    // MARK: - Annotation Tab
    
    private var annotationTab: some View {
        Form {
            Section(header: Text("Scorciatoia Globale di Attivazione").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Abilita scorciatoia globale per disegnare sullo schermo", isOn: $preferences.annotationHotKeyEnabled)
                        .onChange(of: preferences.annotationHotKeyEnabled) { enabled in
                            if enabled {
                                HotKeyManager.shared.registerFromPreferences()
                            } else {
                                HotKeyManager.shared.unregisterAnnotationHotKey()
                            }
                        }
                    
                    HStack(spacing: 12) {
                        Text("Scorciatoia:")
                            .font(.subheadline)
                        
                        Text(uiState.isRecordingShortcut ? "Premi i tasti..." : preferences.annotationHotKeyDisplayString)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(uiState.isRecordingShortcut ? .orange : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(uiState.isRecordingShortcut ? Color.orange.opacity(0.15) : Color.primary.opacity(0.06))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(uiState.isRecordingShortcut ? Color.orange : Color.primary.opacity(0.12), lineWidth: 1)
                            )
                        
                        if uiState.isRecordingShortcut {
                            Button("Annulla") {
                                stopListeningForShortcut()
                            }
                            .font(.caption)
                        } else {
                            Button("Registra nuova scorciatoia...") {
                                startListeningForShortcut()
                            }
                            .font(.caption)
                            .disabled(!preferences.annotationHotKeyEnabled)
                            
                            Button("Ripristina (⌘⇧D)") {
                                resetDefaultShortcut()
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    if uiState.isRecordingShortcut {
                        Text("💡 Premi una combinazione con Command (⌘), Option (⌥) o Control (⌃) e un tasto (es. ⌃⌥D, ⌘⇧A). Premi Esc per annullare.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else {
                        Text("La scorciatoia funziona ovunque su macOS, anche durante la registrazione o con altre applicazioni aperte.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Comandi Rapidi durante il Disegno").font(.headline)) {
                VStack(alignment: .leading, spacing: 6) {
                    shortcutGuideRow(key: "Esc", desc: "Chiudi / Esci dalla modalità annotazione")
                    shortcutGuideRow(key: "⌘ Z", desc: "Annulla ultimo tratto (Undo)")
                    shortcutGuideRow(key: "C", desc: "Pulisci tutti i tratti disegnati")
                    shortcutGuideRow(key: "P", desc: "Strumento Penna (tratto solido)")
                    shortcutGuideRow(key: "H", desc: "Strumento Evidenziatore (tratto fluorescente)")
                    shortcutGuideRow(key: "T", desc: "Strumento Testo (apri casella di testo sul puntatore)")
                    shortcutGuideRow(key: "E", desc: "Strumento Gomma (rimuovi tratti e testo)")
                    shortcutGuideRow(key: "V", desc: "Strumento Cursore (interagisci con le finestre sottostanti)")
                }
            }
        }
        .padding()
    }
    
    private func shortcutGuideRow(key: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .cornerRadius(4)
                .frame(width: 44, alignment: .center)
            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Shortcut Recording
    
    private func startListeningForShortcut() {
        stopListeningForShortcut()
        uiState.isRecordingShortcut = true
        
        uiState.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc key cancels recording
            if event.keyCode == 53 {
                self.stopListeningForShortcut()
                return nil
            }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifiers = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
            
            if hasModifiers {
                let carbonMods = HotKeyManager.carbonModifiers(from: flags)
                let keyCode = Int(event.keyCode)
                
                preferences.annotationHotKeyKeyCode = keyCode
                preferences.annotationHotKeyModifiers = carbonMods
                HotKeyManager.shared.registerAnnotationHotKey(keyCode: keyCode, modifiers: carbonMods)
                
                self.stopListeningForShortcut()
                return nil
            }
            return event
        }
    }
    
    private func stopListeningForShortcut() {
        if let monitor = uiState.keyMonitor {
            NSEvent.removeMonitor(monitor)
            uiState.keyMonitor = nil
        }
        uiState.isRecordingShortcut = false
    }
    
    private func resetDefaultShortcut() {
        stopListeningForShortcut()
        preferences.annotationHotKeyKeyCode = 2 // kVK_ANSI_D
        preferences.annotationHotKeyModifiers = 768 // cmdKey | shiftKey
        preferences.annotationHotKeyEnabled = true
        HotKeyManager.shared.registerFromPreferences()
    }
}
