import AVFoundation
import CoreMedia
import HavenCore
import ImageIO
import UniformTypeIdentifiers

/// Progress back to a job card, from any thread (0…1).
typealias ProgressHandler = @Sendable (Double) -> Void

/// Video and audio with AVFoundation only (no FFmpeg to install). Always writes new files.
enum MediaTools {
    private final class SessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ session: AVAssetExportSession) { self.session = session }
    }

    static func fileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "mp4": return .mp4
        case "m4v": return .m4v
        case "m4a": return .m4a
        default: return .mov
        }
    }

    static func size(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Runs an export with progress, and stops it if the job is cancelled.
    static func export(_ session: AVAssetExportSession, to dest: URL, type: AVFileType, progress: ProgressHandler?) async throws {
        session.outputURL = dest
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        let box = SessionBox(session)
        let poll = Task.detached {
            while !Task.isCancelled {
                progress?(Double(box.session.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { poll.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                box.session.exportAsynchronously { done.resume() }
            }
        } onCancel: {
            box.session.cancelExport()
        }
        switch session.status {
        case .completed:
            progress?(1)
        case .cancelled:
            try? FileManager.default.removeItem(at: dest)
            throw CancellationError()
        default:
            try? FileManager.default.removeItem(at: dest)
            throw ToolError.failed(session.error?.localizedDescription ?? "Couldn't save “\(dest.lastPathComponent)”")
        }
    }

    private static func session(_ asset: AVAsset, _ preset: String) throws -> AVAssetExportSession {
        guard let s = AVAssetExportSession(asset: asset, presetName: preset) else { throw ToolError.unsupported("macOS can't convert this file") }
        return s
    }

    private static func requireVideo(_ asset: AVURLAsset) async throws -> AVAssetTrack {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ToolError.failed("“\(asset.url.lastPathComponent)” has no picture")
        }
        return track
    }

    // MARK: Video

    /// Smaller, at the chosen size. A copy that wouldn't be smaller isn't kept.
    static func compress(_ url: URL, _ quality: VideoQuality, dest: URL, progress: ProgressHandler?) async throws {
        let asset = AVURLAsset(url: url)
        _ = try await requireVideo(asset)
        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let wanted: [String]
        switch quality {
        case .high: wanted = [AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1920x1080]
        case .medium: wanted = [AVAssetExportPreset1280x720]
        case .small: wanted = [AVAssetExportPreset960x540]
        }
        guard let preset = wanted.first(where: presets.contains) else { throw ToolError.unsupported("macOS can't compress this video") }
        try await export(try session(asset, preset), to: dest, type: .mp4, progress: progress)
        if size(dest) >= size(url) * 97 / 100 {
            try? FileManager.default.removeItem(at: dest)
            throw ToolError.notSmaller
        }
    }

    /// MP4 or MOV. The picture and sound are copied untouched when the new container can hold them.
    static func convert(_ url: URL, to container: VideoContainer, dest: URL, progress: ProgressHandler?) async throws {
        let asset = AVURLAsset(url: url)
        let type: AVFileType = container == .mp4 ? .mp4 : .mov
        if let s = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough), s.supportedFileTypes.contains(type) {
            do {
                try await export(s, to: dest, type: type, progress: progress)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Re-encode below.
            }
        }
        try await export(try session(asset, AVAssetExportPresetHighestQuality), to: dest, type: type, progress: progress)
    }

    /// Keeps `range`. Video is copied without re-encoding; audio becomes M4A.
    static func trim(_ url: URL, range: CMTimeRange, dest: URL, progress: ProgressHandler?) async throws {
        let asset = AVURLAsset(url: url)
        let hasVideo = !(try await asset.loadTracks(withMediaType: .video)).isEmpty
        let s = try session(asset, hasVideo ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A)
        s.timeRange = range
        try await export(s, to: dest, type: hasVideo ? fileType(for: dest) : .m4a, progress: progress)
    }

    /// The soundtrack as M4A.
    static func extractAudio(_ url: URL, dest: URL, progress: ProgressHandler?) async throws {
        let asset = AVURLAsset(url: url)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw ToolError.failed("“\(url.lastPathComponent)” has no sound")
        }
        try await export(try session(asset, AVAssetExportPresetAppleM4A), to: dest, type: .m4a, progress: progress)
    }

    /// The same video without sound (the picture isn't re-encoded).
    static func mute(_ url: URL, dest: URL, progress: ProgressHandler?) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let comp = AVMutableComposition()
        for track in try await asset.loadTracks(withMediaType: .video) {
            guard let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try t.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
            t.preferredTransform = try await track.load(.preferredTransform)
        }
        guard !comp.tracks.isEmpty else { throw ToolError.failed("“\(url.lastPathComponent)” has no picture") }
        try await export(try session(comp, AVAssetExportPresetPassthrough), to: dest, type: fileType(for: dest), progress: progress)
    }

    /// Clips one after another. Each is turned upright and fitted into the first clip's frame.
    static func merge(_ urls: [URL], dest: URL, progress: ProgressHandler?) async throws {
        let comp = AVMutableComposition()
        guard let video = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ToolError.failed("Couldn't merge")
        }
        var cursor = CMTime.zero
        var renderSize = CGSize.zero
        var segments: [(start: CMTime, transform: CGAffineTransform, size: CGSize)] = []
        for url in urls {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let v = try await requireVideo(asset)
            let range = CMTimeRange(start: .zero, duration: duration)
            try video.insertTimeRange(range, of: v, at: cursor)
            if let a = try await asset.loadTracks(withMediaType: .audio).first {
                try audio.insertTimeRange(range, of: a, at: cursor)
            }
            let natural = try await v.load(.naturalSize)
            let transform = try await v.load(.preferredTransform)
            let turned = CGRect(origin: .zero, size: natural).applying(transform)
            let upright = CGSize(width: abs(turned.width), height: abs(turned.height))
            if renderSize == .zero { renderSize = upright }
            segments.append((cursor, transform.concatenating(CGAffineTransform(translationX: -turned.minX, y: -turned.minY)), upright))
            cursor = cursor + duration
        }
        if audio.segments.isEmpty { comp.removeTrack(audio) }
        let even = CGSize(width: (renderSize.width / 2).rounded() * 2, height: (renderSize.height / 2).rounded() * 2)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
        for seg in segments {
            let scale = min(even.width / seg.size.width, even.height / seg.size.height)
            let tx = (even.width - seg.size.width * scale) / 2, ty = (even.height - seg.size.height * scale) / 2
            let t = seg.transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: tx, y: ty))
            layer.setTransform(t, at: seg.start)
        }
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = even
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        let s = try session(comp, AVAssetExportPresetHighestQuality)
        s.videoComposition = videoComposition
        try await export(s, to: dest, type: fileType(for: dest), progress: progress)
    }

    /// Slower or faster. Voices keep their pitch.
    static func changeSpeed(_ url: URL, _ speed: PlaybackSpeed, dest: URL, progress: ProgressHandler?) async throws {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        let comp = AVMutableComposition()
        for track in try await asset.load(.tracks) where track.mediaType == .video || track.mediaType == .audio {
            guard let t = comp.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try t.insertTimeRange(range, of: track, at: .zero)
            if track.mediaType == .video { t.preferredTransform = try await track.load(.preferredTransform) }
        }
        guard !comp.tracks.isEmpty else { throw ToolError.unreadable(url.lastPathComponent) }
        comp.scaleTimeRange(range, toDuration: CMTimeMultiplyByFloat64(duration, multiplier: 1 / speed.rawValue))
        let hasVideo = comp.tracks.contains { $0.mediaType == .video }
        let s = try session(comp, hasVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A)
        s.audioTimePitchAlgorithm = .spectral
        try await export(s, to: dest, type: hasVideo ? fileType(for: dest) : .m4a, progress: progress)
    }

    /// A looping GIF (12 frames a second, fewer for long clips).
    static func gif(_ url: URL, _ size: GIFSize, dest: URL, progress: ProgressHandler?) async throws {
        let asset = AVURLAsset(url: url)
        _ = try await requireVideo(asset)
        let duration = try await asset.load(.duration).seconds
        let times = GIFPlan.frameTimes(duration: duration, fps: 12, maxFrames: 240)
        guard !times.isEmpty else { throw ToolError.failed("The video is empty") }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.rawValue, height: size.rawValue)
        let tolerance = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
            throw ToolError.failed("Couldn't create the GIF")
        }
        CGImageDestinationSetProperties(out, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let delay = GIFPlan.delay(duration: duration, frames: times.count)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        for (i, t) in times.enumerated() {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: dest)
                throw CancellationError()
            }
            let image = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
            CGImageDestinationAddImage(out, image, frame)
            progress?(Double(i + 1) / Double(times.count))
        }
        guard CGImageDestinationFinalize(out) else {
            try? FileManager.default.removeItem(at: dest)
            throw ToolError.failed("Couldn't save the GIF")
        }
    }

    // MARK: Audio

    static func audioSettings(_ format: AudioFormat, rate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        switch format {
        case .m4a:
            return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: min(rate, 48_000), AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: channels > 1 ? 256_000 : 128_000]
        case .wav, .aiff:
            return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: format == .aiff,
                    AVLinearPCMIsNonInterleaved: false]
        case .flac:
            return [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: channels, AVEncoderBitDepthHintKey: 16]
        }
    }

    /// M4A, WAV, AIFF or FLAC, read and written in blocks off the main thread.
    static func convertAudio(_ url: URL, to format: AudioFormat, dest: URL, progress: ProgressHandler?) async throws {
        try await Task.detached(priority: .userInitiated) {
            do {
                try convertAudioNow(url, to: format, dest: dest, progress: progress)
            } catch {
                try? FileManager.default.removeItem(at: dest)
                throw error
            }
        }.value
    }

    private static func convertAudioNow(_ url: URL, to format: AudioFormat, dest: URL, progress: ProgressHandler?) throws {
        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: url) } catch { throw ToolError.unreadable(url.lastPathComponent) }
        let source = input.processingFormat
        let settings = audioSettings(format, rate: source.sampleRate, channels: source.channelCount)
        let output: AVAudioFile
        do {
            output = try AVAudioFile(forWriting: dest, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw ToolError.unsupported("macOS can't write \(format.title) here")
        }
        let target = output.processingFormat
        let block: AVAudioFrameCount = 32_768
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: block) else { throw ToolError.failed("Out of memory") }
        let total = max(1, input.length)
        // Same layout: copy blocks straight through. Different rate (AAC tops out at 48 kHz): convert on the way.
        let converter = source == target ? nil : AVAudioConverter(from: source, to: target)
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: inBuffer, frameCount: block)
            if inBuffer.frameLength == 0 { break }
            if let converter {
                let ratio = target.sampleRate / source.sampleRate
                guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 1024) else { break }
                var fed = false
                var error: NSError?
                converter.convert(to: outBuffer, error: &error) { _, status in
                    if fed {
                        status.pointee = .noDataNow
                        return nil
                    }
                    fed = true
                    status.pointee = .haveData
                    return inBuffer
                }
                if let error { throw error }
                try output.write(from: outBuffer)
            } else {
                try output.write(from: inBuffer)
            }
            progress?(Double(input.framePosition) / Double(total))
        }
    }

    /// How long a file plays, in seconds.
    static func duration(_ url: URL) async -> Double {
        (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
    }
}
