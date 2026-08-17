import SwiftUI
import PhotosUI

struct GalleryView: View {
    @State private var viewModel = GalleryViewModel()
    @State private var selectedItem: MediaItem?
    @State private var showLoginSheet = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(hex: "0D0E12")
                    .ignoresSafeArea()

                // Scroll view chính
                ScrollView {
                    VStack(spacing: 8) {
                        CloudStatusCard(
                            isLoggedIn: DiscordService.isLoggedIn,
                            itemCount: viewModel.items.count,
                            onLoginTap: { showLoginSheet = true }
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                        if viewModel.items.isEmpty && !viewModel.isLoadingCloud {
                            VStack(spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color.gray.opacity(0.4))
                                Text("Chưa có ảnh trên Discord Cloud")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.gray)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        } else {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(viewModel.items) { item in
                                    ModernPhotoCard(item: item)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedItem = item }
                                }
                            }
                        }
                    }
                    // Khoảng đệm đáy để cuộn không bị che bởi Floating Sync Bar
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await viewModel.loadCloudMedia()
                }

                // Thanh Sync Bar nổi phía trên Home Indicator
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
                .padding(.bottom, 16)
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
                        Image(systemName: DiscordService.isLoggedIn ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 18))
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

struct ModernPhotoCard: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
                                Color.white.opacity(0.04)
                                ProgressView().controlSize(.mini).tint(.gray)
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            ZStack {
                                Color.white.opacity(0.04)
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.gray)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }

            HStack(spacing: 3) {
                switch item.syncStatus {
                case .synced:
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.cyan)
                case .syncing:
                    ProgressView().controlSize(.mini).tint(.white)
                case .localOnly:
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.85))
                case .failed:
                    Image(systemName: "exclamationmark.icloud.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red)
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
            .padding(4)
        }
        .background(Color.white.opacity(0.03))
    }
}

struct CloudStatusCard: View {
    let isLoggedIn: Bool
    let itemCount: Int
    var onLoginTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isLoggedIn ? "externaldrive.badge.checkmark" : "bolt.slash.fill")
                .font(.system(size: 18))
                .foregroundStyle(isLoggedIn ? Color(hex: "5865F2") : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(isLoggedIn ? "Discord Cloud Storage" : "Chưa kết nối Cloud")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.white)

                Text(isLoggedIn ? "\(itemCount) ảnh trong kho" : "Chạm để cấu hình Bot Token")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray)
            }

            Spacer()

            if !isLoggedIn {
                Button("Kết nối", action: onLoginTap)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color(hex: "5865F2"))
                    .foregroundStyle(Color.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ModernSyncBar: View {
    let isSyncing: Bool
    let progressText: String
    let onSyncTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSyncing {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "5865F2"))
            }

            Text(progressText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.white)
                .lineLimit(1)

            Spacer()

            Button(action: onSyncTap) {
                Text(isSyncing ? "Đang chạy" : "Đồng bộ")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "5865F2"))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.white)
            }
            .disabled(isSyncing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
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
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                }
            }
        }
    }
}
