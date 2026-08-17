import Foundation
import CryptoKit

struct EncryptionService {
    static let shared = EncryptionService()
    private let keyTag = "com.clouddiscord.masterkey"

    private init() {}

    /// Lấy hoặc khởi tạo SymmetricKey trong Keychain/UserDefaults
    private func getOrCreateKey() -> SymmetricKey {
        if let storedKey = UserDefaults.standard.data(forKey: keyTag) {
            return SymmetricKey(data: storedKey)
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        UserDefaults.standard.set(keyData, forKey: keyTag)
        return newKey
    }

    /// Mã hóa dữ liệu bằng AES-GCM
    func encrypt(data: Data) throws -> Data {
        let key = getOrCreateKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw URLError(.cannotDecodeRawData)
        }
        return combined
    }

    /// Giải mã dữ liệu AES-GCM
    func decrypt(data: Data) throws -> Data {
        let key = getOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
