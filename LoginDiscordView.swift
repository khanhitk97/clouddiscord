import SwiftUI

struct LoginDiscordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tokenInput: String = DiscordService.botToken
    @State private var channelInput: String = DiscordService.channelId
    @State private var isVerifying = false
    @State private var errorMessage: String?
    var onLoginSuccess: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "5865F2").opacity(0.25), Color(hex: "0D0E12")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "5865F2"))
                                .frame(width: 70, height: 70)
                                .shadow(color: Color(hex: "5865F2").opacity(0.5), radius: 15, y: 5)
                            
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                        }

                        Text("Kết Nối Discord Storage")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Text("Nhập thông tin Bot để đồng bộ ảnh của bạn")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DISCORD BOT TOKEN")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.gray)

                            SecureField("Dán Bot Token tại đây...", text: $tokenInput)
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("CHANNEL ID LƯU TRỮ")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.gray)

                            TextField("Nhập Channel ID...", text: $channelInput)
                                .keyboardType(.numberPad)
                                .padding()
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    Button(action: handleConnect) {
                        HStack {
                            if isVerifying {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("Lưu & Kết Nối")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: "5865F2"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                        .shadow(color: Color(hex: "5865F2").opacity(0.4), radius: 10, y: 4)
                    }
                    .disabled(tokenInput.isEmpty || channelInput.isEmpty || isVerifying)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Đóng") { dismiss() }
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    private func handleConnect() {
        isVerifying = true
        errorMessage = nil
        
        let trimmedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedChannel = channelInput.trimmingCharacters(in: .whitespacesAndNewlines)

        DiscordService.botToken = trimmedToken
        DiscordService.channelId = trimmedChannel

        Task {
            let isValid = await DiscordService.shared.verifyConnection()
            await MainActor.run {
                isVerifying = false
                if isValid {
                    onLoginSuccess()
                    dismiss()
                } else {
                    errorMessage = "Bot Token không hợp lệ hoặc Bot chưa được thêm vào server!"
                }
            }
        }
    }
}
