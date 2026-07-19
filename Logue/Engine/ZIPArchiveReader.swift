import Compression
import Foundation
import os.log

/// Minimal ZIP archive reader. Sandbox-safe (no subprocess, no third-party
/// dependencies — uses only Foundation + Apple's `Compression` framework).
///
/// Scope: read-only random access to files inside a ZIP archive. Used by
/// `OfficeExtractor` to pull XML parts out of `.xlsx` / `.docx` / `.pptx` so
/// the agent can read attached Office documents.
///
/// Supports:
/// - DEFLATE-compressed entries (method 8) via `Compression.compression_decode_buffer`
/// - STORED entries (method 0)
/// - ZIP32 archives (file < 4 GB, < 65k entries)
///
/// Out of scope:
/// - ZIP64 (huge archives — not used by Office)
/// - Encrypted entries
/// - Other compression methods (BZIP2, LZMA, etc.)
struct ZIPArchiveReader {
    /// Lookup table from filename → (compression method, offset of compressed
    /// data, compressed size, uncompressed size). Built once when the archive
    /// is opened so subsequent reads are O(1).
    struct Entry {
        let method: UInt16
        let dataOffset: Int
        let compressedSize: Int
        let uncompressedSize: Int
    }

    private let data: Data
    private let entries: [String: Entry]
    private let logger = Logger(subsystem: AppConstants.bundleID, category: "ZIPArchiveReader")

    enum ZIPError: Error {
        case eocdNotFound
        case malformedCentralDirectory
        case entryNotFound(String)
        case unsupportedCompression(UInt16)
        case decompressionFailed
        case zip64NotSupported
    }

    /// Loads + parses the central directory. Throws if the archive is malformed
    /// or uses an unsupported feature.
    init(url: URL) throws {
        let raw = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(data: raw)
    }

    init(data: Data) throws {
        self.data = data
        entries = try Self.parseCentralDirectory(in: data)
    }

    /// File names in central-directory order. Useful for callers that need to
    /// enumerate (e.g. pptx slide files like `ppt/slides/slide1.xml`,
    /// `ppt/slides/slide2.xml`, ...).
    var fileNames: [String] {
        Array(entries.keys)
    }

    /// Returns true if the archive contains an entry with the given path.
    func contains(_ name: String) -> Bool {
        entries[name] != nil
    }

    /// Returns the decompressed bytes of the named entry, or nil if absent.
    /// Caps decompressed output at `maxBytes` so a malicious zip-bomb can't
    /// blow the heap.
    func read(_ name: String, maxBytes: Int = 32 * 1024 * 1024) throws -> Data {
        guard let entry = entries[name] else { throw ZIPError.entryNotFound(name) }

        // Defensive: clamp to maxBytes even before decompressing.
        let cappedSize = min(entry.uncompressedSize, maxBytes)
        guard cappedSize > 0 else { return Data() }

        switch entry.method {
        case 0: // stored
            let end = entry.dataOffset + entry.compressedSize
            guard end <= data.count else { throw ZIPError.malformedCentralDirectory }
            return data.subdata(in: entry.dataOffset ..< end)
        case 8: // deflate
            let compressedEnd = entry.dataOffset + entry.compressedSize
            guard compressedEnd <= data.count else { throw ZIPError.malformedCentralDirectory }
            let compressed = data.subdata(in: entry.dataOffset ..< compressedEnd)
            return try Self.deflateDecompress(compressed, expectedSize: cappedSize)
        default:
            throw ZIPError.unsupportedCompression(entry.method)
        }
    }

    /// Convenience: returns the entry as UTF-8 string. Returns nil if not UTF-8.
    func readString(_ name: String, maxBytes: Int = 32 * 1024 * 1024) throws -> String? {
        let bytes = try read(name, maxBytes: maxBytes)
        return String(data: bytes, encoding: .utf8)
    }

    // MARK: - Central directory parsing

    /// EOCD (End of Central Directory) signature: 0x06054b50 ("PK\x05\x06").
    private static let eocdSignature: UInt32 = 0x0605_4B50
    /// Central directory record signature: 0x02014b50 ("PK\x01\x02").
    private static let cdSignature: UInt32 = 0x0201_4B50
    /// Local file header signature: 0x04034b50 ("PK\x03\x04").
    private static let localSignature: UInt32 = 0x0403_4B50

    private static func parseCentralDirectory(in data: Data) throws -> [String: Entry] {
        let eocd = try findEOCD(in: data)
        let totalEntries = readUInt16(data, at: eocd + 10)
        let cdSize = readUInt32(data, at: eocd + 12)
        let cdOffset = Int(readUInt32(data, at: eocd + 16))

        // ZIP64 sentinels — bail out so we don't silently mis-read.
        if totalEntries == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            throw ZIPError.zip64NotSupported
        }

        var entries: [String: Entry] = [:]
        entries.reserveCapacity(Int(totalEntries))
        var offset = cdOffset

        for _ in 0 ..< totalEntries {
            guard offset + 46 <= data.count else { throw ZIPError.malformedCentralDirectory }
            let sig = readUInt32(data, at: offset)
            guard sig == cdSignature else { throw ZIPError.malformedCentralDirectory }

            let method = readUInt16(data, at: offset + 10)
            let compressedSize = Int(readUInt32(data, at: offset + 20))
            let uncompressedSize = Int(readUInt32(data, at: offset + 24))
            let nameLen = Int(readUInt16(data, at: offset + 28))
            let extraLen = Int(readUInt16(data, at: offset + 30))
            let commentLen = Int(readUInt16(data, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(data, at: offset + 42))

            let nameStart = offset + 46
            let nameEnd = nameStart + nameLen
            guard nameEnd <= data.count else { throw ZIPError.malformedCentralDirectory }
            let name = String(data: data.subdata(in: nameStart ..< nameEnd), encoding: .utf8) ?? ""

            // Skip the local file header to find the actual data offset.
            // Local header is at `localHeaderOffset`; data follows
            // [30-byte fixed header][filename length][extra field length].
            guard localHeaderOffset + 30 <= data.count else { throw ZIPError.malformedCentralDirectory }
            let localSig = readUInt32(data, at: localHeaderOffset)
            guard localSig == localSignature else { throw ZIPError.malformedCentralDirectory }
            let localNameLen = Int(readUInt16(data, at: localHeaderOffset + 26))
            let localExtraLen = Int(readUInt16(data, at: localHeaderOffset + 28))
            let dataOffset = localHeaderOffset + 30 + localNameLen + localExtraLen

            entries[name] = Entry(
                method: method,
                dataOffset: dataOffset,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize
            )

            offset = nameEnd + extraLen + commentLen
        }
        return entries
    }

    /// Find the EOCD by scanning backward from the end. Comment can be up to
    /// 64 KB, so we need to search the trailing 64 KB + 22 bytes (EOCD size).
    private static func findEOCD(in data: Data) throws -> Int {
        let minTrailing = 22
        guard data.count >= minTrailing else { throw ZIPError.eocdNotFound }
        let searchStart = max(0, data.count - 65557)
        // Walk forward from `searchStart` looking for the signature; the LAST
        // match is the right one (a comment can contain the signature).
        var found = -1
        var idx = searchStart
        while idx + 4 <= data.count {
            if readUInt32(data, at: idx) == eocdSignature {
                found = idx
            }
            idx += 1
        }
        guard found >= 0 else { throw ZIPError.eocdNotFound }
        return found
    }

    // MARK: - Decompression

    /// Inflates a raw DEFLATE stream using Apple's `Compression` framework
    /// with `COMPRESSION_ZLIB` (which is raw deflate, no zlib header).
    private static func deflateDecompress(_ compressed: Data, expectedSize: Int) throws -> Data {
        // Allocate output buffer at the expected uncompressed size. If the
        // archive lies and the real output is larger, we cap there — better
        // than allowing unbounded growth.
        let outCap = max(expectedSize, 1)
        let outBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outCap)
        defer { outBuffer.deallocate() }

        let written = compressed.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) -> Int in
            guard let base = rawPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                outBuffer, outCap,
                base, compressed.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written > 0 else { throw ZIPError.decompressionFailed }
        return Data(bytes: outBuffer, count: written)
    }

    // MARK: - Little-endian readers

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let lo = UInt16(data[offset])
        let hi = UInt16(data[offset + 1])
        return (hi << 8) | lo
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    }
}
