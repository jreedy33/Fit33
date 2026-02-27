import SwiftUI
import AVFoundation

/// QR Code Scanner view for adding friends by scanning their QR code
struct QRCodeScannerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var scannedCode: String?
    @State private var scannedUser: QRCodeService.ScannedUserData?
    @State private var addFriendResult: QRCodeService.AddFriendResult?
    @State private var isProcessing = false
    @State private var showResultSheet = false
    @State private var cameraError: String?
    @State private var torchOn = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera view
                QRCodeCameraView(
                    scannedCode: $scannedCode,
                    torchOn: $torchOn,
                    onError: { error in
                        cameraError = error
                    }
                )
                .ignoresSafeArea()
                
                // Overlay
                VStack {
                    // Top controls
                    topControls
                    
                    Spacer()
                    
                    // Scanning frame
                    scanningFrame
                    
                    Spacer()
                    
                    // Instructions
                    instructionsCard
                }
                
                // Camera error overlay
                if let error = cameraError {
                    cameraErrorView(error)
                }
            }
            .navigationBarHidden(true)
            .onChange(of: scannedCode) { _, newValue in
                if let code = newValue {
                    handleScannedCode(code)
                }
            }
            .sheet(isPresented: $showResultSheet) {
                if let user = scannedUser {
                    ScannedUserSheet(
                        user: user,
                        result: addFriendResult,
                        isProcessing: $isProcessing,
                        onAddFriend: addFriend,
                        onDismiss: resetScanner,
                        onClose: { dismiss() }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }
    
    // MARK: - Top Controls
    
    private var topControls: some View {
        HStack {
            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            
            Spacer()
            
            // Title
            Text("Scan QR Code")
                .font(.headline)
                .foregroundColor(.white)
                .shadow(radius: 2)
            
            Spacer()
            
            // Torch toggle
            Button(action: {
                HapticManager.impact(.light)
                torchOn.toggle()
            }) {
                Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(torchOn ? .yellow : .white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }
    
    // MARK: - Scanning Frame
    
    private var scanningFrame: some View {
        ZStack {
            // Dimmed overlay with cutout
            Rectangle()
                .fill(.black.opacity(0.5))
                .mask(
                    ZStack {
                        Rectangle()
                        RoundedRectangle(cornerRadius: 24)
                            .frame(width: 280, height: 280)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )
            
            // Scanning frame border
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 280, height: 280)
            
            // Corner accents
            scanningCorners
            
            // Scanning line animation
            if scannedCode == nil {
                ScanningLineView()
                    .frame(width: 260, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }
    
    private var scanningCorners: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                CornerAccent()
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .frame(width: 280, height: 280)
    }
    
    // MARK: - Instructions Card
    
    private var instructionsCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 20))
                Text("Point at a friend's QR code")
                    .font(.subheadline)
            }
            .foregroundColor(.white)
            
            Text("Make sure the code is within the frame")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .background(
            Capsule()
                .fill(.black.opacity(0.6))
        )
        .padding(.bottom, 40)
    }
    
    // MARK: - Camera Error View
    
    private func cameraErrorView(_ error: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("Camera Access Required")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Open Settings") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.gray)
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func handleScannedCode(_ code: String) {
        guard !isProcessing else { return }
        
        // Parse and validate QR code
        guard let qrCodeId = QRCodeService.parseQRCode(code) else {
            // Invalid QR code - reset and continue scanning
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                scannedCode = nil
            }
            return
        }
        
        HapticManager.notification(.success)
        isProcessing = true
        
        // Look up user
        Task {
            if let user = await QRCodeService.shared.lookupUserByQRCode(qrCodeId) {
                await MainActor.run {
                    scannedUser = user
                    showResultSheet = true
                    isProcessing = false
                }
            } else {
                await MainActor.run {
                    HapticManager.notification(.error)
                    // Reset after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        scannedCode = nil
                        isProcessing = false
                    }
                }
            }
        }
    }
    
    private func addFriend() {
        guard let code = scannedCode,
              let qrCodeId = QRCodeService.parseQRCode(code) else { return }
        
        isProcessing = true
        
        Task {
            let result = await QRCodeService.shared.addFriendByQRCode(qrCodeId)
            await MainActor.run {
                addFriendResult = result
                isProcessing = false
                
                if result?.success == true {
                    HapticManager.notification(.success)
                } else {
                    HapticManager.notification(.error)
                }
            }
        }
    }
    
    private func resetScanner() {
        scannedCode = nil
        scannedUser = nil
        addFriendResult = nil
        showResultSheet = false
    }
}

// MARK: - Scanning Line Animation

private struct ScanningLineView: View {
    @State private var offset: CGFloat = -130
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .blue.opacity(0.5), .cyan.opacity(0.8), .blue.opacity(0.5), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: offset)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2)
                    .repeatForever(autoreverses: true)
                ) {
                    offset = 130
                }
            }
    }
}

// MARK: - Corner Accent

private struct CornerAccent: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 30, height: 4)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4, height: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
    }
}

// MARK: - Scanned User Sheet

private struct ScannedUserSheet: View {
    let user: QRCodeService.ScannedUserData
    let result: QRCodeService.AddFriendResult?
    @Binding var isProcessing: Bool
    let onAddFriend: () -> Void
    let onDismiss: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // User Avatar
                userAvatar
                
                // User Info
                userInfo
                
                // Status/Action
                if let result = result {
                    resultView(result)
                } else {
                    actionButtons
                }
                
                Spacer()
            }
            .padding(24)
            .navigationTitle("User Found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(result != nil ? "Done" : "Cancel") {
                        if result != nil {
                            onClose()
                        } else {
                            onDismiss()
                        }
                    }
                }
            }
        }
    }
    
    private var userAvatar: some View {
        ZStack {
            // Profile photo (cached) or initials
            LargeCachedFriendPhoto(
                friendId: user.userId.uuidString,
                photoUrl: user.profilePhotoUrl,
                name: user.userName ?? user.username ?? "?",
                size: 100,
                gradientColors: [.blue, .cyan]
            )
            
            // Status badge
            if user.isAlreadyFriend {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)
                    .background(Circle().fill(.white).padding(2))
                    .offset(x: 35, y: 35)
            }
        }
    }
    
    private var initialsView: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 100, height: 100)
            .overlay(
                Text(user.initials)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            )
    }
    
    private var userInfo: some View {
        VStack(spacing: 4) {
            Text(user.userName ?? "Unknown User")
                .font(.title2)
                .fontWeight(.bold)
            
            if let username = user.username {
                Text("@\(username)")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            
            // Fitness info tags
            HStack(spacing: 8) {
                if let goal = user.fitnessGoal, !goal.isEmpty {
                    InfoTag(text: goal, color: .orange)
                }
                if let level = user.experienceLevel, !level.isEmpty {
                    InfoTag(text: level, color: .purple)
                }
            }
            .padding(.top, 8)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if user.isAlreadyFriend {
                Label("Already Friends", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)
                    .padding(.vertical, 16)
            } else if user.hasPendingRequest {
                if user.requestDirection == "sent" {
                    Label("Request Pending", systemImage: "clock.fill")
                        .font(.headline)
                        .foregroundColor(.orange)
                        .padding(.vertical, 16)
                } else {
                    // They sent us a request - tapping will accept
                    Button(action: {
                        HapticManager.impact(.medium)
                        onAddFriend()
                    }) {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Accept Friend Request")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .clipShape(Capsule())
                    }
                    .disabled(isProcessing)
                }
            } else {
                Button(action: {
                    HapticManager.impact(.medium)
                    onAddFriend()
                }) {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.badge.plus")
                            Text("Add Friend")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .disabled(isProcessing)
            }
        }
    }
    
    private func resultView(_ result: QRCodeService.AddFriendResult) -> some View {
        VStack(spacing: 16) {
            // Status icon
            Image(systemName: statusIcon(for: result.status))
                .font(.system(size: 48))
                .foregroundColor(statusColor(for: result.status))
            
            // Message
            Text(result.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
    }
    
    private func statusIcon(for status: String) -> String {
        switch status {
        case "request_sent": return "paperplane.circle.fill"
        case "already_friends": return "person.2.fill"
        case "already_pending": return "clock.fill"
        case "request_accepted": return "checkmark.circle.fill"
        default: return "exclamationmark.circle.fill"
        }
    }
    
    private func statusColor(for status: String) -> Color {
        switch status {
        case "request_sent", "request_accepted": return .green
        case "already_friends": return .blue
        case "already_pending": return .orange
        default: return .red
        }
    }
}

// MARK: - Info Tag

private struct InfoTag: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
}

// MARK: - Camera View (UIKit Bridge)

struct QRCodeCameraView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Binding var torchOn: Bool
    var onError: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRCodeCameraViewController {
        let controller = QRCodeCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRCodeCameraViewController, context: Context) {
        uiViewController.setTorch(on: torchOn)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QRCodeCameraDelegate {
        var parent: QRCodeCameraView
        
        init(_ parent: QRCodeCameraView) {
            self.parent = parent
        }
        
        func didScanCode(_ code: String) {
            DispatchQueue.main.async {
                self.parent.scannedCode = code
            }
        }
        
        func didFailWithError(_ error: String) {
            DispatchQueue.main.async {
                self.parent.onError(error)
            }
        }
    }
}

// MARK: - Camera View Controller

protocol QRCodeCameraDelegate: AnyObject {
    func didScanCode(_ code: String)
    func didFailWithError(_ error: String)
}

class QRCodeCameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRCodeCameraDelegate?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastScannedCode: String?
    private var lastScanTime: Date?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }
    
    private func setupCamera() {
        // Check permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCaptureSession()
                    }
                } else {
                    self?.delegate?.didFailWithError("Camera access was denied. Please enable it in Settings to scan QR codes.")
                }
            }
        case .denied, .restricted:
            delegate?.didFailWithError("Camera access is required to scan QR codes. Please enable it in Settings.")
        @unknown default:
            delegate?.didFailWithError("Unknown camera authorization status.")
        }
    }
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.didFailWithError("No camera available on this device.")
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                delegate?.didFailWithError("Could not add camera input.")
                return
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                delegate?.didFailWithError("Could not add metadata output.")
                return
            }
        } catch {
            delegate?.didFailWithError("Camera setup failed: \(error.localizedDescription)")
            return
        }
        
        captureSession = session
        
        // Setup preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview
        
        startSession()
    }
    
    private func startSession() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    private func stopSession() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }
    
    func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be configured: \(error)")
        }
    }
    
    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              metadataObject.type == .qr,
              let stringValue = metadataObject.stringValue else {
            return
        }
        
        // Debounce - don't scan same code within 2 seconds
        let now = Date()
        if stringValue == lastScannedCode,
           let lastTime = lastScanTime,
           now.timeIntervalSince(lastTime) < 2 {
            return
        }
        
        lastScannedCode = stringValue
        lastScanTime = now
        
        delegate?.didScanCode(stringValue)
    }
}

#Preview {
    QRCodeScannerView()
}
