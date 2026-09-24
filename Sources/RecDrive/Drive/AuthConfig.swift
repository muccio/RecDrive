import Foundation

/// Central configuration for Google Drive OAuth 2.0 and REST API endpoints.
public struct AuthConfig {
    /// Default Google Cloud OAuth 2.0 Desktop App Client ID.
    /// Can be overridden via SettingsView / PreferencesStorage without recompiling.
    public static let defaultClientId = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
    public static let defaultClientSecret = "YOUR_GOOGLE_CLIENT_SECRET"
    
    // MARK: - OAuth 2.0 Endpoints
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!
    
    // MARK: - Google Drive REST API v3 Endpoints
    public static let driveFilesEndpoint = URL(string: "https://www.googleapis.com/drive/v3/files")!
    public static let driveResumableUploadEndpoint = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable")!
    
    // MARK: - Scopes
    /// Principle of least privilege: only access files created or opened by RecDrive
    public static let scopes = [
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile"
    ].joined(separator: " ")
    
    // MARK: - Dynamic Configuration Resolution
    public static var activeClientId: String {
        let custom = PreferencesStorage.shared.customClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultClientId : custom
    }
    
    public static var activeClientSecret: String {
        let custom = PreferencesStorage.shared.customClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultClientSecret : custom
    }
}
