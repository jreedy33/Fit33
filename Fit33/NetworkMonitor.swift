import Foundation
import Network
import SwiftUI

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published private(set) var isConnected = true
    @Published private(set) var connectionType: ConnectionType = .unknown
    /// True when the current path is cellular, a personal hotspot, or anything
    /// else iOS flags as a "metered" connection. Respect this for anything the
    /// user did not explicitly initiate (prefetch, background sync, analytics).
    @Published private(set) var isExpensive: Bool = false
    /// True when the user has enabled Low Data Mode, or the path is otherwise
    /// constrained (e.g. iOS-level data saver). Treat the same as `isExpensive`
    /// for background traffic decisions.
    @Published private(set) var isConstrained: Bool = false

    enum ConnectionType {
        case wifi, cellular, wired, unknown
    }
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.gofit.network-monitor")

    /// Single-shot "should I skip background traffic?" check used by video
    /// prefetch, analytics, and anything else that is NOT directly requested
    /// by a user tap. On-demand playback / uploads / user-initiated requests
    /// should ignore this and proceed.
    ///
    /// Sprint 3 (Q2-30) — introduced so `VideoPreloadManager` and
    /// `VideoStreamingService` stop bleeding cellular data / battery when the
    /// user is on LTE or Low Data Mode.
    var shouldAvoidBackgroundTraffic: Bool {
        isExpensive || isConstrained
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained

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
                    .font(.ds_labelMedium)
                Text("You're offline")
                    .font(.ds_labelMedium)
                Spacer()
                Text("Changes will sync when reconnected")
                    .font(.ds_caption)
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
