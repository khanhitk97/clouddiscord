import Foundation
import UIKit

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
                let isEncrypted = att.filename.hasSuffix(".enc")
                let isMedia = isEncrypted || att.contentType?.starts(with: "image/") == true || att.contentType?.starts(with: "video/") == true

                if isMedia {
                    let item = MediaItem(
                        id: att.id,
                        messageId: msg.id,
                        remoteURL: att.url,
                        localImage: nil,
                        timestamp: date,
                        syncStatus: .synced(remoteURL: att.url),
                        filename: att.filename,
                        fileSize: att.size,
                        isEncrypted: isEncrypted
                    )
                    fetchedItems.append(item)
                }
            }
        }
        return fetchedItems
    }

    func uploadMedia(imageData: Data, filename: String) async throws -> (url: String, messageId: String) {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages") else {
            throw URLError(.badURL)
        }

        // Mã hóa bảo mật AES
        let encryptedData = (try? EncryptionService.shared.encrypt(data: imageData)) ?? imageData
        let safeFilename = filename.hasSuffix(".enc") ? filename : (filename + ".enc")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files[0]\"; filename=\"\(safeFilename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(encryptedData)
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

    func downloadMediaData(url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    func deleteMedia(messageId: String) async throws {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages/\(messageId)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
