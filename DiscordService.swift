import Foundation
import UIKit

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
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)") else { return false }
        
        var request = URLRequest(url: url)
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Kéo toàn bộ ảnh đã lưu trên server Discord về máy
    func fetchChannelMedia(limit: Int = 100) async throws -> [MediaItem] {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages?limit=\(limit)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let messages = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
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
                            localImage: nil,
                            timestamp: Date(),
                            syncStatus: .synced(remoteURL: urlString),
                            filename: filename,
                            fileSize: size,
                            isEncrypted: false
                        )
                        fetchedItems.append(item)
                    }
                }
            }
        }
        return fetchedItems
    }

    /// Tải ảnh lên kênh Discord
    func uploadMedia(imageData: Data, filename: String) async throws -> (url: String, messageId: String) {
        let token = await DiscordService.botToken
        let channel = await DiscordService.channelId

        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channel)/messages") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageId = json["id"] as? String,
              let attachments = json["attachments"] as? [[String: Any]],
              let firstAtt = attachments.first,
              let remoteURL = firstAtt["url"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return (url: remoteURL, messageId: messageId)
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
