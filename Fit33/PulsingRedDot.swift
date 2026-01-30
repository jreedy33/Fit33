import SwiftUI

// MARK: - Pulsing Red Dot
/// A small red dot indicator with a pulsing animation
/// Used to draw attention to new content (workouts, friend requests, etc.)

struct PulsingRedDot: View {
    @State private var isPulsing = false
    
    var size: CGFloat = 12
    var color: Color = .red
    
    var body: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: size * 1.8, height: size * 1.8)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)
            
            // Inner solid dot
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.5), radius: 3, x: 0, y: 1)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Notification Badge
/// A small number badge for showing counts (e.g., "3" new items)

struct NotificationBadge: View {
    let count: Int
    var backgroundColor: Color = .red
    var textColor: Color = .white
    var size: CGFloat = 18
    
    var body: some View {
        if count > 0 {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: size, height: size)
                
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundColor(textColor)
                    .minimumScaleFactor(0.5)
            }
            .shadow(color: backgroundColor.opacity(0.4), radius: 2, x: 0, y: 1)
        }
    }
}

#Preview("Pulsing Red Dot") {
    VStack(spacing: 40) {
        // Default size
        PulsingRedDot()
        
        // Custom size
        PulsingRedDot(size: 8)
        
        // Different color
        PulsingRedDot(size: 14, color: .orange)
    }
    .padding(50)
    .background(Color.gray.opacity(0.2))
}

#Preview("Notification Badge") {
    VStack(spacing: 20) {
        NotificationBadge(count: 1)
        NotificationBadge(count: 5)
        NotificationBadge(count: 99)
        NotificationBadge(count: 150)
    }
    .padding(50)
    .background(Color.gray.opacity(0.2))
}
