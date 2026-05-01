import SwiftUI
import AVFoundation

// ============================================================================
// BarcodeScannerView — Open Food Facts product scanner
// ============================================================================
// Camera-driven barcode scanner that resolves EAN/UPC codes against the OFF
// database via the `usda-food-search` edge function (`action: "barcode"`).
//
// On scan:
//   1. AVCaptureSession yields the metadata string.
//   2. We debounce duplicate scans (2s, mirrors QRCodeScannerView).
//   3. Call `FoodDatabaseService.shared.searchByBarcode(code)`.
//      - Success → invoke `onScan(food)` so the caller can present
//        `FoodDetailsView` via the existing `selectedFood` path. Avoids any
//        navigation nesting + reuses the entire serving-size + meal-add flow.
//      - Miss → show an inline "Not in database" panel with a single "Search
//        by name" CTA that surfaces the code through `onSearchFallback`.
//
// Architecture parity with `QRCodeScannerView.swift`:
//   - Same UIViewControllerRepresentable bridge (separate VC subclass to keep
//     each scanner's debounce + metadata-types isolated).
//   - Same torch button + dismiss button + camera-error overlay.
//   - Same NSCameraUsageDescription string in Info.plist already mentions
//     "scan food barcodes" — no plist change required (verified 2026-04-30).
//
// Why a separate camera VC (`BarcodeCameraViewController`) instead of reusing
// QRCode's: the metadata-types list is the only difference, but reusing would
// require either (a) parameterizing the existing VC and risking QR-scanner
// regressions, or (b) toggling types per-instance. A small dedicated VC is
// cheaper and keeps each scanner's failure modes investigable in isolation.
// ============================================================================

struct BarcodeScannerView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    /// Successful barcode → product resolution. Caller is expected to route to
    /// FoodDetailsView via its own NavigationLink / selectedFood state.
    let onScan: (ProcessedFoodItem) -> Void
    /// Barcode found but no OFF entry — caller should prefill the search bar
    /// with the raw digits so the user can type-search instead.
    let onSearchFallback: (String) -> Void

    @State private var scannedCode: String?
    @State private var isLookingUp = false
    @State private var lookupError: String?
    @State private var notFoundCode: String?
    @State private var cameraError: String?
    @State private var torchOn = false
    @State private var manualEntryShown = false
    @State private var manualEntryText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                BarcodeCameraView(
                    scannedCode: $scannedCode,
                    torchOn: $torchOn,
                    onError: { error in cameraError = error }
                )
                .ignoresSafeArea()

                VStack {
                    topControls
                    Spacer()
                    scanningFrame
                    Spacer()
                    instructionsOrStatusCard
                }

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
            .sheet(isPresented: $manualEntryShown) {
                manualEntrySheet
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Top Controls

    private var topControls: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.ds_labelLarge)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.5)))
            }

            Spacer()

            Text("Scan Barcode")
                .font(.headline)
                .foregroundColor(.white)
                .shadow(radius: 2)

            Spacer()

            Button(action: {
                HapticManager.impact(.light)
                torchOn.toggle()
            }) {
                Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.ds_labelLarge)
                    .foregroundColor(torchOn ? .yellow : .white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: - Scanning Frame

    // Wider than tall — barcodes are horizontal. Matches the natural aspect of
    // a product label held landscape.
    private var scanningFrame: some View {
        let w: CGFloat = 300
        let h: CGFloat = 180
        return ZStack {
            Rectangle()
                .fill(.black.opacity(0.5))
                .mask(
                    ZStack {
                        Rectangle()
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .frame(width: w, height: h)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )

            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: w, height: h)

            if scannedCode == nil {
                BarcodeScanLineView()
                    .frame(width: w - 20, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            }
        }
    }

    // MARK: - Status / Instructions Card

    @ViewBuilder
    private var instructionsOrStatusCard: some View {
        VStack(spacing: 10) {
            if isLookingUp {
                lookingUpCard
            } else if let code = notFoundCode {
                notFoundCard(code)
            } else if let error = lookupError {
                errorCard(error)
            } else {
                idleCard
            }

            // Manual entry — for cases where the barcode is damaged or won't
            // read (curved bottle, glare, etc.). Power-user fallback that
            // keeps the scanner useful in real-world conditions.
            Button(action: {
                HapticManager.impact(.light)
                manualEntryShown = true
            }) {
                Label("Enter barcode manually", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(.black.opacity(0.5)))
            }
        }
        .padding(.bottom, 40)
    }

    private var idleCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder")
                    .font(.ds_heading3)
                Text("Point at a product barcode")
                    .font(.subheadline)
            }
            .foregroundColor(.white)

            Text("EAN / UPC supported · Powered by Open Food Facts")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .background(Capsule().fill(.black.opacity(0.6)))
    }

    private var lookingUpCard: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("Looking up product…")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .background(Capsule().fill(.black.opacity(0.7)))
    }

    private func notFoundCard(_ code: String) -> some View {
        VStack(spacing: 8) {
            Label("Not in database", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundColor(.orange)
            Text("Code: \(code)")
                .font(.caption.monospaced())
                .foregroundColor(.white.opacity(0.7))
            Button(action: {
                HapticManager.impact(.light)
                onSearchFallback(code)
                dismiss()
            }) {
                Label("Search by name", systemImage: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(.green))
            }
            Button("Scan another") {
                HapticManager.impact(.light)
                resetScanner()
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(.black.opacity(0.75))
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 6) {
            Label("Lookup failed", systemImage: "wifi.exclamationmark")
                .font(.subheadline)
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Try again") { resetScanner() }
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(.black.opacity(0.75))
        )
    }

    private var manualEntrySheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Barcode (8-14 digits)", text: $manualEntryText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Button(action: {
                    let digits = manualEntryText.filter { $0.isNumber }
                    guard [8, 12, 13, 14].contains(digits.count) else {
                        HapticManager.notification(.error)
                        return
                    }
                    manualEntryShown = false
                    handleScannedCode(digits)
                }) {
                    Text("Look up")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Capsule().fill(.green))
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Manual Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { manualEntryShown = false }
                }
            }
        }
    }

    private func cameraErrorView(_ error: String) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)

                Text("Camera Access Required")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.green)

                Button("Cancel") { dismiss() }
                    .foregroundColor(.gray)
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func handleScannedCode(_ code: String) {
        guard !isLookingUp else { return }
        let digits = code.filter { $0.isNumber }
        guard [8, 12, 13, 14].contains(digits.count) else {
            // Not a product barcode — silently ignore, keep scanning.
            // (User might be pointing at a QR sticker on the same package.)
            return
        }

        HapticManager.notification(.success)
        isLookingUp = true
        lookupError = nil
        notFoundCode = nil

        Task {
            do {
                if let cloudFood = try await FoodDatabaseService.shared.searchByBarcode(digits) {
                    let processed = cloudFood.toProcessedFoodItem()
                    await MainActor.run {
                        isLookingUp = false
                        onScan(processed)
                        dismiss()
                    }
                } else {
                    await MainActor.run {
                        HapticManager.notification(.warning)
                        isLookingUp = false
                        notFoundCode = digits
                    }
                }
            } catch {
                await MainActor.run {
                    HapticManager.notification(.error)
                    isLookingUp = false
                    lookupError = error.localizedDescription
                }
            }
        }
    }

    private func resetScanner() {
        scannedCode = nil
        notFoundCode = nil
        lookupError = nil
        isLookingUp = false
    }
}

// MARK: - Scan Line Animation

private struct BarcodeScanLineView: View {
    @State private var offset: CGFloat = -80

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .green.opacity(0.6), .mint.opacity(0.9), .green.opacity(0.6), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    offset = 80
                }
            }
    }
}

// MARK: - Camera View (UIKit Bridge)

struct BarcodeCameraView: UIViewControllerRepresentable {
    @Binding var scannedCode: String?
    @Binding var torchOn: Bool
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCameraViewController {
        let controller = BarcodeCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeCameraViewController, context: Context) {
        uiViewController.setTorch(on: torchOn)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, BarcodeCameraDelegate {
        var parent: BarcodeCameraView
        init(_ parent: BarcodeCameraView) { self.parent = parent }

        func didScanCode(_ code: String) {
            DispatchQueue.main.async { self.parent.scannedCode = code }
        }
        func didFailWithError(_ error: String) {
            DispatchQueue.main.async { self.parent.onError(error) }
        }
    }
}

// MARK: - Camera View Controller

protocol BarcodeCameraDelegate: AnyObject {
    func didScanCode(_ code: String)
    func didFailWithError(_ error: String)
}

class BarcodeCameraViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: BarcodeCameraDelegate?

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
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupCaptureSession() }
                } else {
                    self?.delegate?.didFailWithError("Camera access was denied. Please enable it in Settings to scan barcodes.")
                }
            }
        case .denied, .restricted:
            delegate?.didFailWithError("Camera access is required to scan barcodes. Please enable it in Settings.")
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
                // Standard product barcode types. EAN-13 covers most of the
                // world; UPC-A is US/Canada; EAN-8 is small packages; ITF-14
                // is shipping cartons; Code-128 / Code-39 / I2of5 catch
                // miscellaneous private-label / pharmacy formats.
                metadataOutput.metadataObjectTypes = [
                    .ean13,
                    .ean8,
                    .upce,
                    .code128,
                    .code39,
                    .interleaved2of5,
                    .itf14,
                ]
            } else {
                delegate?.didFailWithError("Could not add metadata output.")
                return
            }
        } catch {
            delegate?.didFailWithError("Camera setup failed: \(error.localizedDescription)")
            return
        }

        captureSession = session

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
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            AppLogger.debug("Torch could not be configured: \(error)", category: .nutrition)
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else { return }

        // Debounce: don't re-scan the same code within 2 seconds. Same window
        // QRCodeScannerView uses, also coalesces the duplicate frames
        // AVFoundation emits during a continuous gaze.
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
    BarcodeScannerView(
        onScan: { _ in },
        onSearchFallback: { _ in }
    )
}
