import AppKit
import Foundation
import HavenCore
import ImageIO
import Vision

/// Finds identical files (SHA-256) and look-alike photos (Vision feature prints), all on this Mac.
@MainActor
@Observable
final class DuplicateService {
    enum Phase: Equatable {
        case idle
        case hashing(Double)
        case comparingPhotos(Double)
        case done
    }

    private(set) var phase: Phase = .idle
    private(set) var groups: [DuplicateGroup] = []
    private(set) var lastRun: Date?

    @ObservationIgnored private var hashCache: [String: String] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    private var cacheURL: URL { LaunchOptions.current.supportDirectory.appendingPathComponent("hashes.json") }

    /// Distance under which two photos count as look-alikes (Vision feature print distance).
    nonisolated static let similarityThreshold: Float = 0.42

    var isRunning: Bool {
        switch phase {
        case .hashing, .comparingPhotos: return true
        default: return false
        }
    }

    var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }
    var identicalGroups: [DuplicateGroup] { groups.filter { $0.kind == .identical } }
    var similarGroups: [DuplicateGroup] { groups.filter { $0.kind == .similar } }

    func loadCache() {
        guard let d = try? Data(contentsOf: cacheURL), let c = try? JSONDecoder().decode([String: String].self, from: d) else { return }
        hashCache = c
    }

    func scan(items: [FileItem], similar: Bool, quietly: Bool = false) {
        task?.cancel()
        phase = .hashing(0)
        let cache = hashCache
        let url = cacheURL
        let service = self
        task = Task(priority: quietly ? .utility : .userInitiated) {
            let report: @Sendable (Phase) -> Void = { p in
                Task { @MainActor in if service.isRunning { service.phase = p } }
            }
            let result = await DuplicateService.compute(items: items, similar: similar, cache: cache, cacheURL: url, report: report)
            guard !Task.isCancelled else { return }
            service.hashCache = result.cache
            service.groups = result.groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
            service.phase = .done
            service.lastRun = Date()
        }
    }

    /// Runs off the main actor and stops when the calling task is cancelled.
    nonisolated static func compute(items: [FileItem], similar: Bool, cache: [String: String], cacheURL: URL,
                                    report: @escaping @Sendable (Phase) -> Void) async -> (groups: [DuplicateGroup], cache: [String: String]) {
        var localCache = cache
        let identical = DuplicateFinder.identicalGroups(in: items, hashCache: &localCache, progress: { done, total in
            report(.hashing(total == 0 ? 1 : Double(done) / Double(total)))
        }, cancelled: { Task.isCancelled })
        if let d = try? JSONEncoder().encode(localCache) { try? d.write(to: cacheURL, options: .atomic) }
        guard similar, !Task.isCancelled else { return (identical, localCache) }
        report(.comparingPhotos(0))
        // Exact copies are already handled; compare the remaining photos.
        let identicalPaths = Set(identical.flatMap { $0.items.dropFirst().map(\.path) })
        let photos = items.filter {
            $0.kind == .image && !$0.isCloudOnly && !identicalPaths.contains($0.path) && $0.size > 20_000
                && !["svg", "gif", "ico", "icns", "psd"].contains($0.ext)
        }
        let similarGroups = SimilarPhotoFinder.groups(in: photos, threshold: similarityThreshold) { p in
            report(.comparingPhotos(p))
        }
        return (identical + similarGroups, localCache)
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunning { phase = groups.isEmpty ? .idle : .done }
    }

    /// Removes trashed files from the groups (and groups left with one file).
    func forget(paths: Set<String>) {
        groups = groups.compactMap { g in
            var copy = g
            copy.items.removeAll { paths.contains($0.path) }
            guard copy.items.count > 1 else { return nil }
            if paths.contains(copy.suggestedKeep) { copy.suggestedKeep = copy.items[0].path }
            return copy
        }
    }
}

/// Look-alike photo detection with Vision.
enum SimilarPhotoFinder {
    static func featurePrint(for url: URL) -> VNFeaturePrintObservation? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        return request.results?.first
    }

    static func pixelCount(_ url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        return w * h
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        do { try a.computeDistance(&d, to: b) } catch { return nil }
        return d
    }

    static func groups(in photos: [FileItem], threshold: Float, progress: ((Double) -> Void)? = nil) -> [DuplicateGroup] {
        let pairs = SimilarityClusterer.candidatePairs(photos, window: 90)
        guard !pairs.isEmpty else { return [] }
        let needed = Set(pairs.flatMap { [$0.0, $0.1] })
        var prints: [Int: VNFeaturePrintObservation] = [:]
        var done = 0
        for i in needed.sorted() {
            if Task.isCancelled { return [] }
            if let fp = featurePrint(for: photos[i].url) { prints[i] = fp }
            done += 1
            if done % 10 == 0 { progress?(Double(done) / Double(needed.count)) }
        }
        let clusters = SimilarityClusterer.clusters(count: photos.count, pairs: pairs, threshold: threshold) { a, b in
            guard let pa = prints[a], let pb = prints[b] else { return nil }
            return distance(pa, pb)
        }
        return clusters.map { idx in
            let members = idx.map { photos[$0] }
            var pixels: [String: Int] = [:]
            for m in members { pixels[m.path] = pixelCount(m.url) }
            let keep = DuplicateFinder.suggestKeeper(members, kind: .similar, pixels: pixels)
            let ordered = [keep] + members.filter { $0.path != keep.path }
            return DuplicateGroup(id: "sim:" + keep.path, kind: .similar, items: ordered, suggestedKeep: keep.path)
        }
    }
}
