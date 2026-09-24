import Foundation

// MARK: - OAuth 2.0 Response Models

public struct OAuthTokenResponse: Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let tokenType: String
    public let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

public struct GoogleUserInfo: Codable {
    public let id: String
    public let email: String
    public let name: String?
    public let picture: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "sub"
        case email
        case name
        case picture
    }
}

// MARK: - Google Drive API Models

public struct DriveFile: Codable, Identifiable {
    public let id: String
    public let name: String
    public let mimeType: String?
    public let webViewLink: String?
    public let parents: [String]?
    public let size: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mimeType
        case webViewLink
        case parents
        case size
    }
}

public struct DriveFileListResponse: Codable {
    public let files: [DriveFile]
    public let nextPageToken: String?
}

public struct DriveFolder: Identifiable, Hashable {
    public let id: String
    public let name: String
    
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Upload State & Progress

public enum UploadState: Equatable {
    case idle
    case initiating
    case uploading(fraction: Double, bytesSent: Int64, totalBytes: Int64)
    case paused
    case completed(fileId: String, webLink: String?)
    case failed(error: String)
}

public struct UploadProgress {
    public let state: UploadState
    public let bytesUploaded: Int64
    public let totalBytes: Int64
    
    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0.0 }
        return Double(bytesUploaded) / Double(totalBytes)
    }
}
