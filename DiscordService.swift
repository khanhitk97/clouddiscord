import Foundation
import UIKit

enum DiscordAPIError: LocalizedError {
    case invalidToken
    case channelNotFound
    case missingPermissions(String)
    case rateLimited
    case badRequest(String)
    case serverError(Int, String)
    case networkError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "❌ Token không hợp lệ (401): Vui lòng kiểm tra lại Bot Token."
        case .channelNotFound:
            return "❌ Không tìm thấy Kênh (404): Channel ID sai hoặc Bot chưa vào Server."
        case .missingPermissions(let details):
            return "❌ Bot thiếu quyền (403): Bot chưa được cấp quyền 'Send Messages' hoặc 'Attach Files'. (\(details))"
        case .rateLimited:
            return "⚠️ Bị giới hạn tốc độ (429): Gửi quá nhanh, Discord tạm khóa 1-2 phút."
        case .badRequest(let details):
            return "❌ Yêu cầu không hợp lệ (400): \(details)"
        case .serverError(let code, let msg):
            return "❌ Lỗi Discord API (\(code)): \(msg)"
        case .networkError(let msg):
            return "❌ Lỗi mạng: \(msg)"
        case .emptyResponse:
            return "❌ Discord không trả về dữ liệu ảnh."
        }
    }
}

actor DiscordService {
    static let shared = DiscordService()
    private init() {}

    @MainActor static var botToken: String {
        get { UserDefaults.standard.string(forKey: "discord_bot_token")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { UserDefaults.standard.setValue(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "discord_bot_token") }
    }
    
    @MainActor static var channelId: String {
        get { UserDefaults.standard.string(forKey: "discord_channel_id")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { UserDefaults.standard.setValue(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "discord_channel_id") }
    }

    @MainActor static var isLoggedIn: Bool {
        return !botToken.isEmpty && !channelId.isEmpty
    }

    /// Phân tích phản hồi lỗi từ Discord
    private func parseError(statusCode: Int, data: Data) -> DiscordAPIError {
        let rawMessage = String(data: data, encoding: .utf8) ?? ""
        
        switch statusCode {
        case 401:
            return .invalidToken
        case 403:
            return .missingPermissions(rawMessage)
        case 404:
            return .channelNotFound
        case 429:
            return .rateLimited
        case 400:
            return .badRequest(rawMessage)
        default:
            return .serverError(statusCode, rawMessage)
        }
    }

    /// Bước 1: Kiểm tra kết nối
    func verifyConnection() async throws {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard !token.isEmpty else { throw DiscordAPIError.invalidToken }
        guard !channel.isEmpty else { throw DiscordAPIError.channelNotFound }
        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)") else {
            throw DiscordAPIError.networkError("URL Kênh không hợp lệ")
        }

        var request = URLRequest(url: url)
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("DiscordBot (https://github.com, 1.0.0)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw DiscordAPIError.networkError("Không nhận được phản hồi từ server")
            }

            if httpResponse.statusCode != 200 {
                throw parseError(statusCode: httpResponse.statusCode, data: data)
            }
        } catch let apiErr as DiscordAPIError {
            throw apiErr
        } catch {
            throw DiscordAPIError.networkError(error.localizedDescription)
        }
    }

    /// Bước 2: Lấy danh sách ảnh
    func fetchChannelMedia(limit: Int = 100) async throws -> [MediaItem] {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages?limit=\(limit)") else {
            throw DiscordAPIError.networkError("URL không hợp lệ")
        }

        var request = URLRequest(url: url)
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("DiscordBot (https://github.com, 1.0.0)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DiscordAPIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscordAPIError.networkError("Không thể kết nối Internet")
        }

        if httpResponse.statusCode != 200 {
            throw parseError(statusCode: httpResponse.statusCode, data: data)
        }

        guard let messages = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DiscordAPIError.badRequest("Lỗi phân giải cấu trúc JSON tin nhắn")
        }

        var fetchedItems: [MediaItem] = []

        for msg in messages {
            let messageId = msg["id"] as? String ?? ""
            if let attachments = msg["attachments"] as? [[String: Any]] {
                for att in attachments {
                    let attId = att["id"] as? String ?? UUID().uuidString
                    let urlString = att["url"] as? String ?? ""
                    let filename = att["filename"] as? String ?? "photo.jpg"
                    let size = att["size"] as? Int ?? 0

                    if !urlString.isEmpty {
                        let item = MediaItem(
                            id: attId,
                            messageId: messageId,
                            remoteURL: urlString,
                            localPath: nil,
                            timestamp: Date(),
                            syncStatus: .synced(remoteURL: urlString),
                            filename: filename,
                            fileSize: size
                        )
                        fetchedItems.append(item)
                    }
                }
            }
        }
        return fetchedItems
    }

    /// Bước 3: Upload ảnh lên Discord
    func uploadMedia(imageData: Data, filename: String) async throws -> (url: String, messageId: String) {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages") else {
            throw DiscordAPIError.networkError("URL Upload không hợp lệ")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("DiscordBot (https://github.com, 1.0.0)", forHTTPHeaderField: "User-Agent")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files[0]\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: body)
        } catch {
            throw DiscordAPIError.networkError("Mạng gián đoạn khi đang upload: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscordAPIError.networkError("Không nhận được phản hồi từ Discord")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            throw parseError(statusCode: httpResponse.statusCode, data: data)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageId = json["id"] as? String,
              let attachments = json["attachments"] as? [[String: Any]],
              let firstAtt = attachments.first,
              let remoteURL = firstAtt["url"] as? String else {
            throw DiscordAPIError.badRequest("Không tìm thấy link đính kèm sau khi upload")
        }

        return (url: remoteURL, messageId: messageId)
    }

    func downloadMediaData(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("DiscordBot (https://github.com, 1.0.0)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    func deleteMedia(messageId: String) async throws {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages/\(messageId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("DiscordBot (https://github.com, 1.0.0)", forHTTPHeaderField: "User-Agent")

        let _ = try? await URLSession.shared.data(for: request)
    }
}
