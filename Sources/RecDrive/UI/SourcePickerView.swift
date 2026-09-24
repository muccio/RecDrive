import SwiftUI
import ScreenCaptureKit

@MainActor
final class SourcePickerUIState: ObservableObject {
    @Published var selectedTab: Int = 0 // 0 = Displays, 1 = Windows
}

/// View for selecting a capture target: Full Display or Specific Window.
struct SourcePickerView: View {
    @ObservedObject var appState = AppState.shared
    @StateObject private var uiState = SourcePickerUIState()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 12) {
            Picker("Source Type", selection: $uiState.selectedTab) {
                Text("Displays").tag(0)
                Text("Windows").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            Divider()
            
            if uiState.selectedTab == 0 {
                // Displays List
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appState.captureManager.availableDisplays) { display in
                            Button {
                                appState.selectedTarget = .display(display.scDisplay)
                                appState.selectedTargetName = display.name
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "display")
                                        .font(.system(size: 20))
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(display.name)
                                            .font(.headline)
                                        Text("\(display.width) × \(display.height) Native")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if case .display(let current) = appState.selectedTarget, current.displayID == display.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                // Windows List
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(appState.captureManager.availableWindows) { window in
                            Button {
                                appState.selectedTarget = .window(window.scWindow)
                                appState.selectedTargetName = "\(window.appName) - \(window.title)"
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "macwindow")
                                        .font(.system(size: 18))
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(window.title)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(window.appName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if case .window(let current) = appState.selectedTarget, current.windowID == window.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            HStack {
                Button("Refresh") {
                    Task {
                        await appState.captureManager.refreshShareableContent()
                    }
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 320, height: 350)
        .padding(.top, 8)
        .task {
            await appState.captureManager.refreshShareableContent()
        }
    }
}
