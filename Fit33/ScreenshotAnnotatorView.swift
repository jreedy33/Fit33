import SwiftUI
import UIKit

// MARK: - ScreenshotAnnotatorView
//
// Full-screen sheet that lets the user draw red marker strokes on top of
// a captured screenshot to circle the bug they're reporting. Used by
// `BugReportView` (rage-shake) and `ManualBugReportView` (Settings →
// Report a Bug). The composited image — base screenshot + strokes
// flattened — is returned via `onSave` and replaces the original
// screenshot in the bug-report payload, so the admin CMS bug-intelligence
// detail panel sees exactly what the user circled.
//
// Implementation notes:
// - Uses SwiftUI's `Canvas` + a `DragGesture(minimumDistance: 0)` for
//   free-hand strokes. We deliberately avoid PencilKit so we don't add a
//   new framework just for this one entry point.
// - Stroke points are captured in the on-screen image rect's local
//   coordinate space (the `Canvas` is sized to the aspect-fit image).
//   On save we re-render at the original image's pixel size and scale
//   each stroke by `image.size.width / canvasSize.width` so the marks
//   land exactly where the user drew them, regardless of device size.
// - One stroke per drag. `Undo` pops the last stroke, `Clear` removes all.
// - Default tool: red marker, 12pt at the on-screen size.
struct ScreenshotAnnotatorView: View {
    let baseImage: UIImage
    let onSave: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var strokes: [Stroke] = []
    @State private var currentPoints: [CGPoint] = []
    @State private var canvasSize: CGSize = .zero

    private let strokeColor: Color = .red
    private let strokeWidth: CGFloat = 12

    struct Stroke: Identifiable {
        let id = UUID()
        let points: [CGPoint]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    let imageRect = aspectFitRect(image: baseImage, in: geo.size)
                    ZStack {
                        Image(uiImage: baseImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .accessibilityHidden(true)

                        Canvas { ctx, _ in
                            for stroke in strokes {
                                drawStroke(stroke.points, in: &ctx)
                            }
                            if !currentPoints.isEmpty {
                                drawStroke(currentPoints, in: &ctx)
                            }
                        }
                        .frame(width: imageRect.width, height: imageRect.height)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    currentPoints.append(value.location)
                                }
                                .onEnded { _ in
                                    if currentPoints.count > 1 {
                                        strokes.append(Stroke(points: currentPoints))
                                    }
                                    currentPoints.removeAll()
                                }
                        )
                        .accessibilityLabel("Drawing canvas")
                        .accessibilityHint("Drag to circle the bug with a red marker")
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .onAppear { canvasSize = imageRect.size }
                    .onChange(of: imageRect.size) { _, newSize in
                        canvasSize = newSize
                    }
                }
            }
            .navigationTitle("Mark the bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.85), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.selectionChanged()
                        dismiss()
                    }
                    .foregroundColor(.red)
                    .accessibilityHint("Discard markup and close")
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(strokeColor)
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                        Text("Red marker")
                            .font(.ds_caption)
                            .foregroundColor(.white)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.selectionChanged()
                        _ = strokes.popLast()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(strokes.isEmpty)
                    .accessibilityLabel("Undo last stroke")

                    Button {
                        HapticManager.selectionChanged()
                        strokes.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(strokes.isEmpty)
                    .accessibilityLabel("Clear all marks")

                    Button("Save") {
                        HapticManager.selectionChanged()
                        let composed = composeAnnotatedImage()
                        onSave(composed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityHint("Save markup and attach to report")
                }
            }
        }
    }

    private func drawStroke(_ points: [CGPoint], in ctx: inout GraphicsContext) {
        guard points.count > 1 else { return }
        var path = Path()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        ctx.stroke(
            path,
            with: .color(strokeColor),
            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
        )
    }

    /// Renders `baseImage` at its native pixel size with every stroke
    /// drawn on top, scaled from the on-screen canvas coordinate system
    /// to the image's pixel coordinate system. Falls back to the
    /// original image if `canvasSize` hasn't laid out yet (no strokes
    /// exist in that case anyway).
    private func composeAnnotatedImage() -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return baseImage }
        let imageSize = baseImage.size
        let scaleX = imageSize.width / canvasSize.width
        let scaleY = imageSize.height / canvasSize.height
        let pixelStrokeWidth = strokeWidth * scaleX

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = baseImage.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        return renderer.image { rendererCtx in
            baseImage.draw(in: CGRect(origin: .zero, size: imageSize))

            let cg = rendererCtx.cgContext
            cg.setStrokeColor(UIColor.systemRed.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setLineWidth(pixelStrokeWidth)

            for stroke in strokes {
                guard stroke.points.count > 1 else { continue }
                let scaledPoints = stroke.points.map {
                    CGPoint(x: $0.x * scaleX, y: $0.y * scaleY)
                }
                cg.beginPath()
                cg.move(to: scaledPoints[0])
                for p in scaledPoints.dropFirst() {
                    cg.addLine(to: p)
                }
                cg.strokePath()
            }
        }
    }

    private func aspectFitRect(image: UIImage, in container: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let aspect = image.size.width / image.size.height
        let containerAspect = container.width / container.height
        let size: CGSize
        if aspect > containerAspect {
            let w = container.width
            size = CGSize(width: w, height: w / aspect)
        } else {
            let h = container.height
            size = CGSize(width: h * aspect, height: h)
        }
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

#Preview {
    ScreenshotAnnotatorView(
        baseImage: UIImage(systemName: "photo")?.withTintColor(.gray) ?? UIImage(),
        onSave: { _ in }
    )
}
