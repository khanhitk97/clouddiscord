import SwiftUI
import PhotosUI

struct GalleryView: View {
    @State private var viewModel = GalleryViewModel()
    @State private var selectedItem: MediaItem?
    @State private var showLoginSheet = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(hex: "0D0E12").ignoresSafeArea()

                ScrollView {
                    // Thẻ trạng thái kết nối Cloud
                    CloudStatusCard(
                        isLoggedIn: DiscordService.isLoggedIn,
                        itemCount: viewModel.items.count,
                        onLoginTap: { showLoginSheet = true }
                    )
                    .padding(.horizontal, CGFloat(16))
                    .padding(.top, CGFloat(10))

                    // Lưới hiển thị ảnh
                    if viewModel.items.isEmpty && !viewModel.isLoadingCloud {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.gray.opacity(0.5))
                            Text("Chưa có ảnh nào trên Discord Cloud")
                                .font(.subheadline)
                                .foregroundStyle(Color.gray)
                        }
                        .padding(.top, CGFloat(80))
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(viewModel.items) { item in
                                ModernPhotoCard(item: item)
                                    .onTapGesture { selectedItem = item }
                            }
                        }
                        .padding(CGFloat(16))
                        .padding(.bottom, CGFloat(90))
                    }
                }
                .refreshable {
                    await viewModel.loadCloudMedia()
                }

                // Thanh điều khiển đồng bộ ghim đáy
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
                .padding(.horizontal, CGFloat(16))
                .padding(.bottom, CGFloat(12))
            }
            .navigationTitle("Discord Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: "5865F2"))
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showLoginSheet = true }) {
                        Image(systemName: DiscordService.isLoggedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(DiscordService.isLoggedIn ? Color.green : Color.orange)
                    }
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                LoginDiscordView {
                    Task {
                        await viewModel.loadCloudMedia()
                        await viewModel.triggerSyncAll()
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
}

// 1. Thẻ hiển thị từng ảnh
struct ModernPhotoCard: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let local = item.localImage {
                    Image(uiImage: local)
                        .resizable()
                        .scaledToFill()
                } else if let remoteURLString = item.remoteURL, let url = URL(string: remoteURLString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                Color.white.opacity(0.05)
                                ProgressView().controlSize(.small).tint(.gray)
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            ZStack {
                                Color.white.opacity(0.05)
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(Color.gray)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .frame(height: 115)
            .clipped()
            .background(Color.white.opacity(0.04))

            // Badge trạng thái
            HStack(spacing: 4) {
                switch item.syncStatus {
                case .synced:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.green)
                case .syncing:
                    ProgressView().controlSize(.mini).tint(.white)
                case .localOnly:
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.8))
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red)
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
            .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 5, y: 3)
    }
}

// 2. Thẻ trạng thái Server / Account
struct CloudStatusCard: View {
    let isLoggedIn: Bool
    let itemCount: Int
    var onLoginTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isLoggedIn ? Color(hex: "5865F2").opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Image(systemName: isLoggedIn ? "externaldrive.badge.checkmark" : "bolt.slash.fill")
                    .foregroundStyle(isLoggedIn ? Color(hex: "5865F2") : Color.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isLoggedIn ? "Discord Storage Đã Kết Nối" : "Chưa Kết Nối Discord")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)

                Text(isLoggedIn ? "\(itemCount) mục trong kho lưu trữ" : "Bấm để thiết lập Bot Token")
                    .font(.caption)
                    .foregroundStyle(Color.gray)
            }

            Spacer()

            if !isLoggedIn {
                Button("Kết nối", action: onLoginTap)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, CGFloat(12))
                    .padding(.vertical, CGFloat(6))
                    .background(Color(hex: "5865F2"))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding(CGFloat(12))
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// 3. Thanh điều khiển đồng bộ ghim đáy
struct ModernSyncBar: View {
    let isSyncing: Bool
    let progressText: String
    let onSyncTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "5865F2").opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "5865F2"))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(progressText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white)
            }

            Spacer()

            Button(action: onSyncTap) {
                Text(isSyncing ? "Đang xử lý..." : "Đồng bộ")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal, CGFloat(16))
                    .padding(.vertical, CGFloat(8))
                    .background(Color(hex: "5865F2"))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.white)
            }
            .disabled(isSyncing)
        }
        .padding(.horizontal, CGFloat(16))
        .padding(.vertical, CGFloat(10))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, y: 6)
    }
}

// 4. Chi tiết xem ảnh phóng to
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
                        .foregroundStyle(Color.white)
                }
            }
        }
    }
}
