import SwiftUI
import MapKit
import CoreLocation
import UIKit

// MARK: - CardioShareCardSheet
//
// Cardio Redesign Phase 1 — Wave 5b. The viral lever.
// 1080×1920 (Instagram Story ratio) share card export:
//   ┌──────────────────────────┐
//   │   FIT33 logo  •  Activity │  header
//   │                           │
//   │     [route silhouette]    │  ~42% — RoutePreviewMap snapshot
//   │                           │
//   │   D I S T A N C E         │  the hero number
//   │   6.21 mi                 │
//   │                           │
//   │  Pace · Time · Calories   │  3-up stat row
//   │                           │
//   │   Powered by Strava       │  conditional co-brand footer
//   └──────────────────────────┘
//
// Renders the SwiftUI view via `ImageRenderer` → `UIImage`, then hands
// it to a `ShareLink(item:preview:)` so the system share sheet shows
// a real preview thumb on iOS 16+. Also offers a one-tap save to
// Photos for users who'd rather post manually.
//
// File length budget: ≤ 300 lines per `codingrules.mdc`.
struct CardioShareCardSheet: View {
    let result: RunWorkoutResult
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var isRendering = true
    @State private var didSaveToPhotos = false
    @State private var photoSaveFailed = false

    private let exportSize = CGSize(width: 1080, height: 1920)
    private let stravaConnected = StravaService.shared.isConnected

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Share your workout")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.top, 8)

                    // Live preview — same view tree as the export, scaled down.
                    cardView
                        .frame(width: 270, height: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)

                    actionButtons
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { renderShareImage() }
        }
    }

    // MARK: - Card view (renders to image AND on-screen preview)

    @ViewBuilder
    private var cardView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    accent.opacity(0.95),
                    accent.opacity(0.55),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 18) {
                cardHeader
                cardRouteSection
                cardHeadline
                cardStatRow
                Spacer(minLength: 0)
                cardFooter
            }
            .padding(28)
        }
        .foregroundColor(.white)
    }

    private var cardHeader: some View {
        HStack {
            Text("FIT33")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .kerning(2)
            Spacer()
            Label(result.activityType.displayName, systemImage: activityIcon)
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.25)))
        }
    }

    @ViewBuilder
    private var cardRouteSection: some View {
        if result.routeCoordinates.count > 1 {
            RouteSilhouette(coordinates: result.routeCoordinates)
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .padding(8)
                .frame(height: 200)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.12))
                )
        } else {
            // Indoor / no-route fallback — show big activity icon.
            Image(systemName: activityIcon)
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.12))
                )
        }
    }

    private var cardHeadline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(distanceLabel)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(distanceUnit)
                .font(.system(size: 14, weight: .bold))
                .kerning(2)
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private var cardStatRow: some View {
        HStack(spacing: 0) {
            statColumn(value: result.formattedDuration, label: "TIME")
            divider
            statColumn(value: paceLabel, label: "PACE")
            divider
            statColumn(value: String(format: "%.0f", result.calories), label: "CAL")
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .kerning(1.4)
                .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.25))
            .frame(width: 1, height: 28)
    }

    @ViewBuilder
    private var cardFooter: some View {
        HStack {
            Text(dateLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            if stravaConnected {
                HStack(spacing: 4) {
                    Text("Powered by")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("STRAVA")
                        .font(.system(size: 11, weight: .black))
                        .kerning(1)
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if let img = renderedImage {
                ShareLink(
                    item: Image(uiImage: img),
                    preview: SharePreview("Fit33 Workout", image: Image(uiImage: img))
                ) {
                    Label("Share to…", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.20)))
                        .foregroundColor(.primary)
                }
                Button(action: saveToPhotos) {
                    Label(photoSaveButtonTitle,
                          systemImage: didSaveToPhotos ? "checkmark.circle.fill" : (photoSaveFailed ? "exclamationmark.triangle.fill" : "square.and.arrow.down"))
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                        .foregroundColor(didSaveToPhotos ? .green : (photoSaveFailed ? .red : .primary))
                }
                .disabled(didSaveToPhotos)
            } else if isRendering {
                ProgressView("Rendering…")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
    }

    private var photoSaveButtonTitle: String {
        if didSaveToPhotos { return "Saved to Photos" }
        if photoSaveFailed { return "Save failed — check Photos access" }
        return "Save to Photos"
    }

    // MARK: - Render

    @MainActor
    private func renderShareImage() {
        let view = cardView
            .frame(width: exportSize.width, height: exportSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0 // we already render at 1080×1920 native px
        if let img = renderer.uiImage {
            renderedImage = img
        }
        isRendering = false
    }

    private func saveToPhotos() {
        guard let img = renderedImage else { return }
        // Success is claimed via the completion selector — the old
        // fire-and-forget call showed "Saved to Photos" even when the write
        // failed (e.g. Photos permission denied). P2 quickie, 2026-07-31.
        let target = PhotoSaveCompletionTarget { error in
            Task { @MainActor in
                if error == nil {
                    didSaveToPhotos = true
                    photoSaveFailed = false
                    HapticManager.notification(.success)
                } else {
                    photoSaveFailed = true
                    HapticManager.notification(.error)
                }
            }
        }
        UIImageWriteToSavedPhotosAlbum(
            img,
            target,
            #selector(PhotoSaveCompletionTarget.image(_:didFinishSavingWithError:contextInfo:)),
            nil
        )
    }

    // MARK: - Helpers

    private var activityIcon: String {
        switch result.activityType {
        case .walk:         return "figure.walk"
        case .run:          return "figure.run"
        case .outdoorCycle: return "figure.outdoor.cycle"
        case .hike:         return "figure.hiking"
        }
    }

    private var distanceLabel: String {
        result.distanceMiles >= 0.01
            ? String(format: "%.2f", result.distanceMiles)
            : String(format: "%.0f", result.distance)
    }

    private var distanceUnit: String {
        result.distanceMiles >= 0.01 ? "MILES" : "METERS"
    }

    private var paceLabel: String {
        guard result.averagePace > 0 else { return "—" }
        let p = result.averagePace * 1.60934
        return String(format: "%d:%02d", Int(p) / 60, Int(p) % 60)
    }

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: result.startTime)
    }
}

// MARK: - RouteSilhouette
//
// Lightweight `Shape` that scales the route polyline to fit its frame.
// Used by the share card so the route renders as a clean white silhouette
// over the activity-colored gradient (vs the live MapKit map which is
// great in-product but visually noisy on a social card).
private struct RouteSilhouette: Shape {
    let coordinates: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard coordinates.count > 1 else { return p }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return p }
        let dLat = max(maxLat - minLat, 0.000001)
        let dLon = max(maxLon - minLon, 0.000001)
        // Aspect-correct the lon range so we don't squish near the poles.
        let aspect = cos(((minLat + maxLat) / 2) * .pi / 180)
        let dLonScaled = dLon * aspect
        let scale = min(rect.width / CGFloat(dLonScaled), rect.height / CGFloat(dLat)) * 0.92
        let offsetX = (rect.width - CGFloat(dLonScaled) * scale) / 2
        let offsetY = (rect.height - CGFloat(dLat) * scale) / 2

        for (i, c) in coordinates.enumerated() {
            let x = offsetX + CGFloat((c.longitude - minLon) * aspect) * scale
            // Y is inverted because coords are bottom-up but UI is top-down.
            let y = rect.height - (offsetY + CGFloat(c.latitude - minLat) * scale)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else      { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

/// `UIImageWriteToSavedPhotosAlbum` needs an Obj-C target/selector for its
/// completion; SwiftUI structs can't be one, so this tiny NSObject bridges
/// the callback to a closure. It retains itself until the callback fires
/// (the API does not retain the target).
private final class PhotoSaveCompletionTarget: NSObject {
    private let onComplete: (Error?) -> Void
    private var selfRetain: PhotoSaveCompletionTarget?

    init(onComplete: @escaping (Error?) -> Void) {
        self.onComplete = onComplete
        super.init()
        self.selfRetain = self
    }

    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        onComplete(error)
        selfRetain = nil
    }
}
