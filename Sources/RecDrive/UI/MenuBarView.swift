import SwiftUI

@MainActor
final class MenuBarUIState: ObservableObject {
    @Published var showingSourcePicker = false
    @Published var showingSettings = false
}

/// Main popover view displayed from the macOS menu bar status item.
struct MenuBarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var preferences = PreferencesStorage.shared
    @ObservedObject var annotationManager = AnnotationManager.shared
    @StateObject private var uiState = MenuBarUIState()
    
    var body: some View {
        VStack(spacing: 12) {
            // Header: Title and Stopwatch
            headerView
            
            Divider()
            
            // Lesson Title Field
            lessonTitleSection
            
            // Primary Recording Action
            recordButtonSection
            
            // Live Screen Annotation Quick Action
            annotationSection
            
            Divider()
            
            // Source Selection
            sourceSelectionSection
            
            // Audio Controls
            audioControlsSection
            
            // Saved Recording Banner / Actions
            if let lastURL = appState.lastRecordedURL {
                recentSavedBanner(url: lastURL)
            }
            
            // Screen Capture Permission Warning Banner
            if !appState.hasScreenCapturePermission {
                permissionWarningBanner
            }
            
            Divider()
            
            // Footer: Settings, Folder, Quit
            footerSection
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            appState.checkScreenCapturePermission()
        }
        .sheet(isPresented: $uiState.showingSourcePicker) {
            SourcePickerView()
        }
        .sheet(isPresented: $uiState.showingSettings) {
            SettingsView()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 8) {
            if let icon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "record.circle")
                    .foregroundColor(.red)
                    .font(.system(size: 16, weight: .bold))
            }
            Text("RecDrive")
                .font(.headline)
            
            Spacer()
            
            if appState.isFinishing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Salvataggio...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.orange)
                }
            } else if appState.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(formatDuration(appState.recordingDuration))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.red)
                }
            } else {
                Text("Pronto")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
            }
        }
    }
    
    // MARK: - Lesson Title Section
    
    private var lessonTitleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Titolo della Lezione:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("es. Algoritmi Lezione 1", text: $appState.lessonTitle)
                    .textFieldStyle(.plain)
                    .disabled(appState.isRecording || appState.isFinishing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Record Button Section
    
    private var recordButtonSection: some View {
        Button {
            Task {
                if appState.isFinishing { return }
                if appState.isRecording {
                    await appState.stopRecording()
                } else {
                    await appState.startRecording()
                }
            }
        } label: {
            HStack(spacing: 10) {
                if appState.isFinishing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Salvataggio in corso...")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Image(systemName: appState.isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.system(size: 18))
                    Text(appState.isRecording ? "Ferma Registrazione" : "Avvia Registrazione")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(.white)
            .background(appState.isFinishing ? Color.gray : (appState.isRecording ? Color.red : Color.accentColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(appState.isFinishing)
    }
    
    // MARK: - Annotation Quick Action
    
    private var annotationSection: some View {
        Button {
            annotationManager.toggleAnnotation()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: annotationManager.isAnnotationActive ? "pencil.slash" : "pencil.and.outline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(annotationManager.isAnnotationActive ? .orange : .accentColor)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(annotationManager.isAnnotationActive ? "Ferma Annotazione" : "Disegna sullo Schermo")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Text(annotationManager.isAnnotationActive ? "Disegno a mano libera attivo" : "Scrivi o disegna a mano libera")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(preferences.annotationHotKeyDisplayString)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
            }
            .padding(8)
            .background(annotationManager.isAnnotationActive ? Color.orange.opacity(0.12) : Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(annotationManager.isAnnotationActive ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Source Selection
    
    private var sourceSelectionSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sorgente di cattura")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(appState.selectedTargetName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Cambia...") {
                uiState.showingSourcePicker = true
            }
            .font(.caption)
            .disabled(appState.isRecording || appState.isFinishing)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }
    
    // MARK: - Audio Controls
    
    private var audioControlsSection: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $preferences.captureSystemAudio) {
                Label("Audio Sistema", systemImage: "speaker.wave.2")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .disabled(appState.isRecording || appState.isFinishing)
            
            Spacer()
            
            Toggle(isOn: $preferences.captureMicrophone) {
                Label("Microfono", systemImage: "mic")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .disabled(appState.isRecording || appState.isFinishing)
        }
    }
    
    // MARK: - Saved File Banner
    
    private func recentSavedBanner(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Registrazione completata")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(url.lastPathComponent)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            HStack(spacing: 8) {
                Button("Mostra nel Finder") {
                    appState.revealLastRecordingInFinder()
                }
                .font(.caption)
                
                Button("Apri video") {
                    appState.openLastRecordingFile()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Permission Warning Banner
    
    private var permissionWarningBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Permesso Schermo Necessario")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
            }
            
            Text("Se hai già concesso il permesso in Impostazioni, premi 'Riavvia App' per renderlo attivo.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 8) {
                Button("Apri Impostazioni") {
                    appState.openSystemSettingsScreenCapture()
                }
                .font(.caption)
                
                Button("Riavvia App") {
                    appState.restartApp()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(6)
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        HStack {
            Button {
                uiState.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Impostazioni")
            
            Button {
                appState.openRecordingsFolder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Apri cartella registrazioni")
            
            Spacer()
            
            if let msg = appState.statusMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Esci") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
