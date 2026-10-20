import Foundation
#if canImport(Compression)
import Compression
#endif

/// Decompresses raw DEFLATE data (what ZIP files use). On the Mac this is Apple's Compression framework;
/// elsewhere (and when `portableOnly` is set, for tests) a small decoder written after zlib's puff.c.
/// Output stops at `limit` bytes, so a malicious archive can't make Haven use unbounded memory.
public enum Inflate {
    public enum Failure: Error { case corrupt }

    /// Tests set this to exercise the portable decoder on the Mac too.
    nonisolated(unsafe) public static var portableOnly = false

    public static func inflate(_ input: UnsafeBufferPointer<UInt8>, expectedSize: Int, limit: Int) throws -> [UInt8] {
        #if canImport(Compression)
        if !portableOnly, let out = system(input, expectedSize: expectedSize, limit: limit) { return out }
        #endif
        var d = Decoder(input: input, limit: limit)
        return try d.run()
    }

    #if canImport(Compression)
    static func system(_ src: UnsafeBufferPointer<UInt8>, expectedSize: Int, limit: Int) -> [UInt8]? {
        guard let base = src.baseAddress, src.count > 0 else { return [] }
        let capacity = max(64, min(limit, expectedSize > 0 ? expectedSize : limit))
        var out = [UInt8](repeating: 0, count: capacity)
        let n = out.withUnsafeMutableBufferPointer { dst in
            compression_decode_buffer(dst.baseAddress!, capacity, base, src.count, nil, COMPRESSION_ZLIB)
        }
        guard n > 0 || expectedSize == 0 else { return nil }
        out.removeSubrange(n...)
        return out
    }
    #endif

    struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol: [Int]
        init(symbols: Int) { symbol = [Int](repeating: 0, count: symbols) }
    }

    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
                           4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    static let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    struct Full: Error {}

    struct Decoder {
        let input: UnsafeBufferPointer<UInt8>
        let limit: Int
        var pos = 0
        var bitBuffer = 0
        var bitCount = 0
        var out: [UInt8] = []

        init(input: UnsafeBufferPointer<UInt8>, limit: Int) {
            self.input = input
            self.limit = limit
            out.reserveCapacity(min(limit, input.count * 4))
        }

        mutating func bits(_ need: Int) throws -> Int {
            var value = bitBuffer
            while bitCount < need {
                guard pos < input.count else { throw Failure.corrupt }
                value |= Int(input[pos]) << bitCount
                pos += 1
                bitCount += 8
            }
            bitBuffer = value >> need
            bitCount -= need
            return value & ((1 << need) - 1)
        }

        mutating func emit(_ b: UInt8) throws {
            out.append(b)
            if out.count >= limit { throw Full() }
        }

        mutating func run() throws -> [UInt8] {
            do {
                var last = 0
                repeat {
                    last = try bits(1)
                    switch try bits(2) {
                    case 0: try stored()
                    case 1: try fixed()
                    case 2: try dynamic()
                    default: throw Failure.corrupt
                    }
                } while last == 0
            } catch is Full {
                return out
            }
            return out
        }

        mutating func stored() throws {
            bitBuffer = 0
            bitCount = 0
            guard pos + 4 <= input.count else { throw Failure.corrupt }
            let len = Int(input[pos]) | Int(input[pos + 1]) << 8
            let nlen = Int(input[pos + 2]) | Int(input[pos + 3]) << 8
            pos += 4
            guard len == (~nlen & 0xFFFF), pos + len <= input.count else { throw Failure.corrupt }
            for i in 0..<len { try emit(input[pos + i]) }
            pos += len
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1...15 {
                code |= try bits(1)
                let count = h.count[len]
                if code - count < first { return h.symbol[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw Failure.corrupt
        }

        /// Builds a canonical Huffman table; returns < 0 for an over-subscribed set, > 0 for an incomplete one.
        static func construct(_ h: inout Huffman, _ lengths: ArraySlice<Int>) -> Int {
            for i in 0..<16 { h.count[i] = 0 }
            for l in lengths { h.count[l] += 1 }
            if h.count[0] == lengths.count { return 0 }
            var left = 1
            for len in 1...15 {
                left <<= 1
                left -= h.count[len]
                if left < 0 { return left }
            }
            var offs = [Int](repeating: 0, count: 16)
            for len in 1..<15 { offs[len + 1] = offs[len] + h.count[len] }
            for (s, l) in lengths.enumerated() where l != 0 {
                h.symbol[offs[l]] = s
                offs[l] += 1
            }
            return left
        }

        mutating func codes(_ lencode: Huffman, _ distcode: Huffman) throws {
            while true {
                var symbol = try decode(lencode)
                if symbol < 256 {
                    try emit(UInt8(symbol))
                } else if symbol == 256 {
                    return
                } else {
                    symbol -= 257
                    guard symbol < 29 else { throw Failure.corrupt }
                    let len = lengthBase[symbol] + (try bits(lengthExtra[symbol]))
                    let dsym = try decode(distcode)
                    guard dsym < 30 else { throw Failure.corrupt }
                    let dist = distBase[dsym] + (try bits(distExtra[dsym]))
                    guard dist <= out.count else { throw Failure.corrupt }
                    let from = out.count - dist
                    for i in 0..<len { try emit(out[from + i]) }
                }
            }
        }

        mutating func fixed() throws {
            var lengths = [Int](repeating: 0, count: 288)
            for s in 0..<144 { lengths[s] = 8 }
            for s in 144..<256 { lengths[s] = 9 }
            for s in 256..<280 { lengths[s] = 7 }
            for s in 280..<288 { lengths[s] = 8 }
            var lencode = Huffman(symbols: 288)
            _ = Decoder.construct(&lencode, lengths[...])
            var distcode = Huffman(symbols: 30)
            _ = Decoder.construct(&distcode, [Int](repeating: 5, count: 30)[...])
            try codes(lencode, distcode)
        }

        mutating func dynamic() throws {
            let nlen = try bits(5) + 257
            let ndist = try bits(5) + 1
            let ncode = try bits(4) + 4
            guard nlen <= 286, ndist <= 30 else { throw Failure.corrupt }
            var lengths = [Int](repeating: 0, count: 320)
            for i in 0..<ncode { lengths[order[i]] = try bits(3) }
            var lencode = Huffman(symbols: 288)
            guard Decoder.construct(&lencode, lengths[0..<19]) == 0 else { throw Failure.corrupt }
            var index = 0
            while index < nlen + ndist {
                var symbol = try decode(lencode)
                if symbol < 16 {
                    lengths[index] = symbol
                    index += 1
                } else {
                    var len = 0
                    if symbol == 16 {
                        guard index > 0 else { throw Failure.corrupt }
                        len = lengths[index - 1]
                        symbol = 3 + (try bits(2))
                    } else if symbol == 17 {
                        symbol = 3 + (try bits(3))
                    } else {
                        symbol = 11 + (try bits(7))
                    }
                    guard index + symbol <= nlen + ndist else { throw Failure.corrupt }
                    for _ in 0..<symbol {
                        lengths[index] = len
                        index += 1
                    }
                }
            }
            guard lengths[256] != 0 else { throw Failure.corrupt }
            lencode = Huffman(symbols: 288)
            let err = Decoder.construct(&lencode, lengths[0..<nlen])
            guard err >= 0, err == 0 || nlen - lencode.count[0] == 1 else { throw Failure.corrupt }
            var distcode = Huffman(symbols: 30)
            let derr = Decoder.construct(&distcode, lengths[nlen..<(nlen + ndist)])
            guard derr >= 0, derr == 0 || ndist - distcode.count[0] == 1 else { throw Failure.corrupt }
            try codes(lencode, distcode)
        }
    }
}
