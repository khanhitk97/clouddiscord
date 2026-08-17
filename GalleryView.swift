import SwiftUI

struct GalleryView: View {
    @State private var viewModel = GalleryViewModel()
    @State private var selectedItem: MediaItem?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // 1. Lưới ảnh chính
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(viewModel.items) { item in
                            MediaThumbnailCell(item: item)
                                .aspectRatio(1, contentMode: .fill)
                                .clipped()
                                .onTapGesture {
                                    selectedItem = item
                                }
                        }
                    }
                    .padding(.bottom, 90) // Tránh che khuất bởi thanh Sync Bar
                }

                // 2. Thanh trạng thái nổi Glassmorphism ở đáy
                FloatingSyncBar(
                    isSyncing: viewModel.isSyncing,
                    progressText: viewModel.syncProgressText,
                    onSyncTap: {
                        Task { await viewModel.triggerSyncAll() }
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .navigationTitle("Ảnh")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedItem) { item in
                DetailMediaViewer(item: item)
            }
        }
    }
}

// Cell hiển thị từng ảnh + Badge trạng thái Discord
struct MediaThumbnailCell: View {
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.secondary.opacity(0.15)
            Image(uiImage: item.image)
                .resizable()
                .scaledToFit()
                .padding(15)

            // Badge trạng thái đồng bộ & bảo mật
            HStack(spacing: 4) {
                if item.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                }

                switch item.syncStatus {
                case .synced:
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.cyan)
                case .syncing:
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                case .localOnly:
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                case .failed:
                    Image(systemName: "exclamationmark.icloud.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(6)
        }
    }
}

// Thanh Sync Bar kính mờ phong cách Apple
struct FloatingSyncBar: View {
    let isSyncing: Bool
    let progressText: String
    let onSyncTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSyncing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Discord Storage")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(progressText)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()

            Button(action: onSyncTap) {
                Text(isSyncing ? "Đang chạy" : "Đồng bộ")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.cyan, in: Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(isSyncing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
}

// Màn hình xem chi tiết ảnh
struct DetailMediaViewer: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFit()
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
