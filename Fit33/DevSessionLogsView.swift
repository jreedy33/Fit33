//
//  DevSessionLogsView.swift
//  GoFit
//
//  Developer-only view for viewing session logs
//

import SwiftUI

#if DEBUG
struct DevSessionLogsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSession: Int = 0
    @State private var logContent: String = ""
    @State private var showShareSheet = false
    @State private var showCopiedToast = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: colorScheme == .dark 
                    ? [Color(red: 0.08, green: 0.10, blue: 0.15), Color.black]
                    : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Session Picker
                Picker("Session", selection: $selectedSession) {
                    Text("Current").tag(0)
                    Text("Previous").tag(1)
                    Text("2 Sessions Ago").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Crash indicator
                if selectedSession == 1 && SessionLogManager.shared.hasCrashLog {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Previous session crashed!")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: copyLogs) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { showShareSheet = true }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: refreshLogs) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
                
                // Log content
                ScrollView {
                    Text(logContent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .background(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                .cornerRadius(CornerRadius.md)
                .padding(.horizontal)
                .padding(.bottom)
            }
            
            // Copied toast
            if showCopiedToast {
                VStack {
                    Spacer()
                    Text("✓ Copied to clipboard")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.green)
                        .cornerRadius(25)
                        .shadow(radius: 10)
                    Spacer().frame(height: 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Session Logs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshLogs()
        }
        .onChange(of: selectedSession) { _ in
            refreshLogs()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [logContent])
        }
    }
    
    private func refreshLogs() {
        SessionLogManager.shared.devLogs(session: selectedSession)
        
        switch selectedSession {
        case 0:
            logContent = SessionLogManager.shared.exportLogsAsText()
        case 1, 2:
            let url = selectedSession == 1 
                ? SessionLogManager.shared.previous1LogURL 
                : SessionLogManager.shared.previous2LogURL
            if FileManager.default.fileExists(atPath: url.path) {
                logContent = (try? String(contentsOf: url, encoding: .utf8)) ?? "Failed to read logs"
            } else {
                logContent = "No logs found for this session"
            }
        default:
            logContent = "Invalid session"
        }
    }
    
    private func copyLogs() {
        UIPasteboard.general.string = logContent
        
        withAnimation(.spring()) {
            showCopiedToast = true
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        DevSessionLogsView()
    }
}
#endif

// MARK: - Share Sheet (available in all build configurations)
/// Reusable share sheet wrapper used by MyQRCodeView and other non-debug views.
/// Must live outside #if DEBUG so it's available in Release/Archive builds.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
