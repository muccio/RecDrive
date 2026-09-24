import Foundation
import AppKit

/// High-performance resumable upload service conforming to Google Drive REST API v3.
/// Streams video in 2MB chunks (multiples of 256KB) to conserve memory and handle network interruptions.
public final class DriveService: ObservableObject {
    public static let shared = DriveService()
    
    @Published public private(set) var activeUploads: [URL: UploadState] = [:]
    
    /// Standard Google Drive resumable chunk size: 2 MB (8 * 256 KB)
    private let chunkSize: Int = 2 * 1024 * 1024
    private let maxRetryAttempts: Int = 5
    
    public init() {}
    
    public enum DriveError: LocalizedError {
        case fileNotFound(URL)
        case initiationFailed(statusCode: Int, message: String)
        case missingLocationHeader
        case chunkUploadFailed(statusCode: Int, message: String)
        case uploadCorrupted
        case networkError(Error)
        case unauthorized
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "File to upload not found at \(url.path)"
            case .initiationFailed(let code, let msg):
                return "Failed to initiate Drive upload session (Status \(code)): \(msg)"
            case .missingLocationHeader:
                return "Google Drive API response did not include a valid resumable upload URL."
            case .chunkUploadFailed(let code, let msg):
                return "Drive chunk upload failed (Status \(code)): \(msg)"
            case .uploadCorrupted:
                return "The uploaded file could not be verified by Google Drive."
            case .networkError(let err):
                return "Network connection error: \(err.localizedDescription)"
            case .unauthorized:
                return "Google account authentication expired or invalid. Please sign in again."
            }
        }
    }
    
    // MARK: - Full Pipeline: Upload Local Recording
    
    /// Executes the full upload workflow: initiates session, uploads in chunks, copies link, and handles cleanup.
    public func uploadRecording(fileURL: URL, progressHandler: (@Sendable (UploadProgress) -> Void)? = nil) async throws -> DriveFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DriveError.fileNotFound(fileURL)
        }
        
        let folderId = PreferencesStorage.shared.selectedDriveFolderId
        
        await MainActor.run {
            self.activeUploads[fileURL] = .initiating
        }
        progressHandler?(UploadProgress(state: .initiating, bytesUploaded: 0, totalBytes: LocalStorageManager.shared.fileSize(at: fileURL)))
        
        // Step 1: Initiate Resumable Session
        let uploadURL = try await initiateResumableUpload(fileURL: fileURL, folderId: folderId)
        
        // Step 2: Upload Chunks
        let driveFile = try await uploadChunks(fileURL: fileURL, uploadURL: uploadURL, progressHandler: progressHandler)
        
        let link = driveFile.webViewLink ?? "https://drive.google.com/file/d/\(driveFile.id)/view"
        
        await MainActor.run {
            self.activeUploads[fileURL] = .completed(fileId: driveFile.id, webLink: link)
            
            // Step 3: Copy Drive link to clipboard if configured
            if PreferencesStorage.shared.copyLinkToClipboard {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(link, forType: .string)
            }
            
            // Step 4: Delete local file if configured
            if PreferencesStorage.shared.autoDeleteLocalFile {
                try? LocalStorageManager.shared.deleteFile(at: fileURL)
            }
        }
        
        return driveFile
    }
    
    // MARK: - Step 1: Initiate Resumable Session
    
    public func initiateResumableUpload(fileURL: URL, folderId: String?) async throws -> URL {
        let token = try await OAuthManager.shared.getValidAccessToken()
        let fileSize = LocalStorageManager.shared.fileSize(at: fileURL)
        
        var request = URLRequest(url: AuthConfig.driveResumableUploadEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("video/mp4", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        // Metadata payload
        var metadata: [String: Any] = [
            "name": fileURL.lastPathComponent,
            "mimeType": "video/mp4",
            "description": "Recorded with RecDrive for macOS"
        ]
        
        if let folderId = folderId, !folderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            metadata["parents"] = [folderId]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DriveError.uploadCorrupted
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DriveError.initiationFailed(statusCode: httpResponse.statusCode, message: errorMsg)
        }
        
        guard let locationString = httpResponse.value(forHTTPHeaderField: "Location"),
              let uploadLocationURL = URL(string: locationString) else {
            throw DriveError.missingLocationHeader
        }
        
        return uploadLocationURL
    }
    
    // MARK: - Step 2: Upload File in Chunks
    
    private func uploadChunks(fileURL: URL, uploadURL: URL, progressHandler: (@Sendable (UploadProgress) -> Void)?) async throws -> DriveFile {
        let totalSize = LocalStorageManager.shared.fileSize(at: fileURL)
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        
        var currentOffset: Int64 = 0
        var retryCount = 0
        
        while currentOffset < totalSize {
            let bytesRemaining = totalSize - currentOffset
            let currentChunkLength = min(Int64(chunkSize), bytesRemaining)
            
            try fileHandle.seek(toOffset: UInt64(currentOffset))
            let chunkData = fileHandle.readData(ofLength: Int(currentChunkLength))
            
            let endByte = currentOffset + Int64(chunkData.count) - 1
            
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"
            request.setValue("\(chunkData.count)", forHTTPHeaderField: "Content-Length")
            request.setValue("bytes \(currentOffset)-\(endByte)/\(totalSize)", forHTTPHeaderField: "Content-Range")
            request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            request.httpBody = chunkData
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw DriveError.uploadCorrupted
                }
                
                // Status 308: Resume Incomplete - advance chunk
                if httpResponse.statusCode == 308 {
                    retryCount = 0
                    if let rangeHeader = httpResponse.value(forHTTPHeaderField: "Range") {
                        // Header format: "bytes=0-1048575"
                        currentOffset = parseLastByteUploaded(from: rangeHeader) + 1
                    } else {
                        currentOffset += Int64(chunkData.count)
                    }
                    
                    let progress = UploadProgress(
                        state: .uploading(fraction: Double(currentOffset) / Double(totalSize), bytesSent: currentOffset, totalBytes: totalSize),
                        bytesUploaded: currentOffset,
                        totalBytes: totalSize
                    )
                    await MainActor.run {
                        self.activeUploads[fileURL] = progress.state
                    }
                    progressHandler?(progress)
                    continue
                }
                
                // Status 200/201: Upload finished
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    let driveFile = try JSONDecoder().decode(DriveFile.self, from: data)
                    let progress = UploadProgress(
                        state: .completed(fileId: driveFile.id, webLink: driveFile.webViewLink),
                        bytesUploaded: totalSize,
                        totalBytes: totalSize
                    )
                    progressHandler?(progress)
                    return driveFile
                }
                
                // Other HTTP error
                let errorMsg = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
                throw DriveError.chunkUploadFailed(statusCode: httpResponse.statusCode, message: errorMsg)
                
            } catch {
                retryCount += 1
                if retryCount > maxRetryAttempts {
                    throw error
                }
                
                // Exponential backoff wait before reconciling byte offset
                let backoffDelay = min(pow(2.0, Double(retryCount)), 32.0)
                try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                
                // Reconcile byte offset from server
                if let serverOffset = try? await queryCurrentServerOffset(uploadURL: uploadURL, totalSize: totalSize) {
                    currentOffset = serverOffset
                }
            }
        }
        
        throw DriveError.uploadCorrupted
    }
    
    // MARK: - Disconnection Recovery: Query Current Server Offset
    
    private func queryCurrentServerOffset(uploadURL: URL, totalSize: Int64) async throws -> Int64 {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue("bytes */\(totalSize)", forHTTPHeaderField: "Content-Range")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return 0 }
        
        if httpResponse.statusCode == 308, let rangeHeader = httpResponse.value(forHTTPHeaderField: "Range") {
            return parseLastByteUploaded(from: rangeHeader) + 1
        }
        return 0
    }
    
    private func parseLastByteUploaded(from rangeHeader: String) -> Int64 {
        // e.g. "bytes=0-2097151"
        let parts = rangeHeader.replacingOccurrences(of: "bytes=", with: "").split(separator: "-")
        if parts.count == 2, let lastByte = Int64(parts[1]) {
            return lastByte
        }
        return 0
    }
    
    // MARK: - Folder Exploration
    
    /// Queries existing user folders in Google Drive for the Preferences selector.
    public func fetchFolders(query: String? = nil) async throws -> [DriveFolder] {
        let token = try await OAuthManager.shared.getValidAccessToken()
        
        var queryConditions = ["mimeType = 'application/vnd.google-apps.folder'", "trashed = false"]
        if let query = query, !query.isEmpty {
            queryConditions.append("name contains '\(query)'")
        }
        
        let q = queryConditions.joined(separator: " and ")
        var components = URLComponents(url: AuthConfig.driveFilesEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fields", value: "files(id, name)"),
            URLQueryItem(name: "pageSize", value: "100"),
            URLQueryItem(name: "orderBy", value: "name")
        ]
        
        guard let url = components.url else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return []
        }
        
        let listResponse = try JSONDecoder().decode(DriveFileListResponse.self, from: data)
        return listResponse.files.map { DriveFolder(id: $0.id, name: $0.name) }
    }
}
