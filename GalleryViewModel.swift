import SwiftUI
import Observation

enum SyncStatus {
    case localOnly
    case syncing(progress: Double)
    case synced(remoteURL: String)
    case failed
}

struct MediaItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var timestamp: Date = Date()
    var syncStatus: SyncStatus = .localOnly
    var isEncrypted: Bool = true
}

@Observable
class GalleryViewModel {
    var items: [MediaItem] = []
    var isSyncing: Bool = false
    var syncProgressText: String = "Đã đồng bộ toàn bộ"

    init() {
        loadSampleData()
    }

    private func loadSampleData() {
        // Mock data mẫu để test hiển thị ngay lập tức
        let systemSymbols = ["mountain.2.fill", "tree.fill", "sunset.fill", "camera.macro", "leaf.fill", "cloud.sun.fill"]
        self.items = systemSymbols.enumerated().map { index, name in
            let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .regular)
            let img = UIImage(systemName: name, withConfiguration: config) ?? UIImage()
            return MediaItem(
                image: img,
                syncStatus: index % 2 == 0 ? .synced(remoteURL: "https://cdn.discordapp.com/...") : .localOnly
            )
        }
    }

    /// Kích hoạt đồng bộ tất cả ảnh chưa lưu lên Discord
    @MainActor
    func triggerSyncAll() async {
        isSyncing = true
        let pendingIndices = items.indices.filter {
            if case .localOnly = items[$0].syncStatus { return true }
            return false
        }

        for (order, idx) in pendingIndices.enumerated() {
            syncProgressText = "Đang đồng bộ \(order + 1)/\(pendingIndices.count)..."
            items[idx].syncStatus = .syncing(progress: 0.5)

            if let jpegData = items[idx].image.jpegData(compressionQuality: 0.8) {
                do {
                    let result = try await DiscordService.shared.uploadMedia(imageData: jpegData)
                    items[idx].syncStatus = .synced(remoteURL: result.url)
                } catch {
                    items[idx].syncStatus = .failed
                }
            }
        }

        isSyncing = false
        syncProgressText = "Đồng bộ hoàn tất"
    }
}
