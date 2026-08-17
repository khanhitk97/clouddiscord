import SwiftUI
import Observation
import Photos

@Observable
class GalleryViewModel {
    var items: [MediaItem] = [] {
        didSet {
            StorageManager.shared.saveItems(items)
        }
    }
    var isSyncing: Bool = false
    var isLoadingCloud: Bool = false
    var syncProgressText: String = "Sẵn sàng"
    var lastErrorMessage: String? = nil

    var isAutoFullSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "auto_full_sync_enabled")
    }

    func setAutoFullSync(_ enabled: Bool) {
        UserDefaults.standard.setValue(enabled, forKey: "auto_full_sync_enabled")
    }

    init() {
        self.items = StorageManager.shared.loadItems()
        Task {
            await loadCloudMedia()
        }
    }

    /// Kéo dữ liệu Cloud và thông báo từng dòng lỗi
    @MainActor
    func loadCloudMedia() async {
        guard DiscordService.isLoggedIn else {
            syncProgressText = "Chưa kết nối Bot Token & Channel ID"
            return
        }

        isLoadingCloud = true
        syncProgressText = "1/2: Đang kết nối Discord..."
        lastErrorMessage = nil

        do {
            try await DiscordService.shared.verifyConnection()
            
            syncProgressText = "2/2: Đang tải danh sách ảnh..."
            let cloudItems = try await DiscordService.shared.fetchChannelMedia()

            var currentMap: [String: MediaItem] = [:]
            for item in items {
                currentMap[item.id] = item
                if let msgId = item.messageId {
                    currentMap[msgId] = item
                }
            }

            for cItem in cloudItems {
                if let msgId = cItem.messageId, currentMap[msgId] == nil {
                    currentMap[msgId] = cItem
                } else if currentMap[cItem.id] == nil {
                    currentMap[cItem.id] = cItem
                }
            }

            self.items = Array(currentMap.values).sorted(by: { $0.timestamp > $1.timestamp })
            syncProgressText = "✅ Đã tải \(cloudItems.count) ảnh từ Cloud"
        } catch let err as DiscordAPIError {
            self.lastErrorMessage = err.localizedDescription
            self.syncProgressText = err.localizedDescription
        } catch {
            self.lastErrorMessage = "❌ Lỗi: \(error.localizedDescription)"
            self.syncProgressText = self.lastErrorMessage!
        }

        isLoadingCloud = false
    }

    @MainActor
    func syncAllDevicePhotos() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            syncProgressText = "❌ Chưa cấp quyền truy cập Ảnh trong Cài đặt iPhone"
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

        var count = 0
        allPhotos.enumerateObjects { asset, _, _ in
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 1200, height: 1200),
                contentMode: .aspectFit,
                options: requestOptions
            ) { image, _ in
                if let valid = image {
                    Task { @MainActor in
                        self.addLocalImage(valid)
                    }
                }
            }
            count += 1
        }

        syncProgressText = "Đã xếp hàng \(count) ảnh"
        await triggerSyncAll()
    }

    @MainActor
    func addLocalImage(_ image: UIImage) {
        let fileId = UUID().uuidString
        let filename = "photo_\(fileId).jpg"
        
        var localPathString: String? = nil
        if let jpegData = image.jpegData(compressionQuality: 0.8) {
            localPathString = StorageManager.shared.saveImageLocally(data: jpegData, filename: filename)
        }

        let newItem = MediaItem(
            id: fileId,
            messageId: nil,
            remoteURL: nil,
            localPath: localPathString,
            timestamp: Date(),
            syncStatus: .localOnly,
            filename: filename,
            fileSize: image.jpegData(compressionQuality: 0.8)?.count ?? 0
        )
        items.insert(newItem, at: 0)
    }

    /// Upload từng file và báo cáo lỗi nếu có
    @MainActor
    func triggerSyncAll() async {
        guard DiscordService.isLoggedIn else {
            syncProgressText = "❌ Vui lòng nhập Token & Channel ID"
            return
        }

        guard !isSyncing else { return }
        isSyncing = true
        lastErrorMessage = nil

        // Bước kiểm tra quyền trước khi gửi
        do {
            syncProgressText = "Đang kiểm tra quyền hạn Bot..."
            try await DiscordService.shared.verifyConnection()
        } catch {
            self.syncProgressText = error.localizedDescription
            self.lastErrorMessage = error.localizedDescription
            isSyncing = false
            return
        }

        let pendingIndices = items.indices.filter {
            if case .localOnly = items[$0].syncStatus { return true }
            if case .failed = items[$0].syncStatus { return true }
            return false
        }

        if pendingIndices.isEmpty {
            syncProgressText = "✅ Toàn bộ ảnh đã được lưu"
            isSyncing = false
            return
        }

        for (index, idx) in pendingIndices.enumerated() {
            syncProgressText = "Đang gửi ảnh [\(index + 1)/\(pendingIndices.count)] lên Discord..."
            items[idx].syncStatus = .syncing(progress: 0.3)

            guard let image = items[idx].localImage, let jpegData = image.jpegData(compressionQuality: 0.8) else {
                items[idx].syncStatus = .failed
                syncProgressText = "❌ Không đọc được dữ liệu ảnh gốc"
                continue
            }

            do {
                items[idx].syncStatus = .syncing(progress: 0.7)
                let result = try await DiscordService.shared.uploadMedia(
                    imageData: jpegData,
                    filename: items[idx].filename
                )
                
                items[idx].syncStatus = .synced(remoteURL: result.url)
                items[idx].remoteURL = result.url
                items[idx].messageId = result.messageId
                items[idx].fileSize = jpegData.count
                
                StorageManager.shared.saveItems(items)
            } catch {
                items[idx].syncStatus = .failed
                self.lastErrorMessage = error.localizedDescription
                self.syncProgressText = "❌ Lỗi: \(error.localizedDescription)"
                break
            }
        }

        isSyncing = false
        if lastErrorMessage == nil {
            syncProgressText = "✅ Đồng bộ thành công"
        }
    }

    @MainActor
    func deleteItem(_ item: MediaItem) async {
        if let msgId = item.messageId {
            try? await DiscordService.shared.deleteMedia(messageId: msgId)
        }
        if let path = item.localPath {
            StorageManager.shared.deleteLocalFile(path: path)
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
            if let path = target.localPath {
                StorageManager.shared.deleteLocalFile(path: path)
            }
        }
        items.removeAll { ids.contains($0.id) }
    }
}
