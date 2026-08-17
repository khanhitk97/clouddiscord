import SwiftUI

struct CloudDashboardSheet: View {
    var viewModel: GalleryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0D0E12").ignoresSafeArea()

                VStack(spacing: 20) {
                    // Thẻ tròn chỉ số dung lượng TeraBox Style
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 10)
                                .frame(width: 130, height: 130)

                            Circle()
                                .trim(from: 0, to: 0.75)
                                .stroke(
                                    LinearGradient(colors: [Color(hex: "5865F2"), Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                )
                                .frame(width: 130, height: 130)
                                .rotationEffect(.degrees(-90))

                            VStack(spacing: 2) {
                                Text(viewModel.totalCloudStorageFormatted)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.white)
                                Text("Đã lưu")
                                    .font(.caption2)
                                    .foregroundStyle(Color.gray)
                            }
                        }
                        .padding(.top, 20)

                        Text("Dung lượng Cloud: Không giới hạn")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.cyan)
                    }

                    // Thông số chi tiết
                    VStack(spacing: 12) {
                        HStack {
                            Text("Tổng số file trên Discord:")
                                .font(.subheadline)
                                .foregroundStyle(Color.gray)
                            Spacer()
                            Text("\(viewModel.items.count) mục")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.white)
                        }
                        Divider().background(Color.white.opacity(0.1))

                        HStack {
                            Text("Mã hóa bảo mật:")
                                .font(.subheadline)
                                .foregroundStyle(Color.gray)
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.green)
                                Text("AES-GCM-256")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.white)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)

                    Spacer()

                    // Nút Giải Phóng Dung Lượng
                    Button(action: {
                        viewModel.freeUpLocalMemory()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Giải phóng bộ nhớ đệm máy")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color(hex: "5865F2"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Trung tâm Lưu trữ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                        .foregroundStyle(Color.white)
                }
            }
        }
    }
}
