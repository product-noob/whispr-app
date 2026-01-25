import Foundation

/// Helper for API key storage using UserDefaults (simpler for development)
/// In production, this should use Keychain with proper code signing
enum KeychainHelper {
    private static let apiKeyKey = "whisprflow_api_key"
    
    // MARK: - API Key
    
    static func saveAPIKey(_ key: String) -> Bool {
        // Encode to base64 for basic obfuscation (not secure, but prevents casual reading)
        guard let data = key.data(using: .utf8) else { return false }
        let encoded = data.base64EncodedString()
        UserDefaults.standard.set(encoded, forKey: apiKeyKey)
        return true
    }
    
    static func getAPIKey() -> String? {
        guard let encoded = UserDefaults.standard.string(forKey: apiKeyKey),
              let data = Data(base64Encoded: encoded),
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }
    
    @discardableResult
    static func deleteAPIKey() -> Bool {
        UserDefaults.standard.removeObject(forKey: apiKeyKey)
        return true
    }
    
    static var hasAPIKey: Bool {
        guard let key = getAPIKey() else { return false }
        return !key.isEmpty
    }
}
