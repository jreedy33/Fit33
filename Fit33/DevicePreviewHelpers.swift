import SwiftUI

// MARK: - Multi-Device Preview Configurations
// Usage: Add to any #Preview block to see the view across all key device sizes.
//
// #Preview("iPhone SE") { MyView().previewDevice(.iPhoneSE) }
// #Preview("iPad Pro") { MyView().previewDevice(.iPadPro13) }

extension PreviewDevice {
    static let iPhoneSE = PreviewDevice(rawValue: "iPhone SE (3rd generation)")
    static let iPhone15Pro = PreviewDevice(rawValue: "iPhone 15 Pro")
    static let iPhone15ProMax = PreviewDevice(rawValue: "iPhone 15 Pro Max")
    static let iPadMini = PreviewDevice(rawValue: "iPad mini (6th generation)")
    static let iPadPro13 = PreviewDevice(rawValue: "iPad Pro 13-inch (M4)")
}

extension View {
    func previewDevice(_ device: PreviewDevice) -> some View {
        self.previewDevice(device)
            .previewDisplayName(device.rawValue)
    }

    func previewAllDevices() -> some View {
        Group {
            self.previewDevice(.iPhoneSE)
            self.previewDevice(.iPhone15Pro)
            self.previewDevice(.iPhone15ProMax)
            self.previewDevice(.iPadPro13)
        }
    }
}
