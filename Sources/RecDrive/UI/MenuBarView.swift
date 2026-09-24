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
    @ObservedObject var oauthManager = OAuthManager.shared
    @StateObject private var uiState = MenuBarUIState()
    
    var body: some View {
        VStack(spacing: 14) {
            // Header: Title and Status
            headerView
            
            Divider()
            
            // Primary Recording Action
            recordButtonSection
            
            Divider()
            
            // Source Selection
            sourceSelectionSection
            
            // Audio Controls
            audioControlsSection
            
            // Upload Banner / Link
            if let link = appState.lastUploadedFileLink {
                recentUploadBanner(link: link)
            }
            
            Divider()
            
            // Footer: Settings & Quit
            footerSection
        }
        .padding(14)
        .frame(width: 310)
        .sheet(isPresented: $uiState.showingSourcePicker) {
            SourcePickerView()
        }
        .sheet(isPresented: $uiState.showingSettings) {
            SettingsView()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "record.circle")
                .foregroundColor(.red)
                .font(.system(size: 16, weight: .bold))
            Text("RecDrive")
                .font(.headline)
            
            Spacer()
            
            if appState.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(formatDuration(appState.recordingDuration))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.red)
                }
            } else if appState.isUploading {
                HStack(spacing: 6) {
                    ProgressView(value: appState.uploadProgressFraction)
                        .frame(width: 50)
                    Text("\(Int(appState.uploadProgressFraction * 100))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            } else {
                Text(oauthManager.isAuthenticated ? "Connected" : "Offline")
                    .font(.caption2)
                    .foregroundColor(oauthManager.isAuthenticated ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
            }
        }
    }
    
    // MARK: - Record Button Section
    
    private var recordButtonSection: some View {
        Button {
            Task {
                if appState.isRecording {
                    await appState.stopRecording()
                } else {
                    await appState.startRecording()
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: appState.isRecording ? "stop.fill" : "record.circle.fill")
                    .font(.system(size: 20))
                Text(appState.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(.white)
            .background(appState.isRecording ? Color.red : Color.accentColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Source Selection
    
    private var sourceSelectionSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Capture Source")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(appState.selectedTargetName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Change...") {
                uiState.showingSourcePicker = true
            }
            .font(.caption)
            .disabled(appState.isRecording)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }
    
    // MARK: - Audio Controls
    
    private var audioControlsSection: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $preferences.captureSystemAudio) {
                Label("System", systemImage: "speaker.wave.2")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .disabled(appState.isRecording)
            
            Spacer()
            
            Toggle(isOn: $preferences.captureMicrophone) {
                Label("Mic", systemImage: "mic")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .disabled(appState.isRecording)
        }
    }
    
    // MARK: - Recent Upload Banner
    
    private func recentUploadBanner(link: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Uploaded to Google Drive")
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            HStack {
                Button("Copy Link") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(link, forType: .string)
                }
                .font(.caption)
                
                Button("Open in Browser") {
                    if let url = URL(string: link) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color.green.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        HStack {
            Button {
                uiState.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Preferences")
            
            Spacer()
            
            if let msg = appState.statusMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Quit") {
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
