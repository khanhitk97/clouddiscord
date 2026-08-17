import SwiftUI
import PhotosUI
import AVKit

struct GalleryView: View {
    @State private var viewModel = GalleryViewModel()
    @State private var selectedItem: MediaItem?
    @State private var showLoginSheet = false
    @State private var showDashboardSheet = false
    @State private var showUploadOptions = false
    @State private var showPhotosPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    @State private var isSelectingMultiple = false
    @State private var selectedItemIDs: Set<String> = []
    @State private var isProcessingAction = false
    @State private var showDeleteConfirm = false
    @State private var downloadToastMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(hex: "0D0E12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 8) {
                        CloudStatusCard(
                            isLoggedIn: DiscordService.isLoggedIn,
                            itemCount: viewModel.items.count,
                            storageText: viewModel.totalCloudStorageFormatted,
                            onCardTap: {
                                if DiscordService.isLoggedIn {
                                    showDashboardSheet = true
                                } else {
                                    showLoginSheet = true
                                }
                            }
                        )
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                        if viewModel.items.isEmpty && !viewModel.isLoadingCloud {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 30))
                                    .foregroundStyle(Color.gray.opacity(0.4))
                                Text("Chưa có ảnh trên Discord Cloud")
                                    .font(.caption)
                                    .foregroundStyle(Color.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        } else {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(viewModel.items) { item in
                                    SelectableMediaCard(
                                        viewModel: viewModel,
                                        item: item,
                                        isSelectMode: isSelectingMultiple,
                                        isSelected: selectedItemIDs.contains(item.id)
                                    )
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .clipped()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isSelectingMultiple {
                                            toggleSelection(for: item.id)
                                        } else {
                                            selectedItem = item
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await viewModel.loadCloudMedia()
                }

                if isSelectingMultiple {
                    MultiSelectBottomBar(
                        selectedCount: selectedItemIDs.count,
                        isProcessing: isProcessingAction,
                        onDownloadTap: downloadSelectedItems,
                        onDeleteTap: { showDeleteConfirm = true },
                        onCancelTap: {
                            isSelectingMultiple = false
                            selectedItemIDs.removeAll()
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                } else {
                    ModernSyncBar(
                        isSyncing: viewModel.isSyncing,
                        progressText: viewModel.syncProgressText,
                        onSyncTap: {
                            if !DiscordService.isLoggedIn {
                                showLoginSheet = true
                            } else {
                                Task { await viewModel.triggerSyncAll() }
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                if let message = downloadToastMessage {
                    Text(message)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .foregroundStyle(Color.white)
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(isSelectingMultiple ? "Đã chọn \(selectedItemIDs.count)" : "Discord Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSelectingMultiple {
                        Button("Hủy") {
                            isSelectingMultiple = false
                            selectedItemIDs.removeAll()
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.gray)
                    } else {
                        Button(action: { showLoginSheet = true }) {
                            Image(systemName: DiscordService.isLoggedIn ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(DiscordService.isLoggedIn ? Color.green : Color.orange)
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !viewModel.items.isEmpty {
                        Button(isSelectingMultiple ? "Xong" : "Chọn") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectingMultiple.toggle()
                                if !isSelectingMultiple {
                                    selectedItemIDs.removeAll()
                                }
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "5865F2"))
                    }

                    if !isSelectingMultiple {
                        Button(action: handleUploadButtonTap) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: "5865F2"))
                        }
                    }
                }
            }
            .sheet(isPresented: $showDashboardSheet) {
                CloudDashboardSheet(viewModel: viewModel)
            }
            .confirmationDialog("Xác nhận xóa", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Xóa \(selectedItemIDs.count) mục khỏi Cloud", role: .destructive) {
                    deleteSelectedItems()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Các file này sẽ bị xóa khỏi máy chủ Discord.")
            }
            .confirmationDialog("Lựa chọn chế độ sao lưu", isPresented: $showUploadOptions, titleVisibility: .visible) {
                Button("Đồng bộ tất cả thư viện (Tự động)") {
                    viewModel.setAutoFullSync(true)
                    Task { await viewModel.syncAllDevicePhotos() }
                }
                Button("Chọn từng ảnh từ máy") {
                    showPhotosPicker = true
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Chọn 'Đồng bộ tất cả' sẽ tự động sao lưu toàn bộ thư viện ảnh mà không cần hỏi lại ở các lần sau.")
            }
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $selectedPhotos,
                maxSelectionCount: 50,
                matching: .images
            )
            .sheet(isPresented: $showLoginSheet) {
                LoginDiscordView {
                    Task {
                        await viewModel.loadCloudMedia()
                        if viewModel.isAutoFullSyncEnabled {
                            await viewModel.syncAllDevicePhotos()
                        }
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                DetailMediaViewer(viewModel: viewModel, item: item, onDelete: {
                    Task {
                        await viewModel.deleteItem(item)
                        showToast(message: "Đã xóa ảnh khỏi Cloud")
                    }
                })
            }
            .onChange(of: selectedPhotos) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            await MainActor.run {
                                viewModel.addLocalImage(image)
                            }
                        }
                    }
                    selectedPhotos.removeAll()
                    await viewModel.triggerSyncAll()
                }
            }
        }
    }

    private func toggleSelection(for id: String) {
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    private func handleUploadButtonTap() {
        if !DiscordService.isLoggedIn {
            showLoginSheet = true
            return
        }
        if viewModel.isAutoFullSyncEnabled {
            Task { await viewModel.syncAllDevicePhotos() }
        } else {
            showUploadOptions = true
        }
    }

    private func downloadSelectedItems() {
        guard !selectedItemIDs.isEmpty else { return }
        isProcessingAction = true

        let itemsToDownload = viewModel.items.filter { selectedItemIDs.contains($0.id) }

        Task {
            var successCount = 0
            for item in itemsToDownload {
                if let local = item.localImage {
                    UIImageWriteToSavedPhotosAlbum(local, nil, nil, nil)
                    successCount += 1
                } else if let remoteURL = item.remoteURL, let url = URL(string: remoteURL) {
                    if let rawData = try? await viewModel.downloadAndDecryptMedia(url: url, isEncrypted: item.isEncrypted),
                       let img = UIImage(data: rawData) {
                        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                        successCount += 1
                    }
                }
            }

            await MainActor.run {
                isProcessingAction = false
                isSelectingMultiple = false
                selectedItemIDs.removeAll()
                showToast(message: "Đã lưu \(successCount) mục vào Thư viện ảnh")
            }
        }
    }

    private func deleteSelectedItems() {
        isProcessingAction = true
        let targetIDs = selectedItemIDs

        Task {
            await viewModel.deleteMultipleItems(ids: targetIDs)
            await MainActor.run {
                isProcessingAction = false
                isSelectingMultiple = false
                selectedItemIDs.removeAll()
                showToast(message: "Đã xóa các mục khỏi Cloud")
            }
        }
    }

    private func showToast(message: String) {
        withAnimation { downloadToastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { downloadToastMessage = nil }
        }
    }
}

struct SelectableMediaCard: View {
    var viewModel: GalleryViewModel
    let item: MediaItem
    let isSelectMode: Bool
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Group {
                    if let local = item.localImage {
                        Image(uiImage: local)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else if let remoteURLString = item.remoteURL, let url = URL(string: remoteURLString) {
                        DecryptedThumbnailView(viewModel: viewModel, url: url, isEncrypted: item.isEncrypted)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                }

                if isSelectMode {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color(hex: "5865F2") : Color.black.opacity(0.4))
                            .frame(width: 18, height: 18)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                        } else {
                            Circle()
                                .stroke(Color.white, lineWidth: 1.5)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .padding(3)
                }

                if !isSelectMode {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 1) {
                                switch item.syncStatus {
                                case .synced:
                                    Image(systemName: item.isEncrypted ? "lock.fill" : "checkmark.circle.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(item.isEncrypted ? Color.green : Color.cyan)
                                case .syncing:
                                    ProgressView().controlSize(.mini).tint(.white)
                                case .localOnly:
                                    Image(systemName: "arrow.up.circle")
                                        .font(.system(size: 7))
                                        .foregroundStyle(Color.white.opacity(0.8))
                                case .failed:
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(Color.red)
                                }
                            }
                            .padding(2)
                            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
                            .padding(2)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white.opacity(0.02))
    }
}

struct DecryptedThumbnailView: View {
    var viewModel: GalleryViewModel
    let url: URL
    let isEncrypted: Bool
    @State private var uiImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                Color.white.opacity(0.04)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.gray)
            }
        }
        .task {
            if let data = try? await viewModel.downloadAndDecryptMedia(url: url, isEncrypted: isEncrypted),
               let img = UIImage(data: data) {
                await MainActor.run {
                    self.uiImage = img
                    self.isLoading = false
                }
            } else {
                await MainActor.run { self.isLoading = false }
            }
        }
    }
}

struct CloudStatusCard: View {
    let isLoggedIn: Bool
    let itemCount: Int
    var storageText: String = "0 MB"
    var onCardTap: () -> Void

    var body: some View {
        Button(action: onCardTap) {
            HStack(spacing: 10) {
                Image(systemName: isLoggedIn ? "externaldrive.badge.checkmark" : "bolt.slash.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(isLoggedIn ? Color(hex: "5865F2") : Color.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text(isLoggedIn ? "Discord Storage • \(storageText)" : "Chưa kết nối Cloud")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.white)

                    Text(isLoggedIn ? "\(itemCount) file an toàn • Xem Dashboard" : "Chạm để cấu hình Bot Token")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct ModernSyncBar: View {
    let isSyncing: Bool
    let progressText: String
    let onSyncTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isSyncing {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "5865F2"))
            }

            Text(progressText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.white)
                .lineLimit(1)

            Spacer()

            Button(action: onSyncTap) {
                Text(isSyncing ? "Đang chạy" : "Đồng bộ")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(hex: "5865F2"))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.white)
            }
            .disabled(isSyncing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
    }
}

struct MultiSelectBottomBar: View {
    let selectedCount: Int
    let isProcessing: Bool
    let onDownloadTap: () -> Void
    let onDeleteTap: () -> Void
    let onCancelTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancelTap) {
                Text("Hủy")
                    .font(.caption)
                    .foregroundStyle(Color.gray)
            }

            Spacer()

            Button(action: onDeleteTap) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedCount > 0 ? Color.red.opacity(0.8) : Color.gray.opacity(0.3))
                    .clipShape(Circle())
                    .foregroundStyle(Color.white)
            }
            .disabled(selectedCount == 0 || isProcessing)

            Button(action: onDownloadTap) {
                HStack(spacing: 5) {
                    if isProcessing {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.down.to.line.circle.fill")
                            .font(.system(size: 13))
                    }
                    Text(isProcessing ? "Đang xử lý..." : "Tải về (\(selectedCount))")
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selectedCount > 0 ? Color(hex: "5865F2") : Color.gray.opacity(0.3))
                .clipShape(Capsule())
                .foregroundStyle(Color.white)
            }
            .disabled(selectedCount == 0 || isProcessing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
    }
}

struct DetailMediaViewer: View {
    var viewModel: GalleryViewModel
    let item: MediaItem
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var decryptedImage: UIImage?
    @State private var isDownloadingSingle = false
    @State private var downloadedToast = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let local = item.localImage {
                    Image(uiImage: local)
                        .resizable()
                        .scaledToFit()
                } else if let img = decryptedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }

                if downloadedToast {
                    VStack {
                        Spacer()
                        Text("Đã lưu vào Camera Roll")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .foregroundStyle(Color.white)
                            .padding(.bottom, 40)
                    }
                }
            }
            .task {
                if let remoteURLString = item.remoteURL, let url = URL(string: remoteURLString) {
                    if let rawData = try? await viewModel.downloadAndDecryptMedia(url: url, isEncrypted: item.isEncrypted),
                       let img = UIImage(data: rawData) {
                        await MainActor.run { self.decryptedImage = img }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: saveSingleMedia) {
                        HStack(spacing: 4) {
                            if isDownloadingSingle {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                Text("Lưu")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "5865F2"))
                    }
                    .disabled(isDownloadingSingle)

                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(Color.red)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                        .font(.body)
                        .foregroundStyle(Color.white)
                }
            }
            .confirmationDialog("Xác nhận xóa", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Xóa vĩnh viễn khỏi Cloud", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("File này sẽ bị xóa khỏi kênh Discord và không thể khôi phục.")
            }
        }
    }

    private func saveSingleMedia() {
        isDownloadingSingle = true
        Task {
            if let local = item.localImage {
                UIImageWriteToSavedPhotosAlbum(local, nil, nil, nil)
            } else if let img = decryptedImage {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
            }
            await MainActor.run {
                isDownloadingSingle = false
                withAnimation { downloadedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { downloadedToast = false }
                }
            }
        }
    }
}
