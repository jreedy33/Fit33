import SwiftUI
import Vision
import UIKit

/// Shared exercise card row component used by both ExerciseLibraryView and CustomWorkoutBuilderView.
/// Renders a consistent 56x56 hollow gradient ring with a cached video still centered inside (falls
/// back to an SF Symbol on a filled gradient when no poster is cached), plus exercise
/// name/category/equipment, and optional checkbox, chevron, info button, or favorite star based on
/// the display context.
struct ExerciseCardRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let exercise: Exercise
    var showCheckbox: Bool = false
    var isSelected: Bool = false
    var showChevron: Bool = false
    var showInfoButton: Bool = false
    var onInfo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if showCheckbox {
                checkboxView
            }

            exerciseIcon
            exerciseDetails

            Spacer()

            if exercise.isFavorite {
                Image(systemName: "star.fill")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.yellow)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            if showInfoButton, let onInfo {
                Button(action: {
                    HapticManager.selectionChanged()
                    onInfo()
                }) {
                    Image(systemName: "info.circle")
                        .font(.ds_bodyRegular).fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.leading, Spacing.xxs)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
    }

    // MARK: - Checkbox

    private var checkboxView: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 28, height: 28)

            if isSelected {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.ds_bodySmall).fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }

    // MARK: - Exercise Icon (56x56 hollow gradient ring with centered video still)

    private var exerciseIcon: some View {
        ExercisePosterRingIcon(
            exerciseName: exercise.displayName,
            gradientColors: categoryGradient,
            fallbackSymbol: resolvedIcon,
            isCoreCategory: exercise.category?.lowercased() == "core",
            size: 56,
            ringWidth: 2.5
        )
    }

    // MARK: - Exercise Details

    private var exerciseDetails: some View {
        let split = ExerciseNicknameService.splitPresentation(exercise.displayName)
        return VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(split.main)
                .font(.ds_bodyLarge)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let variant = split.variant {
                Text(variant)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: Spacing.xs) {
                if let category = exercise.category {
                    Text(category)
                        .font(.ds_bodySmall)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)
                }

                if let equipment = exercise.equipment {
                    Text("•")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)

                    Text(equipment)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    // MARK: - Category Styling

    var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .purple
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "full body": return .pink
        default: return .gray
        }
    }

    var categoryGradient: [Color] {
        switch exercise.category?.lowercased() {
        case "chest": return [Color.purple, Color.pink]
        case "back": return [Color.blue, Color.cyan]
        case "legs": return [Color.green, Color.teal]
        case "shoulders": return [Color.orange, Color.yellow]
        case "arms": return [Color.purple, Color.indigo]
        case "core": return [Color.yellow, Color.orange]
        case "full body": return [Color.pink, Color.red]
        default: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }

    // MARK: - Smart Icon Resolution
    // Prioritizes exercise-name-specific icons, then equipment, then category fallback.

    var resolvedIcon: String {
        if let instructions = exercise.instructions,
           instructions.contains("[CUSTOM_EXERCISE|ICON:"),
           let iconRange = instructions.range(of: #"\[CUSTOM_EXERCISE\|ICON:([^\]]+)\]"#, options: .regularExpression),
           let iconName = instructions[iconRange].split(separator: ":").last?.replacingOccurrences(of: "]", with: "") {
            return String(iconName)
        }

        if let name = exercise.name?.lowercased() {
            if name.contains("dumbbell") { return "dumbbell.fill" }
            if name.contains("barbell") { return "figure.strengthtraining.traditional" }
            if name.contains("cable") { return "dot.radiowaves.left.and.right" }
            if name.contains("push") && name.contains("up") { return "figure.strengthtraining.traditional" }
            if name.contains("pull") && (name.contains("up") || name.contains("chin")) { return "figure.climbing" }
            if name.contains("squat") { return "figure.strengthtraining.traditional" }
            if name.contains("lunge") { return "figure.walk" }
            if name.contains("thrust") || name.contains("bridge") { return "figure.strengthtraining.functional" }
            if name.contains("deadlift") { return "figure.strengthtraining.functional" }
            if name.contains("curl") { return "figure.arms.open" }
            if name.contains("press") && !name.contains("leg") { return "arrow.up.circle.fill" }
            if name.contains("row") { return "arrow.left.and.right.circle.fill" }
            if name.contains("fly") || name.contains("flye") { return "arrow.up.left.and.arrow.down.right.circle.fill" }
            if name.contains("raise") { return "arrow.up.circle" }
            if name.contains("shrug") { return "arrow.up.and.down.circle.fill" }
            if name.contains("plank") { return "figure.core.training" }
            if name.contains("run") || name.contains("jog") { return "figure.run" }
            if name.contains("jump") { return "figure.jumprope" }
        }

        if let equipment = exercise.equipment?.lowercased() {
            switch equipment {
            case "dumbbells": return "dumbbell.fill"
            case "barbell": return "figure.strengthtraining.traditional"
            case "cables": return "dot.radiowaves.left.and.right"
            case "machines": return "gearshape.fill"
            case "bodyweight": return "figure.strengthtraining.traditional"
            default: break
            }
        }

        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.climbing"
        case "legs": return "figure.strengthtraining.traditional"
        case "shoulders": return "arrow.up.circle.fill"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}

// MARK: - Exercise Poster Ring Icon
// Hollow gradient ring with a cached video still cleanly centered inside.
// Mirrors the circular video treatment used in StretchModeView — the poster frame
// is clipped to a circle with .fill aspect ratio so the subject stays centered.
// Falls back to a filled gradient + SF Symbol when no poster frame is cached yet.
//
// ⚡️ PERFORMANCE (see QUALITY_PERFORMANCE_AGENT invariants #11, #12, #17):
//   • Synchronous disk+memory cache hit on appear — no `Task`, no polling, no Vision.
//   • Cache miss triggers a SERIAL, utility-QoS, network-gated bake in the background.
//   • The cell is notified via NotificationCenter when its bake completes, so we never
//     keep 10+ main-actor polling Tasks alive per visible scroll viewport.
//   • Every smart-cropped result is persisted to disk (<15KB JPEG), so subsequent
//     launches skip Vision entirely and render in <5ms.
struct ExercisePosterRingIcon: View {
    let exerciseName: String
    let gradientColors: [Color]
    let fallbackSymbol: String
    var isCoreCategory: Bool = false
    var size: CGFloat = 56
    var ringWidth: CGFloat = 2.5

    @State private var displayImage: UIImage?

    private var ringGradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size - ringWidth * 2, height: size - ringWidth * 2)
                    .clipShape(Circle())
                    .transition(.opacity)
            } else {
                Circle()
                    .fill(ringGradient)
                    .frame(width: size - ringWidth * 2, height: size - ringWidth * 2)

                if isCoreCategory {
                    CoreIcon(size: size * 0.5, color: .white)
                } else {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            Circle()
                .strokeBorder(ringGradient, lineWidth: ringWidth)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.2), value: displayImage != nil)
        .onAppear { loadPoster() }
        .onReceive(NotificationCenter.default.publisher(for: .exercisePosterSmartCropReady)) { note in
            guard let name = note.userInfo?["name"] as? String,
                  name == exerciseName,
                  displayImage == nil else { return }
            displayImage = ExercisePosterSmartCrop.shared.cachedCrop(for: exerciseName)
        }
    }

    private func loadPoster() {
        // Fast path #1: smart-cropped image already on disk/memory (<5ms).
        if let cropped = ExercisePosterSmartCrop.shared.cachedCrop(for: exerciseName) {
            displayImage = cropped
            return
        }

        // Fast path #2: raw 16:9 poster is cached — show it immediately (center-cropped),
        // and bake the smart-cropped version in the background for next appearance.
        if let cached = VideoThumbnailService.shared.getPosterFrame(for: exerciseName) {
            displayImage = cached
            ExercisePosterSmartCrop.shared.requestBake(name: exerciseName, source: cached)
            return
        }

        // Cold path: no poster cached. Show fallback immediately; request a background
        // bake (which will also generate the raw poster, gated by NetworkMonitor).
        // No main-actor polling — we rely on the notification subscription above.
        ExercisePosterSmartCrop.shared.requestGenerationAndBake(name: exerciseName)
    }
}

// MARK: - Smart Crop Ready Notification

extension Notification.Name {
    /// Posted by `ExercisePosterSmartCrop` when a bake completes. `userInfo["name"]` is
    /// the exercise displayName. Cells filter by this name to update themselves instead
    /// of polling.
    static let exercisePosterSmartCropReady = Notification.Name("ExercisePosterSmartCropReady")
}

// MARK: - Exercise Poster Smart Crop Service
//
// Detects the subject in a 16:9 poster frame and persists a square smart-cropped JPEG
// (~8-15 KB) to disk. On subsequent launches / scrolls the cell reads the pre-computed
// crop synchronously — no Vision, no AVFoundation, no network.
//
// PATTERN: mirrors `VideoThumbnailService` (disk + memory NSCache, utility QoS,
// in-flight dedup, network-gated speculative work). Performance invariants:
//   • Vision runs on a SERIAL utility-QoS queue so it can't saturate CPU during scroll.
//   • Speculative video download (for cold-path generation) consults NetworkMonitor.
//   • Completion side effect is a single NotificationCenter post; no retained callbacks.
final class ExercisePosterSmartCrop {
    static let shared = ExercisePosterSmartCrop()

    // MARK: Caches

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheDir: URL?
    private let fileManager = FileManager.default

    // MARK: Queues

    // Serial, utility-QoS queue — one Vision op at a time so we don't compete with
    // the UI thread during scroll (invariant #17).
    private let visionQueue = DispatchQueue(label: "exercise.smartcrop.vision", qos: .utility)

    // Separate utility queue for cold-path poster generation (video download + first-frame
    // extraction), also serial so we never flood the network from a scroll event.
    private let generationQueue = DispatchQueue(label: "exercise.smartcrop.generation", qos: .utility)

    private var inFlightBakes: Set<String> = []
    private var inFlightGenerations: Set<String> = []
    private let lock = NSLock()

    /// Padding around the detected subject before cropping to square. 1.35 = ~35%
    /// breathing room — empirically balanced for demo animations where the figure can
    /// shift pose within a few frames.
    private let paddingFactor: CGFloat = 1.35

    /// Square output size in pixels. 160 is large enough to look crisp at 2x/3x on a
    /// 56pt ring (~170px on 3x displays) without wasting disk.
    private let outputSize: CGFloat = 160

    private init() {
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 12 * 1024 * 1024 // ~12MB of small square JPEGs

        diskCacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("exercise_smart_crops")

        if let dir = diskCacheDir {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Public API

    /// Synchronous cache lookup — returns nil if not yet cached. Called on every cell
    /// appearance; must be cheap (<5ms).
    func cachedCrop(for name: String) -> UIImage? {
        let key = cacheKey(for: name)
        if let hit = memoryCache.object(forKey: key as NSString) {
            return hit
        }
        if let image = loadFromDisk(key: key) {
            memoryCache.setObject(image, forKey: key as NSString, cost: estimatedCost(image))
            return image
        }
        return nil
    }

    /// Request a bake from a raw poster we already have in hand. Non-blocking.
    /// Posts `.exercisePosterSmartCropReady` when done.
    func requestBake(name: String, source: UIImage) {
        guard !hasDiskCrop(for: name) else { return }

        lock.lock()
        guard !inFlightBakes.contains(name) else {
            lock.unlock()
            return
        }
        inFlightBakes.insert(name)
        lock.unlock()

        visionQueue.async { [weak self] in
            guard let self else { return }
            let result = self.performSmartCrop(source: source)
            self.markBakeComplete(name: name, image: result)
        }
    }

    /// Cold path: no raw poster cached either. Downloads / extracts the raw poster
    /// (gated by NetworkMonitor so we never pull video bytes on cellular/constrained
    /// networks — invariant #11), then bakes the smart crop. Non-blocking.
    func requestGenerationAndBake(name: String) {
        guard !hasDiskCrop(for: name) else { return }

        // NETWORK GATE: speculative prefetch must never run on expensive connections.
        if NetworkMonitor.shared.shouldAvoidBackgroundTraffic {
            return
        }

        lock.lock()
        guard !inFlightGenerations.contains(name) else {
            lock.unlock()
            return
        }
        inFlightGenerations.insert(name)
        lock.unlock()

        generationQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.inFlightGenerations.remove(name)
                self.lock.unlock()
            }

            // If the raw poster appeared on disk while we were waiting in the queue, use it.
            if let existing = VideoThumbnailService.shared.getPosterFrame(for: name) {
                self.requestBake(name: name, source: existing)
                return
            }

            // Ask VideoThumbnailService to generate the raw poster (it has its own
            // in-flight dedup + disk persistence). Then poll off-main with a bounded
            // timeout — much cheaper than polling on MainActor per-cell.
            guard let url = VideoStreamingService.shared.getVideoURL(for: name) else { return }
            VideoThumbnailService.shared.generatePosterFrame(exerciseName: name, videoURL: url)

            for _ in 0..<8 {
                Thread.sleep(forTimeInterval: 0.4)
                if let raw = VideoThumbnailService.shared.getPosterFrame(for: name) {
                    self.requestBake(name: name, source: raw)
                    return
                }
            }
        }
    }

    // MARK: - Bake Pipeline

    private func markBakeComplete(name: String, image: UIImage?) {
        let key = cacheKey(for: name)
        if let image {
            memoryCache.setObject(image, forKey: key as NSString, cost: estimatedCost(image))
            saveToDisk(image, key: key)

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .exercisePosterSmartCropReady,
                    object: nil,
                    userInfo: ["name": name]
                )
            }
        }
        lock.lock()
        inFlightBakes.remove(name)
        lock.unlock()
    }

    // MARK: - Vision Detection

    private func performSmartCrop(source: UIImage) -> UIImage? {
        guard let cgImage = source.cgImage else { return nil }
        let imageW = CGFloat(cgImage.width)
        let imageH = CGFloat(cgImage.height)

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        // 1) Prefer human-body detection — most exercise videos feature a full figure.
        var subjectBox: CGRect? = detectHumanBox(handler: handler)
        // 2) Fall back to saliency if no human was confidently detected.
        if subjectBox == nil {
            subjectBox = detectSaliencyBox(handler: handler)
        }

        let pixelBox: CGRect
        if let box = subjectBox {
            // Vision returns normalized rects with origin bottom-left — flip to image coords.
            pixelBox = CGRect(
                x: box.origin.x * imageW,
                y: (1 - box.origin.y - box.size.height) * imageH,
                width: box.size.width * imageW,
                height: box.size.height * imageH
            )
        } else {
            let side = min(imageW, imageH)
            pixelBox = CGRect(
                x: (imageW - side) / 2,
                y: (imageH - side) / 2,
                width: side,
                height: side
            )
        }

        let cropRect = squareCrop(around: pixelBox, imageW: imageW, imageH: imageH)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        // Downscale to outputSize so disk + memory footprint is ~8-15KB per image.
        return downscale(cgImage: cropped, to: outputSize)
    }

    private func detectHumanBox(handler: VNImageRequestHandler) -> CGRect? {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let best = (request.results ?? []).max(by: { $0.confidence < $1.confidence }),
              best.confidence > 0.3 else {
            return nil
        }
        return best.boundingBox
    }

    private func detectSaliencyBox(handler: VNImageRequestHandler) -> CGRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first as? VNSaliencyImageObservation,
              let salient = result.salientObjects?.first else {
            return nil
        }
        return salient.boundingBox
    }

    // MARK: - Geometry + Downscale

    private func squareCrop(around box: CGRect, imageW: CGFloat, imageH: CGFloat) -> CGRect {
        let rawSide = max(box.width, box.height) * paddingFactor
        let side = min(rawSide, imageW, imageH)

        var x = box.midX - side / 2
        var y = box.midY - side / 2
        x = max(0, min(imageW - side, x))
        y = max(0, min(imageH - side, y))

        return CGRect(x: x, y: y, width: side, height: side).integral
    }

    private func downscale(cgImage: CGImage, to side: CGFloat) -> UIImage? {
        let target = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: target, format: {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.opaque = true
            fmt.scale = 1 // we persist JPEG; keep pixel size explicit
            return fmt
        }())
        return renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Disk

    private func cacheKey(for name: String) -> String {
        // Include gender preference so the crop flips when the user changes video gender,
        // matching VideoThumbnailService's key scheme.
        let gender = GenderFilterService.shared.preferredGender.rawValue.lowercased()
        let base = name.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "\(base)_\(gender)"
    }

    private func hasDiskCrop(for name: String) -> Bool {
        let key = cacheKey(for: name)
        if memoryCache.object(forKey: key as NSString) != nil { return true }
        guard let dir = diskCacheDir else { return false }
        return fileManager.fileExists(atPath: dir.appendingPathComponent("\(key).jpg").path)
    }

    private func loadFromDisk(key: String) -> UIImage? {
        guard let dir = diskCacheDir else { return nil }
        let filePath = dir.appendingPathComponent("\(key).jpg")
        guard fileManager.fileExists(atPath: filePath.path),
              let data = try? Data(contentsOf: filePath),
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func saveToDisk(_ image: UIImage, key: String) {
        guard let dir = diskCacheDir,
              let data = image.jpegData(compressionQuality: 0.75) else { return }
        let filePath = dir.appendingPathComponent("\(key).jpg")
        try? data.write(to: filePath, options: .atomic)
    }

    private func estimatedCost(_ image: UIImage) -> Int {
        let size = image.size
        return Int(size.width * size.height * image.scale * image.scale * 4)
    }
}
