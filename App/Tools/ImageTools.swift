import AppKit
import CoreImage
import HavenCore
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Why a tool couldn't finish, in words for a toast.
enum ToolError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case failed(String)
    case noSubject
    case wrongPassword
    case locked(String)
    case notSmaller
    case needsModel

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): return "Couldn't read “\(name)”"
        case .unsupported(let what): return what
        case .failed(let what): return what
        case .noSubject: return "Couldn't find a subject to cut out"
        case .wrongPassword: return "That password doesn't open it"
        case .locked(let name): return "“\(name)” has a password: remove it first"
        case .notSmaller: return "Already as small as it gets"
        case .needsModel: return "Download the transcription model first (Settings › AI)"
        }
    }
}

/// Converting, resizing, rotating and cleaning images, and cutting out their subject. Always writes a new file.
enum ImageTools {
    /// Formats this Mac can write (HEIC and WebP depend on the Mac and macOS version).
    static var writableFormats: [ImageFormat] {
        let types = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return ImageFormat.allCases.filter { types.contains($0.typeIdentifier) }
    }

    static func source(_ url: URL) throws -> (CGImageSource, [CFString: Any]) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            throw ToolError.unreadable(url.lastPathComponent)
        }
        return (src, props)
    }

    static func pixelSize(_ props: [CFString: Any]) -> (width: Int, height: Int) {
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let o = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        // Orientations 5–8 are stored sideways.
        return o >= 5 ? (h, w) : (w, h)
    }

    /// The picture the right way up, at most `maxSide` pixels on its long side (full size if nil).
    static func upright(_ src: CGImageSource, props: [CFString: Any], maxSide: Int?) throws -> CGImage {
        let size = pixelSize(props)
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide ?? max(size.width, size.height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { throw ToolError.failed("Couldn't read the picture") }
        return image
    }

    /// Writes `image` with the camera details of `props` (upright, so orientation 1).
    static func write(_ image: CGImage, as format: ImageFormat, to dest: URL, props: [CFString: Any], quality: Double = 0.9) throws {
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, format.typeIdentifier as CFString, 1, nil) else {
            throw ToolError.unsupported("This Mac can't write \(format.title) images")
        }
        var image = image
        if format == .jpeg, hasAlpha(image), let flat = ShareMaker.flatten(image) { image = flat }
        var meta: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality, kCGImagePropertyOrientation: 1]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
            if let v = props[key] { meta[key] = v }
        }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            meta[kCGImagePropertyTIFFDictionary] = tiff
        }
        CGImageDestinationAddImage(out, image, meta as CFDictionary)
        guard CGImageDestinationFinalize(out) else {
            try? FileManager.default.removeItem(at: dest)
            throw ToolError.failed("Couldn't save the \(format.title) file")
        }
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        let a = image.alphaInfo
        return !(a == .none || a == .noneSkipFirst || a == .noneSkipLast)
    }

    /// The format to save edits in: the original's when this Mac can write it, otherwise JPEG (PNG for transparent images).
    static func outputFormat(for url: URL, image: CGImage? = nil) -> ImageFormat {
        if let f = ImageFormat.of(url.pathExtension), writableFormats.contains(f) { return f }
        if let image, hasAlpha(image) { return .png }
        return .jpeg
    }

    // MARK: Tools

    static func convert(_ url: URL, to format: ImageFormat, dest: URL) throws {
        let (src, props) = try source(url)
        let image = try upright(src, props: props, maxSide: nil)
        try write(image, as: format, to: dest, props: props, quality: format == .jpeg ? 0.9 : 0.92)
    }

    static func resize(_ url: URL, _ option: ResizeOption, dest: URL) throws {
        let (src, props) = try source(url)
        let size = pixelSize(props)
        let target = option.size(width: size.width, height: size.height)
        let image = try upright(src, props: props, maxSide: max(target.width, target.height))
        try write(image, as: ImageFormat.of(dest.pathExtension) ?? .jpeg, to: dest, props: props, quality: 0.88)
    }

    static func rotate(_ url: URL, _ rotation: Rotation, dest: URL) throws {
        let (src, props) = try source(url)
        let image = try upright(src, props: props, maxSide: nil)
        let w = rotation.swapsSides ? image.height : image.width
        let h = rotation.swapsSides ? image.width : image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ToolError.failed("Couldn't rotate") }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        // Quartz turns counterclockwise for positive angles.
        ctx.rotate(by: -CGFloat(rotation.degrees) * .pi / 180)
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let rotated = ctx.makeImage() else { throw ToolError.failed("Couldn't rotate") }
        try write(rotated, as: ImageFormat.of(dest.pathExtension) ?? .jpeg, to: dest, props: props, quality: 0.95)
    }

    /// What a picture says about where and how it was taken.
    struct PrivateDetails: Equatable {
        var location = false
        var camera = false
        var date = false
        var any: Bool { location || camera || date }
    }

    static func privateDetails(_ url: URL) -> PrivateDetails {
        guard let props = (try? source(url))?.1 else { return PrivateDetails() }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        return PrivateDetails(
            location: props[kCGImagePropertyGPSDictionary] != nil,
            camera: tiff[kCGImagePropertyTIFFModel] != nil || tiff[kCGImagePropertyTIFFMake] != nil || exif[kCGImagePropertyExifLensModel] != nil,
            date: exif[kCGImagePropertyExifDateTimeOriginal] != nil || tiff[kCGImagePropertyTIFFDateTime] != nil
        )
    }

    /// Where, with what and when: the tags a clean copy leaves out (as CGImageMetadata paths).
    static let privateTags = [
        "tiff:Make", "tiff:Model", "tiff:Software", "tiff:DateTime", "tiff:Artist", "tiff:HostComputer", "tiff:Copyright",
        "exif:DateTimeOriginal", "exif:DateTimeDigitized", "exif:SubsecTimeOriginal", "exif:SubsecTimeDigitized", "exif:SubsecTime",
        "exif:OffsetTime", "exif:OffsetTimeOriginal", "exif:OffsetTimeDigitized", "exif:UserComment", "exif:MakerNote",
        "exifEX:LensMake", "exifEX:LensModel", "exifEX:LensSpecification", "exifEX:BodySerialNumber", "exifEX:LensSerialNumber",
        "exifEX:CameraOwnerName", "aux:Lens", "aux:LensInfo", "aux:SerialNumber",
    ]

    /// A copy without location, camera, dates or editing history. Pixels aren't touched (no re-compression)
    /// where macOS can copy the image as is; the picture keeps its orientation and colours.
    static func removeDetails(_ url: URL, dest: URL) throws {
        let (src, props) = try source(url)
        let sameFormat = ImageFormat.of(url.pathExtension) != nil && ImageFormat.of(url.pathExtension) == ImageFormat.of(dest.pathExtension)
        // JPEG: take the detail sections out of the file itself; the picture data is copied byte for byte.
        if sameFormat, ImageFormat.of(url.pathExtension) == .jpeg, let data = try? Data(contentsOf: url),
           let clean = JPEGDetails.strip([UInt8](data), orientation: UInt16(props[kCGImagePropertyOrientation] as? UInt32 ?? 1)) {
            try Data(clean).write(to: dest)
            if !privateDetails(dest).any, (try? source(dest)) != nil { return }
            try? FileManager.default.removeItem(at: dest)
        }
        if sameFormat, let type = CGImageSourceGetType(src), let out = CGImageDestinationCreateWithURL(dest as CFURL, type, 1, nil) {
            // Each private tag set to null is taken out; the picture itself is copied byte for byte.
            let drop = CGImageMetadataCreateMutable()
            for path in privateTags {
                CGImageMetadataSetValueWithPath(drop, nil, path as CFString, kCFNull)
            }
            let opts: [CFString: Any] = [
                kCGImageDestinationMetadata: drop,
                kCGImageDestinationMergeMetadata: true,
                kCGImageMetadataShouldExcludeGPS: true,
                kCGImageMetadataShouldExcludeXMP: true,
            ]
            var error: Unmanaged<CFError>?
            if CGImageDestinationCopyImageSource(out, src, opts as CFDictionary, &error), !privateDetails(dest).any {
                return
            }
        }
        // Formats macOS can't copy as is: draw the pixels into a fresh file with no details at all.
        try? FileManager.default.removeItem(at: dest)
        let image = try upright(src, props: props, maxSide: nil)
        try write(image, as: ImageFormat.of(dest.pathExtension) ?? .png, to: dest, props: [:], quality: 0.9)
    }

    /// Cuts the subject out on a transparent background (PNG), with the same on-device model as Photos.
    static func removeBackground(_ url: URL, dest: URL) throws {
        let (src, props) = try source(url)
        let image = try upright(src, props: props, maxSide: 4096)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ToolError.failed("Couldn't look for a subject: \(error.localizedDescription)")
        }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw ToolError.noSubject }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cut = CIContext().createCGImage(ci, from: ci.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw ToolError.failed("Couldn't make the cut-out")
        }
        try write(cut, as: .png, to: dest, props: [:])
    }
}

/// Removes the sections of a JPEG that hold details (EXIF, XMP, IPTC, comments, maker data) without decoding the
/// picture. Colour profiles stay. The orientation is written back on its own, so the photo stays the right way up.
enum JPEGDetails {
    static func strip(_ bytes: [UInt8], orientation: UInt16) -> [UInt8]? {
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var out: [UInt8] = [0xFF, 0xD8]
        var wroteOrientation = orientation == 1
        var i = 2
        while i + 4 <= bytes.count {
            guard bytes[i] == 0xFF else { return nil }
            let marker = bytes[i + 1]
            if marker == 0xFF { i += 1; continue }                     // padding
            if marker == 0xDA {                                          // the picture: copied as is to the end
                if !wroteOrientation { out += orientationSegment(orientation) }
                out += bytes[i...]
                return out
            }
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            guard length >= 2, i + 2 + length <= bytes.count else { return nil }
            // Keep JFIF (APP0), colour profiles (APP2), Adobe colour info (APP14) and everything that isn't metadata.
            let isDetails = marker == 0xE1 || marker == 0xFE || (0xE3...0xEF).contains(marker) && marker != 0xEE
            if !isDetails {
                out += bytes[i..<(i + 2 + length)]
                // The orientation goes right after JFIF, where readers look for it.
                if marker == 0xE0, !wroteOrientation {
                    out += orientationSegment(orientation)
                    wroteOrientation = true
                }
            }
            i += 2 + length
        }
        return nil
    }

    /// A tiny EXIF section holding only the orientation.
    static func orientationSegment(_ orientation: UInt16) -> [UInt8] {
        var payload: [UInt8] = Array("Exif".utf8) + [0, 0]
        payload += [0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08]          // big-endian TIFF header, IFD at 8
        payload += [0x00, 0x01]                                              // one entry
        payload += [0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01]          // Orientation, SHORT, count 1
        payload += [UInt8(orientation >> 8), UInt8(orientation & 0xFF), 0x00, 0x00]
        payload += [0x00, 0x00, 0x00, 0x00]                                  // no next IFD
        let length = payload.count + 2
        return [0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
    }
}
