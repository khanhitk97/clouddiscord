import SwiftUI
import Observation
import Photos

@Observable
class GalleryViewModel {
    var items: [MediaItem] = []
    var isSyncing: Bool = false
    var isLoadingCloud: Bool = false
    var syncProgressText: String = "Sẵn sàng"

    var isAutoFullSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "auto_full_sync_enabled")
    }

    func setAutoFullSync(_ enabled: Bool) {
        UserDefaults.standard.setValue(enabled, forKey: "auto_full_sync_enabled")
    }

    var totalCloudStorageFormatted: String {
        let bytes = items.reduce(0) { $0 + $1.fileSize }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    init() {
        Task {
            await loadCloudMedia()
        }
    }

    @MainActor
    func loadCloudMedia() async {
        guard DiscordService.isLoggedIn else {
            syncProgressText = "Chưa kết nối Discord"
            return
        }

        isLoadingCloud = true
        syncProgressText = "Đang tải ảnh từ Cloud..."

        do {
            let cloudItems = try await DiscordService.shared.fetchChannelMedia()
            let localPending = items.filter {
                if case .localOnly = $0.syncStatus { return true }
                if case .syncing = $0.syncStatus { return true }
                return false
            }
            self.items = localPending + cloudItems
            syncProgressText = "Đã tải \(cloudItems.count) mục"
        } catch {
            syncProgressText = "Lỗi: \(error.localizedDescription)"
        }

        isLoadingCloud = false
    }

    @MainActor
    func syncAllDevicePhotos() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            syncProgressText = "Chưa cấp quyền truy cập Ảnh"
            return
        }

        syncProgressText = "Đang quét thư viện ảnh..."
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat

        var newPhotosCount = 0
        allPhotos.enumerateObjects { asset, _, _ in
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 1400, height: 1400),
                contentMode: .aspectFit,
                options: requestOptions
            ) { image, _ in
                if let validImage = image {
                    Task { @MainActor in
                        self.addLocalImage(validImage)
                    }
                }
            }
            newPhotosCount += 1
        }

        syncProgressText = "Đã xếp hàng \(newPhotosCount) ảnh"
        await triggerSyncAll()
    }

    @MainActor
    func addLocalImage(_ image: UIImage) {
        let newItem = MediaItem(
            id: UUID().uuidString,
            messageId: nil,
            remoteURL: nil,
            localImage: image,
            timestamp: Date(),
            syncStatus: .localOnly,
            filename: "media_\(Int(Date().timeIntervalSince1970))_\(items.count).jpg",
            fileSize: image.jpegData(compressionQuality: 0.85)?.count ?? 0,
            isEncrypted: true
        )
        items.insert(newItem, at: 0)
    }

    @MainActor
    func triggerSyncAll() async {
        guard DiscordService.isLoggedIn else {
            syncProgressText = "Vui lòng kết nối Discord"
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
            syncProgressText = "Tất cả file đã được sao lưu"
            isSyncing = false
            return
        }

        for (index, idx) in pendingIndices.enumerated() {
            syncProgressText = "Đang mã hóa & tải lên \(index + 1)/\(pendingIndices.count)..."
            items[idx].syncStatus = .syncing(progress: 0.5)

            if let image = items[idx].localImage, let jpegData = image.jpegData(compressionQuality: 0.85) {
                do {
                    let result = try await DiscordService.shared.uploadMedia(
                        imageData: jpegData,
                        filename: items[idx].filename
                    )
                    items[idx].syncStatus = .synced(remoteURL: result.url)
                    items[idx].remoteURL = result.url
                    items[idx].messageId = result.messageId
                    items[idx].fileSize = jpegData.count
                } catch {
                    items[idx].syncStatus = .failed
                }
            }
        }

        isSyncing = false
        syncProgressText = "Đồng bộ hoàn tất"
    }

    @MainActor
    func deleteItem(_ item: MediaItem) async {
        if let msgId = item.messageId {
            try? await DiscordService.shared.deleteMedia(messageId: msgId)
        }
        items.removeAll { $0.id == item.id }
    }

    @MainActor
    func deleteMultipleItems(ids: Set<String>) async {
        let targets = items.filter { ids.contains($0.id) }
        for target in targets {
            if let msgId = target.messageId {
                try? await DiscordService.shared.deleteMedia(messageId: msgId)
            }
        }
        items.removeAll { ids.contains($0.id) }
    }

    @MainActor
    func freeUpLocalMemory() {
        for idx in items.indices {
            if case .synced = items[idx].syncStatus {
                items[idx].localImage = nil
            }
        }
        syncProgressText = "Đã giải phóng bộ nhớ đệm máy"
    }
}
