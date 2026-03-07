import Foundation
import Network
import SwiftUI

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published private(set) var isConnected = true
    @Published private(set) var connectionType: ConnectionType = .unknown
    
    enum ConnectionType {
        case wifi, cellular, wired, unknown
    }
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.gofit.network-monitor")
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = .wired
                } else {
                    self.connectionType = .unknown
                }
                
                if !wasConnected && self.isConnected {
                    NotificationCenter.default.post(name: .networkReconnected, object: nil)
                }
            }
        }
        monitor.start(queue: queue)
    }
}

extension Notification.Name {
    static let networkReconnected = Notification.Name("networkReconnected")
}

// MARK: - Offline Banner View

struct OfflineBanner: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var show = false
    
    var body: some View {
        if !network.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13, weight: .semibold))
                Text("You're offline")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Changes will sync when reconnected")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.9))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
