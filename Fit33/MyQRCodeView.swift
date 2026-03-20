import SwiftUI

/// View displaying the user's personal QR code for friends to scan
struct MyQRCodeView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var qrService = QRCodeService.shared
    
    @State private var showShareSheet = false
    @State private var qrCodeImage: UIImage?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // QR Code Card
                        qrCodeCard
                        
                        // Instructions
                        instructionsSection
                        
                        // Share Button
                        shareButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("My QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .task {
            await qrService.fetchMyQRCode()
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = qrCodeImage {
                ShareSheet(items: [image])
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "qrcode")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Share Your Code")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Friends can scan this to add you instantly")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - QR Code Card
    
    private var qrCodeCard: some View {
        VStack(spacing: 16) {
            if qrService.isLoading {
                loadingView
            } else if let qrData = qrService.myQRCode {
                qrCodeContent(qrData)
            } else {
                errorView
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(colorScheme == .dark ? Color(.systemGray6) : .white)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        )
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading your QR code...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 280)
    }
    
    private func qrCodeContent(_ qrData: QRCodeService.MyQRCodeData) -> some View {
        VStack(spacing: 16) {
            // User name/username above QR code
            VStack(spacing: 4) {
                if let name = qrData.userName {
                    Text(name)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                if let username = qrData.username {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            
            // QR Code Image
            let qrString = QRCodeService.createQRCodeURL(for: qrData.qrCodeId)
            QRCodeImageView(
                qrCodeString: qrString,
                size: 220,
                foregroundColor: colorScheme == .dark ? .white : .black,
                backgroundColor: colorScheme == .dark ? Color(.systemGray6) : .white
            )
            .padding(Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
            )
            .onAppear {
                // Generate image for sharing
                qrCodeImage = QRCodeService.generateStyledQRCode(
                    from: qrString,
                    size: CGSize(width: 600, height: 600),
                    foregroundColor: .black,
                    backgroundColor: .white
                )
            }
            
            // QR Code ID (for manual entry)
            Text(qrData.qrCodeId)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(.systemGray5))
                )
        }
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("Couldn't load QR code")
                .font(.headline)
            
            if let error = qrService.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Try Again") {
                Task {
                    await qrService.fetchMyQRCode()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(height: 280)
    }
    
    // MARK: - Instructions
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works")
                .font(.headline)
            
            InstructionRow(
                number: "1",
                icon: "camera.fill",
                text: "Friend opens the QR scanner in Fit33"
            )
            
            InstructionRow(
                number: "2",
                icon: "qrcode.viewfinder",
                text: "They scan your code with their camera"
            )
            
            InstructionRow(
                number: "3",
                icon: "person.badge.plus",
                text: "Instant friend request sent!"
            )
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
    
    // MARK: - Share Button
    
    private var shareButton: some View {
        Button(action: {
            HapticManager.impact(.medium)
            showShareSheet = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Share QR Code")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
        }
        .disabled(qrCodeImage == nil)
        .opacity(qrCodeImage == nil ? 0.5 : 1)
    }
}

// MARK: - Instruction Row

private struct InstructionRow: View {
    let number: String
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Number badge
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            
            // Icon
            Image(systemName: icon)
                .font(.ds_bodyRegular)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            // Text
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    MyQRCodeView()
}
