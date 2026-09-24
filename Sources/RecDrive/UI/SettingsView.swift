import SwiftUI

@MainActor
final class SettingsUIState: ObservableObject {
    @Published var availableFolders: [DriveFolder] = []
    @Published var isLoadingFolders: Bool = false
    @Published var showingAdvancedAuth: Bool = false
}

/// Preferences and settings window for RecDrive.
struct SettingsView: View {
    @ObservedObject var preferences = PreferencesStorage.shared
    @ObservedObject var oauthManager = OAuthManager.shared
    @ObservedObject var driveService = DriveService.shared
    @StateObject private var uiState = SettingsUIState()
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            
            driveTab
                .tabItem {
                    Label("Google Drive", systemImage: "externaldrive.badge.icloud")
                }
            
            captureTab
                .tabItem {
                    Label("Capture & Audio", systemImage: "video")
                }
        }
        .frame(width: 460, height: 380)
        .padding()
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
            Section(header: Text("Post-Recording Automation").font(.headline)) {
                Toggle("Copy Google Drive link to clipboard automatically", isOn: $preferences.copyLinkToClipboard)
                Toggle("Delete local file after successful upload", isOn: $preferences.autoDeleteLocalFile)
                    .help("Saves disk space by removing the local .mp4 once uploaded to Google Drive.")
            }
            
            Section(header: Text("Local Storage").font(.headline)) {
                HStack {
                    Text("Recordings Folder:")
                    Spacer()
                    Text("~/Movies/RecDrive/")
                        .foregroundColor(.secondary)
                    Button("Reveal") {
                        let url = LocalStorageManager.shared.recordingsDirectory
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Drive Tab
    
    private var driveTab: some View {
        Form {
            Section(header: Text("Account Connection").font(.headline)) {
                if oauthManager.isAuthenticated {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 28))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(oauthManager.currentUserEmail ?? "Connected User")
                                .font(.headline)
                            if let name = oauthManager.currentUserName {
                                Text(name).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Disconnect", role: .destructive) {
                            oauthManager.signOut()
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect your Google account to automatically upload screen recordings with resumable background uploads.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            Task {
                                try? await oauthManager.startAuthentication()
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                Text(oauthManager.isAuthenticating ? "Connecting..." : "Sign in with Google")
                            }
                        }
                        .disabled(oauthManager.isAuthenticating)
                        
                        if let error = oauthManager.authErrorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            
            if oauthManager.isAuthenticated {
                Section(header: Text("Destination Folder").font(.headline)) {
                    HStack {
                        Text("Folder:")
                        Spacer()
                        Text(preferences.selectedDriveFolderName)
                            .foregroundColor(.secondary)
                        
                        Button(uiState.isLoadingFolders ? "Loading..." : "Browse") {
                            loadDriveFolders()
                        }
                        .disabled(uiState.isLoadingFolders)
                    }
                    
                    if !uiState.availableFolders.isEmpty {
                        Picker("Select Destination", selection: $preferences.selectedDriveFolderId) {
                            Text("Google Drive Root").tag(nil as String?)
                            ForEach(uiState.availableFolders) { folder in
                                Text(folder.name).tag(folder.id as String?)
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Custom OAuth Credentials").font(.headline)) {
                DisclosureGroup("Configure Google Cloud Client ID (Optional)", isExpanded: $uiState.showingAdvancedAuth) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client ID:")
                        TextField("Your Google Client ID", text: $preferences.customClientId)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Client Secret:")
                        SecureField("Your Google Client Secret", text: $preferences.customClientSecret)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Capture Tab
    
    private var captureTab: some View {
        Form {
            Section(header: Text("Hardware Video Encoding").font(.headline)) {
                Picker("Video Codec:", selection: $preferences.videoCodec) {
                    Text("HEVC / H.265 (Recommended - Apple Silicon)").tag("hevc")
                    Text("H.264 (Maximum Compatibility)").tag("h264")
                }
                
                Picker("Target Framerate:", selection: $preferences.targetFrameRate) {
                    Text("60 FPS (Ultra Smooth)").tag(60)
                    Text("30 FPS (Energy Saving)").tag(30)
                }
            }
            
            Section(header: Text("Default Audio Inputs").font(.headline)) {
                Toggle("Capture System Audio", isOn: $preferences.captureSystemAudio)
                Toggle("Capture External Microphone", isOn: $preferences.captureMicrophone)
            }
        }
        .padding()
    }
    
    private func loadDriveFolders() {
        uiState.isLoadingFolders = true
        Task {
            do {
                let folders = try await driveService.fetchFolders()
                await MainActor.run {
                    self.uiState.availableFolders = folders
                    self.uiState.isLoadingFolders = false
                }
            } catch {
                await MainActor.run {
                    self.uiState.isLoadingFolders = false
                }
            }
        }
    }
}
