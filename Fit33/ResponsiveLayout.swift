import SwiftUI

// MARK: - Responsive Stack
/// Switches between VStack (compact horizontal size class) and HStack (regular)

struct ResponsiveStack<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let hSpacing: CGFloat
    let vSpacing: CGFloat
    let alignment: VerticalAlignment
    @ViewBuilder let content: () -> Content

    init(
        hSpacing: CGFloat = Spacing.md,
        vSpacing: CGFloat = Spacing.md,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.hSpacing = hSpacing
        self.vSpacing = vSpacing
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        if sizeClass == .regular {
            HStack(alignment: alignment, spacing: hSpacing) { content() }
        } else {
            VStack(spacing: vSpacing) { content() }
        }
    }
}

// MARK: - Adaptive Grid
/// Returns a column layout array sized for the current device

struct AdaptiveGridLayout {
    static func columns(minWidth: CGFloat = 160) -> [GridItem] {
        let count = Spacing.adaptiveColumns(minWidth: minWidth)
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: count)
    }
}

// MARK: - Device Conditional Modifier
/// Shows content only on specified device tiers

struct DeviceConditionalModifier: ViewModifier {
    let tiers: Set<DeviceTier>

    func body(content: Content) -> some View {
        if tiers.contains(DeviceTier.current) {
            content
        }
    }
}

extension View {
    func visibleOn(_ tiers: DeviceTier...) -> some View {
        modifier(DeviceConditionalModifier(tiers: Set(tiers)))
    }

    func hiddenOn(_ tiers: DeviceTier...) -> some View {
        let allTiers: Set<DeviceTier> = [.compact, .standard, .large, .tablet]
        let visible = allTiers.subtracting(Set(tiers))
        return modifier(DeviceConditionalModifier(tiers: visible))
    }
}

// MARK: - Minimum Touch Target Modifier

struct MinimumTouchTargetModifier: ViewModifier {
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

extension View {
    func touchTarget(_ size: CGFloat = 44) -> some View {
        modifier(MinimumTouchTargetModifier(size: size))
    }
}
