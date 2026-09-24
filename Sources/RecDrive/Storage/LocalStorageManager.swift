import Foundation

/// Manages local disk storage for active and completed screen recordings.
public final class LocalStorageManager {
    public static let shared = LocalStorageManager()
    
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Target directory for recordings: `~/Movies/RecDrive/`
    public var recordingsDirectory: URL {
        if let moviesURL = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first {
            let recDriveDir = moviesURL.appendingPathComponent("RecDrive", isDirectory: true)
            if !fileManager.fileExists(atPath: recDriveDir.path) {
                try? fileManager.createDirectory(at: recDriveDir, withIntermediateDirectories: true)
            }
            return recDriveDir
        }
        
        // Fallback to NSTemporaryDirectory() if Movies directory is inaccessible
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("RecDrive", isDirectory: true)
        if !fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }
        return tempDir
    }
    
    /// Creates a timestamped unique file URL for a new recording.
    /// Format: `RecDrive_YYYY-MM-dd_HH-mm-ss.mp4`
    public func createRecordingURL(fileExtension: String = "mp4") -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "RecDrive_\(timestamp).\(fileExtension)"
        return recordingsDirectory.appendingPathComponent(filename)
    }
    
    /// Returns the exact byte size of a local file.
    public func fileSize(at url: URL) -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            return 0
        }
    }
    
    /// Safely deletes a file from disk.
    public func deleteFile(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
    
    /// Enumerates existing local recording files sorted newest first.
    public func listRecordings() -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        let videoFiles = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "mp4" || ext == "mov"
        }
        
        return videoFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
            return date1 > date2
        }
    }
    
    /// Cleans up partial or abandoned temporary files older than the specified duration.
    public func cleanupOldTempFiles(olderThan seconds: TimeInterval = 86400 * 3) {
        let cutoff = Date().addingTimeInterval(-seconds)
        let files = listRecordings()
        for file in files {
            if let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               date < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
