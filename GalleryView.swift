import SwiftUI
import PhotosUI
import AVKit

struct GalleryView: View {
    @State private var viewModel = GalleryViewModel()
    @State private var selectedItem: MediaItem?
    @State private var showLoginSheet = false
    @State private var showUploadOptions = false
    @State private var showPhotosPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    // Quản lý chế độ chọn nhiều
    @State private var isSelectingMultiple = false
    @State private var selectedItemIDs: Set<String> = []
    @State private var isDownloading = false
    @State private var downloadToastMessage: String?

    // Lưới 5 cột cố định, tỉ lệ vuông
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(hex: "0D0E12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 8) {
                        // Thẻ Cloud Status Card
                        CloudStatusCard(
                            isLoggedIn: DiscordService.isLoggedIn,
                            itemCount: viewModel.items.count,
                            onLoginTap: { showLoginSheet = true }
                        )
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                        // Lưới hiển thị ảnh/video
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

                // Thanh điều khiển ghim đáy: Tùy biến theo chế độ chọn nhiều hoặc đồng bộ
                if isSelectingMultiple {
                    MultiSelectBottomBar(
                        selectedCount: selectedItemIDs.count,
                        isDownloading: isDownloading,
                        onDownloadTap: downloadSelectedItems,
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

                // Thông báo Toast khi tải về thành công
                if let message = downloadToastMessage {
                    Text(message)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
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
                DetailMediaViewer(item: item)
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

    /// Tải nhiều ảnh/video về Camera Roll
    private func downloadSelectedItems() {
        guard !selectedItemIDs.isEmpty else { return }
        isDownloading = true

        let itemsToDownload = viewModel.items.filter { selectedItemIDs.contains($0.id) }

        Task {
            var successCount = 0
            for item in itemsToDownload {
                if let local = item.localImage {
                    UIImageWriteToSavedPhotosAlbum(local, nil, nil, nil)
                    successCount += 1
                } else if let remoteURL = item.remoteURL, let url = URL(string: remoteURL) {
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let img = UIImage(data: data) {
                        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                        successCount += 1
                    }
                }
            }

            await MainActor.run {
                isDownloading = false
                isSelectingMultiple = false
                selectedItemIDs.removeAll()
                showToast(message: "Đã lưu \(successCount) mục vào Thư viện ảnh")
            }
        }
    }

    private func showToast(message: String) {
        withAnimation {
            downloadToastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                downloadToastMessage = nil
            }
        }
    }
}

// Thẻ hiển thị ô ảnh hỗ trợ chế độ chọn
struct SelectableMediaCard: View {
    let item: MediaItem
    let isSelectMode: Bool
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                // Media Thumbnail
                Group {
                    if let local = item.localImage {
                        Image(uiImage: local)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else if let remoteURLString = item.remoteURL, let url = URL(string: remoteURLString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Color.white.opacity(0.04)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            case .failure:
                                ZStack {
                                    Color.white.opacity(0.04)
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.gray)
                                }
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }

                // Checkbox chọn nhiều ở góc trên
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

                // Badge đồng bộ ở góc dưới
                if !isSelectMode {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 1) {
                                switch item.syncStatus {
                                case .synced:
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(Color.cyan)
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

// Thanh thao tác khi chọn nhiều mục (Tải về / Hủy)
struct MultiSelectBottomBar: View {
    let selectedCount: Int
    let isDownloading: Bool
    let onDownloadTap: () -> Void
    let onCancelTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancelTap) {
                Text("Bỏ chọn")
                    .font(.caption)
                    .foregroundStyle(Color.gray)
            }

            Spacer()

            Button(action: onDownloadTap) {
                HStack(spacing: 6) {
                    if isDownloading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.down.to.line.circle.fill")
                            .font(.system(size: 14))
                    }
                    Text(isDownloading ? "Đang tải..." : "Tải về máy (\(selectedCount))")
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedCount > 0 ? Color(hex: "5865F2") : Color.gray.opacity(0.3))
                .clipShape(Capsule())
                .foregroundStyle(Color.white)
            }
            .disabled(selectedCount == 0 || isDownloading)
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

// Trình xem chi tiết Media (Phóng to, xem Video, Tải đơn)
struct DetailMediaViewer: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var isDownloadingSingle = false
    @State private var downloadedToast = false

    var isVideo: Bool {
        item.filename.lowercased().hasSuffix(".mp4") || item.filename.lowercased().hasSuffix(".mov")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isVideo, let remote = item.remoteURL, let videoURL = URL(string: remote) {
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .ignoresSafeArea()
                } else if let local = item.localImage {
                    Image(uiImage: local)
                        .resizable()
                        .scaledToFit()
                } else if let remoteURLString = item.remoteURL, let url = URL(string: remoteURLString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: saveSingleMedia) {
                        HStack(spacing: 4) {
                            if isDownloadingSingle {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                Text("Lưu về máy")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "5865F2"))
                    }
                    .disabled(isDownloadingSingle)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                        .font(.body)
                        .foregroundStyle(Color.white)
                }
            }
        }
    }

    private func saveSingleMedia() {
        isDownloadingSingle = true
        Task {
            if let local = item.localImage {
                UIImageWriteToSavedPhotosAlbum(local, nil, nil, nil)
            } else if let remoteURL = item.remoteURL, let url = URL(string: remoteURL) {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let img = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                }
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
