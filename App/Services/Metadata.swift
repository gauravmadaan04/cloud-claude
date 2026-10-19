import AppKit
import AVFoundation
import HavenCore
import ImageIO
import PDFKit

/// Extra details for the inspector, read on demand.
struct FileDetails {
    var rows: [(String, String)] = []
}

enum MetadataReader {
    static func details(for item: FileItem) async -> FileDetails {
        var d = FileDetails()
        switch item.kind {
        case .image:
            d.rows += imageRows(item.url)
        case .video, .audio:
            d.rows += await mediaRows(item.url, video: item.kind == .video)
        case .pdf:
            if let doc = PDFDocument(url: item.url) {
                d.rows.append(("Pages", "\(doc.pageCount)"))
                if let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
                    d.rows.append(("Title", title))
                }
                if let author = doc.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
                    d.rows.append(("Author", author))
                }
            }
        case .app:
            if let bundle = Bundle(url: item.url) {
                if let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { d.rows.append(("Version", v)) }
                if let id = bundle.bundleIdentifier { d.rows.append(("Identifier", id)) }
            }
        default:
            break
        }
        return d
    }

    static func imageRows(_ url: URL) -> [(String, String)] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return [] }
        var rows: [(String, String)] = []
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            rows.append(("Dimensions", "\(w) × \(h)"))
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let camera = model.hasPrefix(make) ? model : [make, model].filter { !$0.isEmpty }.joined(separator: " ")
            if !camera.isEmpty { rows.append(("Camera", camera)) }
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let lens = exif[kCGImagePropertyExifLensModel] as? String { rows.append(("Lens", lens)) }
            var exposure: [String] = []
            if let f = exif[kCGImagePropertyExifFNumber] as? Double { exposure.append(String(format: "ƒ/%.1f", f)) }
            if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
                exposure.append(t >= 1 ? String(format: "%.1fs", t) : "1/\(Int((1 / t).rounded()))s")
            }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { exposure.append("ISO \(iso)") }
            if !exposure.isEmpty { rows.append(("Exposure", exposure.joined(separator: "  "))) }
            if let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String { rows.append(("Taken", prettyExifDate(taken))) }
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double, let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let ns = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
            let ew = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
            rows.append(("Location", String(format: "%.4f° %@, %.4f° %@", lat, ns, lon, ew)))
        }
        return rows
    }

    static func prettyExifDate(_ s: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let d = f.date(from: s) else { return s }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    static func mediaRows(_ url: URL, video: Bool) async -> [(String, String)] {
        let asset = AVURLAsset(url: url)
        var rows: [(String, String)] = []
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 {
            rows.append(("Duration", HavenFormat.duration(duration.seconds)))
        }
        if video, let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize) {
            rows.append(("Resolution", "\(Int(abs(size.width))) × \(Int(abs(size.height)))"))
        }
        if !video, let meta = try? await asset.load(.commonMetadata) {
            for entry in meta {
                if entry.commonKey == .commonKeyArtist, let s = try? await entry.load(.stringValue) { rows.append(("Artist", s)) }
                if entry.commonKey == .commonKeyAlbumName, let s = try? await entry.load(.stringValue) { rows.append(("Album", s)) }
            }
        }
        return rows
    }
}
