import Foundation
import UIKit

actor DiscordService {
    static let shared = DiscordService()
    private init() {}

    // Cấu hình Bot Token và Channel ID lưu trữ
    private let botToken = "YOUR_DISCORD_BOT_TOKEN"
    private let channelId = "YOUR_CHANNEL_ID"

    enum DiscordError: Error {
        case invalidURL
        case encodingFailed
        case serverError(statusCode: Int)
    }

    /// Upload ảnh lên kênh Discord và trả về CDN URL
    func uploadMedia(imageData: Data, filename: String = "photo.jpg") async throws -> (url: String, messageId: String) {
        guard let url = URL(string: "https://discord.com/api/v10/channels/\(channelId)/messages") else {
            throw DiscordError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bot \(botToken)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Tạo Multipart/form-data payload
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files[0]\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            throw DiscordError.serverError(statusCode: code)
        }

        // Trích xuất URL từ JSON phản hồi của Discord
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messageId = json?["id"] as? String ?? ""
        let attachments = json?["attachments"] as? [[String: Any]]
        let attachmentUrl = attachments?.first?["url"] as? String ?? ""

        return (url: attachmentUrl, messageId: messageId)
    }
}
