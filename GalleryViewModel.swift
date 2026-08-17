import SwiftUI
import Observation

@Observable
class GalleryViewModel {
    var items: [MediaItem] = []
    var isSyncing: Bool = false
    var isLoadingCloud: Bool = false
    var syncProgressText: String = "Sẵn sàng"

    init() {
        Task {
            await loadCloudMedia()
        }
    }

    /// Tải toàn bộ danh sách ảnh thực tế từ kênh Discord
    @MainActor
    func loadCloudMedia() async {
        guard DiscordService.isLoggedIn else {
            syncProgressText = "Chưa kết nối Discord"
            return
        }

        isLoadingCloud = true
        syncProgressText = "Đang tải ảnh từ Discord..."

        do {
            let cloudItems = try await DiscordService.shared.fetchChannelMedia()
            
            // Giữ lại các ảnh local đang chờ upload (nếu có)
            let localPending = items.filter {
                if case .localOnly = $0.syncStatus { return true }
                if case .syncing = $0.syncStatus { return true }
                return false
            }
            
            self.items = localPending + cloudItems
            syncProgressText = "Đã tải \(cloudItems.count) ảnh từ Cloud"
        } catch {
            syncProgressText = "Không thể tải ảnh: \(error.localizedDescription)"
        }

        isLoadingCloud = false
    }

    /// Thêm ảnh từ máy vào hàng đợi
    @MainActor
    func addLocalImage(_ image: UIImage) {
        let newItem = MediaItem(
            id: UUID().uuidString,
            remoteURL: nil,
            localImage: image,
            timestamp: Date(),
            syncStatus: .localOnly,
            filename: "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        )
        items.insert(newItem, at: 0)
    }

    /// Bắt đầu đồng bộ các ảnh chưa tải lên
    @MainActor
    func triggerSyncAll() async {
        guard DiscordService.isLoggedIn else {
            syncProgressText = "Vui lòng đăng nhập trước"
            return
        }

        guard !isSyncing else { return }
        isSyncing = true

        let pendingIndices = items.indices.filter {
            if case .localOnly = items[$0].syncStatus { return true }
            if case .failed = items[$0].syncStatus { return true }
            return false
        }

        if pendingIndices.isEmpty {
            syncProgressText = "Tất cả ảnh đã được sao lưu"
            isSyncing = false
            return
        }

        for (index, idx) in pendingIndices.enumerated() {
            syncProgressText = "Đang tải lên \(index + 1)/\(pendingIndices.count)..."
            items[idx].syncStatus = .syncing(progress: 0.5)

            if let image = items[idx].localImage, let jpegData = image.jpegData(compressionQuality: 0.85) {
                do {
                    let result = try await DiscordService.shared.uploadMedia(
                        imageData: jpegData,
                        filename: items[idx].filename
                    )
                    items[idx].syncStatus = .synced(remoteURL: result.url)
                    items[idx].remoteURL = result.url
                } catch {
                    items[idx].syncStatus = .failed
                }
            }
        }

        isSyncing = false
        syncProgressText = "Đồng bộ hoàn tất"
    }
}
