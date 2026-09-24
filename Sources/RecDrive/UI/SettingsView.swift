import SwiftUI
import AppKit

/// Preferences and settings window for RecDrive.
struct SettingsView: View {
    @ObservedObject var preferences = PreferencesStorage.shared
    
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
        }
        .frame(width: 480, height: 340)
        .padding()
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
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
}
