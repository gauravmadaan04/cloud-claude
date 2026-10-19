import AppKit
import AVFoundation
import HavenCore
import MediaPlayer

/// Plays songs from the toolbar; works with the keyboard's media keys and Control Center.
@MainActor
@Observable
final class MusicPlayer {
    static let shared = MusicPlayer()

    private(set) var current: FileItem?
    private(set) var queue: [FileItem] = []
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var title = ""
    private(set) var artist = ""
    private(set) var artwork: NSImage?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var remoteConfigured = false

    var hasTrack: Bool { current != nil }

    func play(_ item: FileItem, queue: [FileItem]) {
        self.queue = queue.isEmpty ? [item] : queue
        load(item)
        resume()
    }

    private func load(_ item: FileItem) {
        stopObserving()
        current = item
        title = item.baseName
        artist = ""
        artwork = nil
        position = 0
        duration = 0
        let p = AVPlayer(url: item.url)
        player = p
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = t.seconds
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite { self.duration = d }
                self.updateNowPlaying()
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
        configureRemoteCommands()
        Task { await loadMetadata(item) }
    }

    private func loadMetadata(_ item: FileItem) async {
        let asset = AVURLAsset(url: item.url)
        guard let meta = try? await asset.load(.commonMetadata) else { return }
        // Read everything first, then show it only if this song is still the one playing
        // (skipping quickly must never show the previous song's title or cover).
        var newTitle: String?
        var newArtist: String?
        var newArtwork: NSImage?
        for entry in meta {
            guard let key = entry.commonKey else { continue }
            switch key {
            case .commonKeyTitle:
                if let s = try? await entry.load(.stringValue), !s.isEmpty { newTitle = s }
            case .commonKeyArtist:
                if let s = try? await entry.load(.stringValue) { newArtist = s }
            case .commonKeyArtwork:
                if let d = try? await entry.load(.dataValue), let img = NSImage(data: d) { newArtwork = img }
            default: break
            }
        }
        guard current?.id == item.id else { return }
        if let newTitle { title = newTitle }
        if let newArtist { artist = newArtist }
        if let newArtwork { artwork = newArtwork }
        updateNowPlaying()
    }

    func togglePlayPause() {
        guard player != nil else { return }
        isPlaying ? pause() : resume()
    }

    func resume() {
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func next() {
        guard let c = current, let i = queue.firstIndex(of: c) else { stop(); return }
        if i + 1 < queue.count {
            load(queue[i + 1])
            resume()
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        guard let c = current, let i = queue.firstIndex(of: c) else { return }
        if position > 3 || i == 0 {
            seek(to: 0)
        } else {
            load(queue[i - 1])
            resume()
        }
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
    }

    func stop() {
        pause()
        stopObserving()
        player = nil
        current = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func stopObserving() {
        if let t = timeObserver { player?.removeTimeObserver(t) }
        timeObserver = nil
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        endObserver = nil
    }

    private func configureRemoteCommands() {
        guard !remoteConfigured else { return }
        remoteConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { _ in
            MainActor.assumeIsolated { MusicPlayer.shared.togglePlayPause() }
            return .success
        }
        center.playCommand.addTarget { _ in
            MainActor.assumeIsolated { MusicPlayer.shared.resume() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            MainActor.assumeIsolated { MusicPlayer.shared.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { MusicPlayer.shared.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            MainActor.assumeIsolated { MusicPlayer.shared.previous() }
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let art = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
