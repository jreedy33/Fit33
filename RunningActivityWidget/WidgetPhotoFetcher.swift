//
//  WidgetPhotoFetcher.swift
//  RunningActivityWidget
//
//  Realtime Widget Server Pull — Phase 8a (2026-04-28).
//
//  Downloads the caller's own profile photo + each opponent's photo
//  directly from Supabase Storage (PostgREST URLs surfaced in the
//  `get_active_challenges` RPC response) and writes the resized JPEGs
//  into the App Group container under the SAME filenames the main
//  app's `Fit33/ActiveChallengeWidgetBridge.swift::publish()` uses:
//
//      group.com.fit33.app/widget_user_photo.jpg
//      group.com.fit33.app/widget_opponent_<opponentId>.jpg
//
//  This matters when the user installs the widget BEFORE ever opening
//  the main app, OR the iPhone has been killed for hours and the in-
//  memory `ProfilePhotoCache` / `FriendPhotoCache` are cold — the
//  bridge can't write photos it doesn't have. Without this fetcher the
//  widget renders the gradient-initials fallback indefinitely; with it
//  the avatars hydrate within the first timeline tick.
//
//  Why this lives in the widget extension (not the main app):
//   • The widget's direct Supabase pull is already authoritative for
//     challenge data (Phase 3, 2026-04-26). Adding photo hydration
//     here keeps the entire "widget freshness" invariant in one place.
//   • The main-app `publish()` is still the writer when the user IS
//     active in the foreground app — that path uses the in-memory
//     image caches and a single 240px resize (matches us byte-for-
//     byte) so once the bridge runs, our cached files become a no-op.
//
//  Resize parity with `ActiveChallengeWidgetBridge.swift`:
//   • Max long side: 240pt
//   • JPEG quality: 0.8
//   • Filename: `widget_user_photo.jpg` / `widget_opponent_<id>.jpg`
//

import Foundation
import OSLog
import UIKit

enum WidgetPhotoFetcher {
    private static let log = Logger(subsystem: "com.fit33.app.RunningActivityWidget", category: "photo-fetch")

    /// Side length the bridge uses (`ActiveChallengeWidgetBridge.photoMaxSide`).
    /// 240px @ 80% quality keeps each file <30KB while still rendering
    /// crisply on the largest medium-widget avatar (38pt @3x = 114px).
    /// Keep in lockstep with the bridge's value.
    private static let photoMaxSide: CGFloat = 240
    private static let jpegQuality: CGFloat = 0.8

    /// App Group constants — keep in sync with
    /// `ActiveChallengeWidgetBridge.appGroupID` /
    /// `userPhotoFilename` / `opponentPhotoPrefix`.
    private static let appGroupID = "group.com.fit33.app"
    private static let userPhotoFilename = "widget_user_photo.jpg"
    private static let opponentPhotoPrefix = "widget_opponent_"

    private static func opponentPhotoFilename(opponentId: String) -> String {
        "\(opponentPhotoPrefix)\(opponentId).jpg"
    }

    /// One opponent input pair. Caller supplies the opponent's id +
    /// optional URL; we skip rows where the URL is nil/empty (server
    /// has no photo for them) AND rows where the App Group already has
    /// a fresh file (the bridge wrote it last main-app foreground).
    struct OpponentInput {
        let opponentId: String
        let photoURL: URL?
    }

    /// Bookkeeping returned to `pullAndMergeIfPossible` so it can stamp
    /// `hasUserPhoto` / `hasOpponentPhoto` on the merged challenge
    /// rows for the on-disk cache. The widget-side render path reads
    /// photos by filename (not by flag), so these flags are mostly
    /// metadata — but keeping them honest avoids confusing the bridge
    /// the next time it runs.
    struct WrittenPhotos {
        var didWriteUserPhoto: Bool
        var didWriteOpponentByID: [String: Bool]

        static let empty = WrittenPhotos(didWriteUserPhoto: false, didWriteOpponentByID: [:])
    }

    /// Ensures both the caller's avatar AND every opponent's avatar
    /// exists in the App Group container. Skips downloads when the file
    /// already exists (bridge already wrote it OR a prior pull cached
    /// it). Bounded per-image timeout keeps the whole pass under
    /// iOS's per-tick budget even when network is flaky.
    ///
    /// - Parameters:
    ///   - userPhotoURL: Caller's own profile photo URL from
    ///     `my_profile_photo_url` in the RPC response. nil = user has
    ///     never uploaded a photo, in which case we leave any existing
    ///     cached file alone (the user might have rotated to a fresh
    ///     account; the next bridge `publish()` will sort it out).
    ///   - opponents: One entry per active 1v1 challenge. Order
    ///     doesn't matter — we de-dupe by `opponentId` so the same
    ///     opponent across multiple challenges only downloads once.
    ///   - perImageTimeout: Hard ceiling on each download. 3s mirrors
    ///     the timeline pull budget so a hostile network never stalls
    ///     the timeline render.
    /// - Returns: `WrittenPhotos` describing exactly which files were
    ///   newly written this pass.
    static func ensureCached(
        userPhotoURL: URL?,
        opponents: [OpponentInput],
        perImageTimeout: TimeInterval = 3.0
    ) async -> WrittenPhotos {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            log.error("Photo fetch skipped: App Group container unavailable")
            return .empty
        }

        var written = WrittenPhotos.empty

        // User photo — sequential (single image, no parallelism win).
        if let url = userPhotoURL {
            let target = containerURL.appendingPathComponent(userPhotoFilename)
            if !FileManager.default.fileExists(atPath: target.path) {
                let ok = await downloadAndWrite(url, to: target, timeout: perImageTimeout)
                written.didWriteUserPhoto = ok
                if ok {
                    log.info("Wrote user avatar to App Group from widget pull")
                }
            }
        }

        // Opponent photos — parallel, per-opponent dedup.
        let uniqueOpponents = dedupedOpponents(opponents)
        let toDownload = uniqueOpponents.compactMap { input -> (String, URL)? in
            guard let url = input.photoURL else { return nil }
            let filename = opponentPhotoFilename(opponentId: input.opponentId)
            let target = containerURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: target.path) { return nil }
            return (input.opponentId, url)
        }

        guard !toDownload.isEmpty else { return written }

        await withTaskGroup(of: (String, Bool).self) { group in
            for (id, url) in toDownload {
                group.addTask {
                    let target = containerURL.appendingPathComponent(opponentPhotoFilename(opponentId: id))
                    let ok = await downloadAndWrite(url, to: target, timeout: perImageTimeout)
                    return (id, ok)
                }
            }
            for await (id, ok) in group where ok {
                written.didWriteOpponentByID[id] = true
            }
        }

        if !written.didWriteOpponentByID.isEmpty {
            log.info("Wrote \(written.didWriteOpponentByID.count, privacy: .public) opponent avatar(s) to App Group from widget pull")
        }

        return written
    }

    // MARK: - Internals

    /// Drops duplicates by `opponentId` (keeping the first non-nil URL
    /// seen). Same opponent can show up across multiple 1v1s with the
    /// caller; downloading their avatar once is enough.
    private static func dedupedOpponents(_ opponents: [OpponentInput]) -> [OpponentInput] {
        var seen = Set<String>()
        var result: [OpponentInput] = []
        for input in opponents where !input.opponentId.isEmpty {
            if seen.insert(input.opponentId).inserted {
                result.append(input)
            }
        }
        return result
    }

    /// Single-shot URL download → in-memory `UIImage` → resize to
    /// `photoMaxSide` → JPEG → atomic write. Returns false on every
    /// failure mode (transport, non-2xx, decode, encode, write) so the
    /// caller can log a uniform "no photo this pass" outcome without
    /// branching.
    private static func downloadAndWrite(
        _ url: URL,
        to target: URL,
        timeout: TimeInterval
    ) async -> Bool {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        // Storage URLs are public — no JWT needed. Anon role can read
        // public buckets via the standard PostgREST path. Adding the
        // anon API key would be wrong (these are direct storage URLs,
        // not RPC calls).
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                if let http = response as? HTTPURLResponse {
                    log.debug("Photo HTTP \(http.statusCode, privacy: .public) at \(url.absoluteString, privacy: .public)")
                }
                return false
            }
            guard let image = UIImage(data: data) else {
                log.debug("Photo decode failed at \(url.absoluteString, privacy: .public)")
                return false
            }
            let resized = resize(image, maxSide: photoMaxSide)
            guard let jpeg = resized.jpegData(compressionQuality: jpegQuality) else {
                log.debug("Photo JPEG encode failed")
                return false
            }
            try jpeg.write(to: target, options: .atomic)
            return true
        } catch {
            // Transport / write failures — quiet at debug, the
            // gradient-initials fallback is acceptable degradation.
            log.debug("Photo download failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Aspect-preserving resize. No-op when the image is already
    /// smaller than `maxSide`. `UIGraphicsImageRenderer` is safe in
    /// extension processes — it allocates a CG context on demand and
    /// doesn't require any UIKit lifecycle to be set up.
    private static func resize(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
