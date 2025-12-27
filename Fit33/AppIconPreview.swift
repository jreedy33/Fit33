import SwiftUI

// MARK: - App Icon Preview
// Use this view to preview/export the app icon design
// Screenshot at 1024x1024 for the App Store icon

struct AppIconPreview: View {
    var body: some View {
        ZStack {
            // App background gradient (matches home tab)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.10, green: 0.06, blue: 0.15),
                    Color(red: 0.06, green: 0.04, blue: 0.10),
                    Color(red: 0.04, green: 0.04, blue: 0.06)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Fit33 logo - exactly like header
            HStack(spacing: 0) {
                Text("Fit")
                    .font(.system(size: 280, weight: .bold, design: .default))
                    .foregroundColor(.white)
                
                Text("33")
                    .font(.system(size: 280, weight: .bold, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.3, green: 0.5, blue: 0.7), Color(red: 0.4, green: 0.6, blue: 0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .shadow(color: .blue.opacity(0.4), radius: 20, x: 0, y: 8)
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 0)) // Square for export
    }
}

// Light mode version (if needed)
struct AppIconPreviewLight: View {
    var body: some View {
        ZStack {
            // Light app background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.95, green: 0.93, blue: 1.0),
                    Color(red: 0.92, green: 0.90, blue: 0.98),
                    Color.white
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Fit33 logo
            HStack(spacing: 0) {
                Text("Fit")
                    .font(.system(size: 280, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.25))
                
                Text("33")
                    .font(.system(size: 280, weight: .bold, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.3, green: 0.5, blue: 0.7), Color(red: 0.4, green: 0.6, blue: 0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 6)
        }
        .frame(width: 1024, height: 1024)
    }
}

// Preview for Xcode canvas
#Preview("App Icon - Dark") {
    AppIconPreview()
}

#Preview("App Icon - Light") {
    AppIconPreviewLight()
}
