import SwiftUI

struct LevelUpCelebrationOverlay: View {
    let level: Int
    let levelTitle: String
    let levelIcon: String
    let levelColor: Color
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var iconScale: CGFloat = 0.3
    @State private var textOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var sparkleRotation: Double = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
            
            VStack(spacing: Spacing.lg) {
                // Animated level icon with rings
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(levelColor.opacity(0.3), lineWidth: 4)
                        .frame(width: 140, height: 140)
                        .scaleEffect(ringScale)
                        .blur(radius: 4)
                    
                    // Sparkle ring
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [levelColor, .white.opacity(0.6), levelColor],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(sparkleRotation))
                    
                    // Main icon circle
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [levelColor.opacity(0.4), levelColor.opacity(0.1)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: levelIcon)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [levelColor, .white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: levelColor.opacity(0.6), radius: 12, x: 0, y: 0)
                }
                .scaleEffect(iconScale)
                
                VStack(spacing: Spacing.sm) {
                    Text("LEVEL UP!")
                        .font(.ds_displayMedium)
                        .fontWeight(.black)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [levelColor, .white],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Level \(level)")
                        .font(.ds_stat)
                        .foregroundColor(.white)
                    
                    Text(levelTitle)
                        .font(.ds_heading3)
                        .foregroundColor(.white.opacity(0.8))
                }
                .opacity(textOpacity)
                
                // Dismiss button
                Button(action: onDismiss) {
                    Text("Continue")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: 200)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            LinearGradient(
                                colors: [levelColor, levelColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill))
                        )
                }
                .opacity(textOpacity)
                .padding(.top, Spacing.sm)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) {
                iconScale = 1.0
                ringScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                textOpacity = 1.0
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                sparkleRotation = 360
            }
            
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5.0))
                guard !Task.isCancelled else { return }
                onDismiss()
            }
        }
    }
}
