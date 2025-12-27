import SwiftUI

/// Custom 6-pack abs icon for Core exercises
struct CoreIcon: View {
    var size: CGFloat = 24
    var color: Color = .yellow
    
    var body: some View {
        Canvas { context, canvasSize in
            let scale = size / 10 // Scale factor to fill the circle
            let centerX = canvasSize.width / 2
            let gap = 0.4 * scale // Gap between left and right
            
            // Top Row - rounded rectangles
            let topWidth = 4.2 * scale
            let topHeight = 2.5 * scale
            let topY = 0.3 * scale
            let topCorner = 1.2 * scale
            
            // Left top
            let topLeftRect = RoundedRectangle(cornerRadius: topCorner)
                .path(in: CGRect(x: centerX - gap - topWidth, y: topY, width: topWidth, height: topHeight))
            context.fill(topLeftRect, with: .color(color))
            
            // Right top
            let topRightRect = RoundedRectangle(cornerRadius: topCorner)
                .path(in: CGRect(x: centerX + gap, y: topY, width: topWidth, height: topHeight))
            context.fill(topRightRect, with: .color(color))
            
            // Middle Row - slightly rounded rectangles
            let midWidth = 4.2 * scale
            let midHeight = 2.5 * scale
            let midY = topY + topHeight + 0.5 * scale
            let midCorner = 1.2 * scale
            
            // Left middle
            let midLeftRect = RoundedRectangle(cornerRadius: midCorner)
                .path(in: CGRect(x: centerX - gap - midWidth, y: midY, width: midWidth, height: midHeight))
            context.fill(midLeftRect, with: .color(color))
            
            // Right middle
            let midRightRect = RoundedRectangle(cornerRadius: midCorner)
                .path(in: CGRect(x: centerX + gap, y: midY, width: midWidth, height: midHeight))
            context.fill(midRightRect, with: .color(color))
            
            // Bottom Row - angled/organic shapes (V-shaped abs)
            let botY = midY + midHeight + 0.5 * scale
            let botHeight = 3.8 * scale
            let botTopWidth = 4.2 * scale
            let botBottomWidth = 2.8 * scale
            let botCorner = 1.4 * scale
            
            // Left bottom - angled inward at bottom
            var leftBotPath = Path()
            leftBotPath.move(to: CGPoint(x: centerX - gap - botTopWidth + botCorner, y: botY))
            leftBotPath.addLine(to: CGPoint(x: centerX - gap - botCorner, y: botY))
            leftBotPath.addQuadCurve(to: CGPoint(x: centerX - gap, y: botY + botCorner),
                                      control: CGPoint(x: centerX - gap, y: botY))
            leftBotPath.addLine(to: CGPoint(x: centerX - gap, y: botY + botHeight - botCorner))
            leftBotPath.addQuadCurve(to: CGPoint(x: centerX - gap - botCorner, y: botY + botHeight),
                                      control: CGPoint(x: centerX - gap, y: botY + botHeight))
            leftBotPath.addLine(to: CGPoint(x: centerX - gap - botBottomWidth + botCorner, y: botY + botHeight))
            leftBotPath.addQuadCurve(to: CGPoint(x: centerX - gap - botBottomWidth, y: botY + botHeight - botCorner),
                                      control: CGPoint(x: centerX - gap - botBottomWidth, y: botY + botHeight))
            leftBotPath.addLine(to: CGPoint(x: centerX - gap - botTopWidth, y: botY + botCorner))
            leftBotPath.addQuadCurve(to: CGPoint(x: centerX - gap - botTopWidth + botCorner, y: botY),
                                      control: CGPoint(x: centerX - gap - botTopWidth, y: botY))
            leftBotPath.closeSubpath()
            context.fill(leftBotPath, with: .color(color))
            
            // Right bottom - angled inward at bottom (mirrored)
            var rightBotPath = Path()
            rightBotPath.move(to: CGPoint(x: centerX + gap + botCorner, y: botY))
            rightBotPath.addLine(to: CGPoint(x: centerX + gap + botTopWidth - botCorner, y: botY))
            rightBotPath.addQuadCurve(to: CGPoint(x: centerX + gap + botTopWidth, y: botY + botCorner),
                                       control: CGPoint(x: centerX + gap + botTopWidth, y: botY))
            rightBotPath.addLine(to: CGPoint(x: centerX + gap + botBottomWidth, y: botY + botHeight - botCorner))
            rightBotPath.addQuadCurve(to: CGPoint(x: centerX + gap + botBottomWidth - botCorner, y: botY + botHeight),
                                       control: CGPoint(x: centerX + gap + botBottomWidth, y: botY + botHeight))
            rightBotPath.addLine(to: CGPoint(x: centerX + gap + botCorner, y: botY + botHeight))
            rightBotPath.addQuadCurve(to: CGPoint(x: centerX + gap, y: botY + botHeight - botCorner),
                                       control: CGPoint(x: centerX + gap, y: botY + botHeight))
            rightBotPath.addLine(to: CGPoint(x: centerX + gap, y: botY + botCorner))
            rightBotPath.addQuadCurve(to: CGPoint(x: centerX + gap + botCorner, y: botY),
                                       control: CGPoint(x: centerX + gap, y: botY))
            rightBotPath.closeSubpath()
            context.fill(rightBotPath, with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Core icons
        HStack(spacing: 20) {
            CoreIcon(size: 14, color: .yellow)
            CoreIcon(size: 24, color: .yellow)
            CoreIcon(size: 36, color: .yellow)
        }
        
        // In circle background like exercise cards
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.15))
                .frame(width: 36, height: 36)
            CoreIcon(size: 22, color: .yellow)
        }
    }
    .padding()
}

