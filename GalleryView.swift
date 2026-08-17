// Thẻ hiển thị ô vuông 5 cột kèm thanh tiến trình upload trực quan
struct SelectableMediaCard: View {
    let item: MediaItem
    let isSelectMode: Bool
    let isSelected: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
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

                // 1. LỚP PHỦ TIẾN TRÌNH KHI ĐANG ĐỒNG BỘ LÊN CLOUD
                if case .syncing(let progress) = item.syncStatus {
                    ZStack {
                        Color.black.opacity(0.45) // Làm tối nền để nổi bật thanh tiến trình
                        
                        // Vòng tròn tiến trình xoay quanh
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2.5)
                            .frame(width: 26, height: 26)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color(hex: "5865F2"), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .frame(width: 26, height: 26)
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                // Checkbox chọn nhiều ở góc trên
                if isSelectMode {
                    VStack {
                        HStack {
                            Spacer()
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
                        Spacer()
                    }
                }

                // 2. BADGE TRẠNG THÁI GÓC DƯỚI
                if !isSelectMode {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 1) {
                                switch item.syncStatus {
                                case .synced:
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.cyan)
                                case .localOnly:
                                    Image(systemName: "arrow.up.circle")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.white.opacity(0.8))
                                case .failed:
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.red)
                                case .syncing:
                                    EmptyView()
                                }
                            }
                            .padding(2)
                            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
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
