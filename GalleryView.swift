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
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // Lưới hiển thị ảnh thực tế
                    if viewModel.items.isEmpty && !viewModel.isLoadingCloud {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 44))
                                .foregroundStyle(.gray.opacity(0.5))
                            Text("Chưa có ảnh nào trên Discord Cloud")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        }
                        .padding(.top, 80)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(viewModel.items) { item in
                                ModernPhotoCard(item: item)
                                    .onTapGesture { selectedItem = item }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 90)
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
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
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
                            .foregroundStyle(DiscordService.isLoggedIn ? .green : .orange)
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

// Thẻ hiển thị ảnh: Render cả ảnh cục bộ lẫn ảnh tải từ Discord CDN
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
                                    .foregroundStyle(.gray)
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
                        .foregroundStyle(.green)
                case .syncing:
                    ProgressView().controlSize(.mini).tint(.white)
                case .localOnly:
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.8))
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
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
        .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
    }
}

// Chi tiết xem ảnh phóng to
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
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
