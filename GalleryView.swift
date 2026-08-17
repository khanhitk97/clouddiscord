import SwiftUI
import PhotosUI

struct GalleryView: View {
    @State private var viewModel = GalleryViewModel()
    @State private var selectedItem: MediaItem?
    @State private var showLoginSheet = false
    @State private var showUploadOptions = false
    @State private var showPhotosPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    // 1. Cấu hình lưới 5 cột ngang cố định
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(hex: "0D0E12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 8) {
                        // Thẻ Cloud Status
                        CloudStatusCard(
                            isLoggedIn: DiscordService.isLoggedIn,
                            itemCount: viewModel.items.count,
                            onLoginTap: { showLoginSheet = true }
                        )
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                        // Lưới ảnh 5 cột vuông vức
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
                                    ModernPhotoCard(item: item)
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(minWidth: 0, maxWidth: .infinity)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedItem = item }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await viewModel.loadCloudMedia()
                }

                // Floating Sync Bar
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
            .navigationTitle("Discord Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: handleUploadButtonTap) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: "5865F2"))
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showLoginSheet = true }) {
                        Image(systemName: DiscordService.isLoggedIn ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DiscordService.isLoggedIn ? Color.green : Color.orange)
                    }
                }
            }
            // Hộp thoại lựa chọn chế độ Upload
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
            // Trình chọn ảnh thủ công
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
            .onAppear {
                if viewModel.isAutoFullSyncEnabled && DiscordService.isLoggedIn {
                    Task { await viewModel.syncAllDevicePhotos() }
                }
            }
        }
    }

    private func handleUploadButtonTap() {
        if !DiscordService.isLoggedIn {
            showLoginSheet = true
            return
        }
        
        // Nếu đã bật tự động đồng bộ tất cả trước đó -> chạy luôn không hỏi
        if viewModel.isAutoFullSyncEnabled {
            Task { await viewModel.syncAllDevicePhotos() }
        } else {
            showUploadOptions = true
        }
    }
}

// Thẻ hiển thị từng ô vuông 5 cột
struct ModernPhotoCard: View {
    let item: MediaItem

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
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

                // Badge trạng thái nhỏ góc dưới
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
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white.opacity(0.02))
    }
}

struct CloudStatusCard: View {
    let isLoggedIn: Bool
    let itemCount: Int
    var onLoginTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isLoggedIn ? "externaldrive.badge.checkmark" : "bolt.slash.fill")
                .font(.system(size: 15))
                .foregroundStyle(isLoggedIn ? Color(hex: "5865F2") : Color.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(isLoggedIn ? "Discord Cloud Storage" : "Chưa kết nối Cloud")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white)

                Text(isLoggedIn ? "\(itemCount) ảnh trong kho" : "Chạm để cấu hình Bot Token")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.gray)
            }

            Spacer()

            if !isLoggedIn {
                Button("Kết nối", action: onLoginTap)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "5865F2"))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
    }
}

struct DetailMediaViewer: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let local = item.localImage {
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
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                        .font(.body)
                        .foregroundStyle(Color.white)
                }
            }
        }
    }
}
