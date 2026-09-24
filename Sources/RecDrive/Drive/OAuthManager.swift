import Foundation
import Network
import CommonCrypto
import AppKit

/// Manages Google OAuth 2.0 PKCE authentication flow, Keychain persistence, and token refreshment.
@MainActor
public final class OAuthManager: ObservableObject {
    public static let shared = OAuthManager()
    
    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var currentUserEmail: String? = nil
    @Published public private(set) var currentUserName: String? = nil
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public private(set) var authErrorMessage: String? = nil
    
    private var accessToken: String? = nil
    private var tokenExpirationDate: Date = .distantPast
    private let keychain = KeychainHelper.shared
    
    private let tokenAccountKey = "google_refresh_token"
    private let userEmailAccountKey = "google_user_email"
    private let userNameAccountKey = "google_user_name"
    
    public init() {
        checkExistingAuth()
    }
    
    // MARK: - Initial Auth State Check
    
    public func checkExistingAuth() {
        if let _ = keychain.getString(key: tokenAccountKey) {
            self.isAuthenticated = true
            self.currentUserEmail = keychain.getString(key: userEmailAccountKey)
            self.currentUserName = keychain.getString(key: userNameAccountKey)
        } else {
            self.isAuthenticated = false
            self.currentUserEmail = nil
            self.currentUserName = nil
        }
    }
    
    // MARK: - PKCE Cryptography (RFC 7636)
    
    private nonisolated func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private nonisolated func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Interactive Authorization Flow
    
    public func startAuthentication() async throws {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authErrorMessage = nil
        
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        do {
            let (port, authCode) = try await startLoopbackServerAndGetAuthCode(codeChallenge: codeChallenge)
            let redirectUri = "http://127.0.0.1:\(port)/oauth2callback"
            
            try await exchangeCodeForTokens(code: authCode, codeVerifier: codeVerifier, redirectUri: redirectUri)
            try await fetchUserProfile()
            
            self.isAuthenticated = true
            self.isAuthenticating = false
        } catch {
            self.isAuthenticating = false
            self.authErrorMessage = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Loopback HTTP Server
    
    private func startLoopbackServerAndGetAuthCode(codeChallenge: String) async throws -> (UInt16, String) {
        let clientId = AuthConfig.activeClientId
        let scopes = AuthConfig.scopes
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(UInt16, String), Error>) in
            do {
                let tcpOptions = NWProtocolTCP.Options()
                let parameters = NWParameters(tls: nil, tcp: tcpOptions)
                parameters.allowLocalEndpointReuse = true
                
                let listener = try NWListener(using: parameters, on: .any)
                
                final class SafeResumeBox: @unchecked Sendable {
                    private let lock = NSLock()
                    private var hasResumed = false
                    
                    func resumeOnce(_ block: () -> Void) {
                        lock.lock()
                        defer { lock.unlock() }
                        guard !hasResumed else { return }
                        hasResumed = true
                        block()
                    }
                }
                
                let resumeBox = SafeResumeBox()
                
                let safeResume: @Sendable (Result<(UInt16, String), Error>) -> Void = { result in
                    resumeBox.resumeOnce {
                        listener.cancel()
                        switch result {
                        case .success(let val):
                            continuation.resume(returning: val)
                        case .failure(let err):
                            continuation.resume(throwing: err)
                        }
                    }
                }
                
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard let port = listener.port?.rawValue else { return }
                        let redirectUri = "http://127.0.0.1:\(port)/oauth2callback"
                        
                        var components = URLComponents(url: AuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
                        components.queryItems = [
                            URLQueryItem(name: "client_id", value: clientId),
                            URLQueryItem(name: "redirect_uri", value: redirectUri),
                            URLQueryItem(name: "response_type", value: "code"),
                            URLQueryItem(name: "scope", value: scopes),
                            URLQueryItem(name: "code_challenge", value: codeChallenge),
                            URLQueryItem(name: "code_challenge_method", value: "S256"),
                            URLQueryItem(name: "access_type", value: "offline"),
                            URLQueryItem(name: "prompt", value: "consent")
                        ]
                        
                        if let authURL = components.url {
                            DispatchQueue.main.async {
                                NSWorkspace.shared.open(authURL)
                            }
                        }
                    case .failed(let error):
                        safeResume(.failure(error))
                    default:
                        break
                    }
                }
                
                listener.newConnectionHandler = { connection in
                    connection.start(queue: .global())
                    connection.receive(minimumIncompleteLength: 4, maximumLength: 4096) { content, _, isComplete, error in
                        if let error = error {
                            safeResume(.failure(error))
                            return
                        }
                        
                        guard let content = content, let requestString = String(data: content, encoding: .utf8) else {
                            return
                        }
                        
                        let lines = requestString.components(separatedBy: "\r\n")
                        guard let firstLine = lines.first, firstLine.hasPrefix("GET ") else { return }
                        
                        let pathParts = firstLine.split(separator: " ")
                        guard pathParts.count >= 2 else { return }
                        let pathAndQuery = String(pathParts[1])
                        
                        var code: String? = nil
                        if let queryUrl = URL(string: "http://localhost" + pathAndQuery),
                           let queryItems = URLComponents(url: queryUrl, resolvingAgainstBaseURL: false)?.queryItems {
                            code = queryItems.first(where: { $0.name == "code" })?.value
                        }
                        
                        let html = """
                        <!DOCTYPE html>
                        <html>
                        <head><title>RecDrive - Connected</title><style>body { font-family: -apple-system, sans-serif; text-align: center; padding: 40px; background: #0f172a; color: white; } h1 { color: #38bdf8; } p { color: #94a3b8; }</style></head>
                        <body>
                            <h1>✓ RecDrive Connected!</h1>
                            <p>Google Drive authorization was successful. You can close this tab and return to the menu bar app.</p>
                        </body>
                        </html>
                        """
                        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                        
                        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in
                            connection.cancel()
                        }))
                        
                        if let port = listener.port?.rawValue, let extractedCode = code {
                            safeResume(.success((port, extractedCode)))
                        }
                    }
                }
                
                listener.start(queue: .global())
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Token Exchange
    
    private func exchangeCodeForTokens(code: String, codeVerifier: String, redirectUri: String) async throws {
        var request = URLRequest(url: AuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyParams: [String: String] = [
            "code": code,
            "client_id": AuthConfig.activeClientId,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]
        
        let clientSecret = AuthConfig.activeClientSecret
        if !clientSecret.isEmpty && clientSecret != AuthConfig.defaultClientSecret {
            bodyParams["client_secret"] = clientSecret
        }
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown token exchange error"
            throw NSError(domain: "RecDrive.OAuth", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
        self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        
        if let refreshToken = tokenResponse.refreshToken {
            _ = try? keychain.save(key: tokenAccountKey, string: refreshToken)
        }
    }
    
    // MARK: - Token Refresh & Access
    
    public func getValidAccessToken() async throws -> String {
        if let token = accessToken, Date() < tokenExpirationDate {
            return token
        }
        
        guard let refreshToken = keychain.getString(key: tokenAccountKey) else {
            self.isAuthenticated = false
            throw NSError(domain: "RecDrive.OAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No refresh token available. Please sign in to Google Drive."])
        }
        
        var request = URLRequest(url: AuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyParams: [String: String] = [
            "client_id": AuthConfig.activeClientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        let clientSecret = AuthConfig.activeClientSecret
        if !clientSecret.isEmpty && clientSecret != AuthConfig.defaultClientSecret {
            bodyParams["client_secret"] = clientSecret
        }
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Token refresh failed"
            throw NSError(domain: "RecDrive.OAuth", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
        self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        
        if let newRefreshToken = tokenResponse.refreshToken {
            _ = try? keychain.save(key: tokenAccountKey, string: newRefreshToken)
        }
        
        self.isAuthenticated = true
        return tokenResponse.accessToken
    }
    
    // MARK: - User Profile Fetch
    
    public func fetchUserProfile() async throws {
        let token = try await getValidAccessToken()
        var request = URLRequest(url: AuthConfig.userInfoEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return
        }
        
        let userInfo = try JSONDecoder().decode(GoogleUserInfo.self, from: data)
        _ = try? keychain.save(key: userEmailAccountKey, string: userInfo.email)
        if let name = userInfo.name {
            _ = try? keychain.save(key: userNameAccountKey, string: name)
        }
        
        self.currentUserEmail = userInfo.email
        self.currentUserName = userInfo.name
    }
    
    // MARK: - Sign Out
    
    public func signOut() {
        try? keychain.delete(key: tokenAccountKey)
        try? keychain.delete(key: userEmailAccountKey)
        try? keychain.delete(key: userNameAccountKey)
        
        self.accessToken = nil
        self.tokenExpirationDate = .distantPast
        self.isAuthenticated = false
        self.currentUserEmail = nil
        self.currentUserName = nil
    }
}
