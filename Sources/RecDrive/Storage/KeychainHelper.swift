import Foundation
import Security

/// Thread-safe wrapper for macOS Keychain Services API.
/// Securely stores OAuth tokens and sensitive credentials in `kSecClassGenericPassword`.
public final class KeychainHelper {
    public static let shared = KeychainHelper()
    
    private let defaultService = "com.recdrive.tokens"
    private let lock = NSLock()
    
    public init() {}
    
    public enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case invalidData
        
        public var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "The requested item was not found in the Keychain."
            case .duplicateItem:
                return "The item already exists in the Keychain."
            case .unexpectedStatus(let status):
                if let message = SecCopyErrorMessageString(status, nil) as String? {
                    return "Keychain error: \(message) (\(status))"
                }
                return "Unknown Keychain status code: \(status)"
            case .invalidData:
                return "Data could not be converted."
            }
        }
    }
    
    // MARK: - Save Item
    
    @discardableResult
    public func save(key: String, data: Data, service: String? = nil) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        
        // Remove existing item if present to avoid errSecDuplicateItem
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        return true
    }
    
    @discardableResult
    public func save(key: String, string: String, service: String? = nil) throws -> Bool {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        return try save(key: key, data: data, service: service)
    }
    
    // MARK: - Read Item
    
    public func get(key: String, service: String? = nil) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }
    
    public func getString(key: String, service: String? = nil) -> String? {
        guard let data = get(key: key, service: service) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Delete Item
    
    public func delete(key: String, service: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // MARK: - Clear All
    
    public func clearAll(service: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let targetService = service ?? defaultService
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
