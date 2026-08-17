import Foundation
import UIKit

// Model ánh xạ JSON phản hồi từ Discord
struct DiscordAttachmentResponse: Decodable {
    let id: String
    let url: String
    let proxyUrl: String?
    let filename: String
    let size: Int
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case id, url, filename, size
        case proxyUrl = "proxy_url"
        case contentType = "content_type"
    }
}

struct DiscordMessageResponse: Decodable {
    let id: String
    let attachments: [DiscordAttachmentResponse]
    let timestamp: String
}

actor DiscordService {
    static let shared = DiscordService()
    private init() {}

    @MainActor static var botToken: String {
        get { UserDefaults.standard.string(forKey: "discord_bot_token") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "discord_bot_token") }
    }
    
    @MainActor static var channelId: String {
        get { UserDefaults.standard.string(forKey: "discord_channel_id") ?? "" }
        set { UserDefaults.standard.setValue(newValue, forKey: "discord_channel_id") }
    }

    @MainActor static var isLoggedIn: Bool {
        return !botToken.isEmpty && !channelId.isEmpty
    }

    /// Kiểm tra token và quyền truy cập kênh
    func verifyConnection() async -> Bool {
        let token = await DiscordService.botToken
        guard let url = URL(string: "https://discord.com/api/v10/users/@me") else { return false }
        
        var request = URLRequest(url: url)
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Kéo danh sách file media đã lưu trên kênh Discord (Tối đa 100 tin nhắn gần nhất)
    func fetchChannelMedia(limit: Int = 100) async throws -> [MediaItem] {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages?limit=\(limit)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let messages = try JSONDecoder().decode([DiscordMessageResponse].self, from: data)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var fetchedItems: [MediaItem] = []

        for msg in messages {
            let date = isoFormatter.date(from: msg.timestamp) ?? Date()
            for att in msg.attachments {
                // Chỉ lấy file định dạng hình ảnh
                let isImage = att.contentType?.starts(with: "image/") == true ||
                              att.filename.hasSuffix(".jpg") ||
                              att.filename.hasSuffix(".png") ||
                              att.filename.hasSuffix(".jpeg") ||
                              att.filename.hasSuffix(".webp")

                if isImage {
                    let item = MediaItem(
                        id: att.id,
                        remoteURL: att.url,
                        localImage: nil,
                        timestamp: date,
                        syncStatus: .synced(remoteURL: att.url),
                        filename: att.filename
                    )
                    fetchedItems.append(item)
                }
            }
        }
        return fetchedItems
    }

    /// Tải dữ liệu ảnh nhị phân lên kênh Discord
    func uploadMedia(imageData: Data, filename: String) async throws -> (url: String, messageId: String) {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files[0]\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let msg = try JSONDecoder().decode(DiscordMessageResponse.self, from: data)
        guard let firstAttachment = msg.attachments.first else {
            throw URLError(.cannotParseResponse)
        }

        return (url: firstAttachment.url, messageId: msg.id)
    }
}
