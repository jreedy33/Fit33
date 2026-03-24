import SwiftUI
import MediaPlayer
import AVFoundation

// MARK: - Now Playing Mini Bar

import MediaPlayer

struct NowPlayingBar: View {
    @State private var songTitle: String = ""
    @State private var artistName: String = ""
    @State private var isPlaying: Bool = false
    @State private var hasLoaded: Bool = false
    @State private var pollTimer: Timer?
    @State private var albumArtwork: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            if !songTitle.isEmpty {
                HStack(spacing: 10) {
                    if let artwork = albumArtwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.ds_bodyMedium)
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(songTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(artistName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button { skipBack() } label: {
                            Image(systemName: "backward.fill")
                                .font(.ds_bodyMedium)
                                .foregroundColor(.secondary)
                        }
                        
                        Button { togglePlayPause() } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.ds_heading3)
                                .foregroundColor(.primary)
                        }
                        
                        Button { skipForward() } label: {
                            Image(systemName: "forward.fill")
                                .font(.ds_bodyMedium)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
            }
        }
        .onAppear {
            let player = MPMusicPlayerController.systemMusicPlayer
            if !hasLoaded {
                hasLoaded = true
                player.beginGeneratingPlaybackNotifications()
            }
            updateFromNowPlaying()
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)) { _ in
            updateFromNowPlaying()
        }
        .onReceive(NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)) { _ in
            updateFromNowPlaying()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            updateFromNowPlaying()
        }
    }
    
    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            DispatchQueue.main.async { updateFromNowPlaying() }
        }
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    private func togglePlayPause() {
        HapticManager.selectionChanged()
        let player = MPMusicPlayerController.systemMusicPlayer
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }
    
    private func skipForward() {
        HapticManager.selectionChanged()
        MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        refreshNowPlaying()
    }
    
    private func skipBack() {
        HapticManager.selectionChanged()
        MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
        refreshNowPlaying()
    }
    
    private func refreshNowPlaying() {
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.3)); updateFromNowPlaying() }
    }
    
    private func updateFromNowPlaying() {
        let player = MPMusicPlayerController.systemMusicPlayer
        let item = player.nowPlayingItem
        
        songTitle = item?.title ?? ""
        artistName = item?.artist ?? ""
        isPlaying = player.playbackState == .playing
        
        // Get artwork — keep existing if new fetch fails (transient nil)
        if let img = item?.artwork?.image(at: CGSize(width: 200, height: 200)) {
            albumArtwork = img
        } else if songTitle != (item?.title ?? "") {
            albumArtwork = nil
        }
        
        // Fallback for non-Apple Music apps (Spotify, etc.)
        if songTitle.isEmpty && AVAudioSession.sharedInstance().isOtherAudioPlaying {
            songTitle = "Now Playing"
            artistName = "External App"
            isPlaying = true
        }
    }
}
