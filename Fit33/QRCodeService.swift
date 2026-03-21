import Foundation
import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - QR Code Service
/// Handles QR code generation and friend lookup via QR codes
@MainActor
class QRCodeService: ObservableObject {
    static let shared = QRCodeService()
    
    @Published var myQRCode: MyQRCodeData?
    @Published var isLoading = false
    @Published var error: String?
    
    private init() {}
    
    // MARK: - Data Models
    
    struct MyQRCodeData: Codable {
        let qrCodeId: String
        let userName: String?
        let username: String?
        let profilePhotoUrl: String?
        
        enum CodingKeys: String, CodingKey {
            case qrCodeId = "qr_code_id"
            case userName = "user_name"
            case username
            case profilePhotoUrl = "profile_photo_url"
        }
    }
    
    struct ScannedUserData: Codable, Identifiable {
        let userId: UUID
        let userName: String?
        let username: String?
        let profilePhotoUrl: String?
        let fitnessGoal: String?
        let experienceLevel: String?
        let isAlreadyFriend: Bool
        let hasPendingRequest: Bool
        let requestDirection: String? // "sent" or "received"
        
        var id: UUID { userId }
        
        var displayName: String {
            if let username = username, !username.isEmpty {
                return "@\(username)"
            }
            return userName ?? "Unknown User"
        }
        
        var initials: String {
            guard let name = userName, !name.isEmpty else {
                if let username = username, !username.isEmpty {
                    return String(username.prefix(2)).uppercased()
                }
                return "?"
            }
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case userName = "user_name"
            case username
            case profilePhotoUrl = "profile_photo_url"
            case fitnessGoal = "fitness_goal"
            case experienceLevel = "experience_level"
            case isAlreadyFriend = "is_already_friend"
            case hasPendingRequest = "has_pending_request"
            case requestDirection = "request_direction"
        }
    }
    
    struct AddFriendResult: Codable {
        let success: Bool
        let message: String
        let requestId: UUID?
        let friendUserId: UUID?
        let friendName: String?
        let status: String // request_sent, already_friends, already_pending, request_accepted, user_not_found, error
        
        enum CodingKeys: String, CodingKey {
            case success
            case message
            case requestId = "request_id"
            case friendUserId = "friend_user_id"
            case friendName = "friend_name"
            case status
        }
    }
    
    // MARK: - Fetch My QR Code
    
    /// Fetches the current user's QR code data
    func fetchMyQRCode() async {
        isLoading = true
        error = nil
        
        do {
            let result: [MyQRCodeData] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_my_qr_code")
                .execute()
                .value
            
            self.myQRCode = result.first
            AppLogger.info("✅ Fetched QR code: \(myQRCode?.qrCodeId ?? "none")", category: .social)
        } catch {
            self.error = "Failed to fetch QR code: \(error.localizedDescription)"
            AppLogger.error("❌ Error fetching QR code: \(error)", category: .social)
        }
        
        isLoading = false
    }
    
    // MARK: - Look Up User by QR Code
    
    /// Looks up a user by their scanned QR code
    func lookupUserByQRCode(_ qrCode: String) async -> ScannedUserData? {
        do {
            let result: [ScannedUserData] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_user_by_qr_code", params: ["scanned_code": qrCode])
                .execute()
                .value
            
            AppLogger.info("✅ Found user by QR code: \(result.first?.displayName ?? "none")", category: .social)
            return result.first
        } catch {
            AppLogger.error("❌ Error looking up user by QR code: \(error)", category: .social)
            return nil
        }
    }
    
    // MARK: - Add Friend via QR Code
    
    /// Sends a friend request using the scanned QR code
    func addFriendByQRCode(_ qrCode: String, message: String? = nil) async -> AddFriendResult? {
        do {
            var params: [String: String] = ["scanned_code": qrCode]
            if let msg = message {
                params["request_message"] = msg
            }
            
            let results: [AddFriendResult] = try await SupabaseManager.shared.supabaseClient
                .rpc("add_friend_by_qr_code", params: params)
                .execute()
                .value
            
            let result = results.first
            AppLogger.info("✅ Add friend result: \(result?.status ?? "unknown") - \(result?.message ?? "")", category: .social)
            
            // Refresh friend data if successful
            if result?.success == true {
                await FriendService.shared.refreshAll()
            }
            
            return result
        } catch {
            AppLogger.error("❌ Error adding friend by QR code: \(error)", category: .social)
            return AddFriendResult(
                success: false,
                message: "Failed to send friend request: \(error.localizedDescription)",
                requestId: nil,
                friendUserId: nil,
                friendName: nil,
                status: "error"
            )
        }
    }
    
    // MARK: - QR Code Generation
    
    /// Generates a QR code image from a string
    static func generateQRCode(from string: String, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        // Set the QR code content
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction
        
        guard let outputImage = filter.outputImage else {
            return nil
        }
        
        // Scale the QR code to desired size
        let scaleX = size.width / outputImage.extent.width
        let scaleY = size.height / outputImage.extent.height
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Convert to UIImage
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Generates a styled QR code with custom colors
    static func generateStyledQRCode(
        from string: String,
        size: CGSize = CGSize(width: 200, height: 200),
        foregroundColor: UIColor = .black,
        backgroundColor: UIColor = .white
    ) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else {
            return nil
        }
        
        // Apply color filter
        let colorFilter = CIFilter.falseColor()
        colorFilter.setValue(outputImage, forKey: "inputImage")
        colorFilter.setValue(CIColor(color: foregroundColor), forKey: "inputColor0")
        colorFilter.setValue(CIColor(color: backgroundColor), forKey: "inputColor1")
        
        guard let coloredImage = colorFilter.outputImage else {
            return nil
        }
        
        // Scale the QR code
        let scaleX = size.width / coloredImage.extent.width
        let scaleY = size.height / coloredImage.extent.height
        let scaledImage = coloredImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Parse Scanned QR Code
    
    /// Validates and extracts the QR code ID from a scanned string
    static func parseQRCode(_ scannedString: String) -> String? {
        // Accept raw QR code ID (fit33_XXXXXXXX)
        if scannedString.hasPrefix("fit33_") && scannedString.count >= 14 {
            return scannedString
        }
        
        // Accept full URL format: fit33://friend/fit33_XXXXXXXX
        if let url = URL(string: scannedString),
           url.scheme == "fit33",
           url.host == "friend",
           let qrCode = url.pathComponents.last,
           qrCode.hasPrefix("fit33_") {
            return qrCode
        }
        
        // Accept web URL format: https://fit33.app/friend/fit33_XXXXXXXX
        if let url = URL(string: scannedString),
           url.pathComponents.contains("friend"),
           let qrCode = url.pathComponents.last,
           qrCode.hasPrefix("fit33_") {
            return qrCode
        }
        
        return nil
    }
    
    /// Creates a deep link URL for the QR code
    static func createQRCodeURL(for qrCodeId: String) -> String {
        // Use the custom URL scheme for easy scanning
        return "fit33://friend/\(qrCodeId)"
    }
}

// MARK: - SwiftUI QR Code View Helper

struct QRCodeImageView: View {
    let qrCodeString: String
    let size: CGFloat
    var foregroundColor: Color = .black
    var backgroundColor: Color = .white
    
    @State private var qrImage: UIImage?
    
    var body: some View {
        Group {
            if let image = qrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
        .onAppear {
            generateQRCode()
        }
        .onChange(of: qrCodeString) { _, _ in
            generateQRCode()
        }
    }
    
    private func generateQRCode() {
        qrImage = QRCodeService.generateStyledQRCode(
            from: qrCodeString,
            size: CGSize(width: size * 3, height: size * 3), // Generate at higher resolution
            foregroundColor: UIColor(foregroundColor),
            backgroundColor: UIColor(backgroundColor)
        )
    }
}
