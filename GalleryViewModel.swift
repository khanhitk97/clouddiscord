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

    init() {
        Task {
            await loadCloudMedia()
        }
    }

    /// Kéo toàn bộ ảnh từ Discord
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
            syncProgressText = "Đã tải \(cloudItems.count) ảnh"
        } catch {
            syncProgressText = "Lỗi tải ảnh: \(error.localizedDescription)"
        }

        isLoadingCloud = false
    }

    /// Tự động quét toàn bộ thư viện ảnh của thiết bị và đưa vào hàng đợi
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
                targetSize: CGSize(width: 1200, height: 1200),
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

        syncProgressText = "Đã thêm \(newPhotosCount) ảnh vào hàng đợi"
        await triggerSyncAll()
    }

    @MainActor
    func addLocalImage(_ image: UIImage) {
        let newItem = MediaItem(
            id: UUID().uuidString,
            remoteURL: nil,
            localImage: image,
            timestamp: Date(),
            syncStatus: .localOnly,
            filename: "photo_\(Int(Date().timeIntervalSince1970))_\(items.count).jpg"
        )
        items.insert(newItem, at: 0)
    }

    /// Upload toàn bộ ảnh local chưa sync lên Discord
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
