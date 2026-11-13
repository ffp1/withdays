import Foundation

/// Writes a ZIP archive (stored entries, no compression) straight to a file, entry by entry,
/// so a large deck never sits in memory whole. Enough for OOXML packages, with no dependency.
final class ZipWriter {
    private struct Entry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt32 = 0

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    func add(_ path: String, _ data: Data) throws {
        let name = Data(path.utf8)
        // Stored ZIP (no ZIP64) holds up to 4 GB.
        guard UInt64(offset) + UInt64(data.count) + UInt64(name.count) + 30 < UInt64(UInt32.max) else {
            throw Failure(message: "ファイルが大きすぎて書き出せませんでした。")
        }
        let crc = CRC32.checksum(data)
        var header = Data()
        header.append(le32: 0x0403_4B50)
        header.append(le16: 20)            // version needed
        header.append(le16: 0x0800)        // UTF-8 names
        header.append(le16: 0)             // stored
        header.append(le16: 0)             // time
        header.append(le16: 0x21)          // date (1980-01-01)
        header.append(le32: crc)
        header.append(le32: UInt32(data.count))
        header.append(le32: UInt32(data.count))
        header.append(le16: UInt16(name.count))
        header.append(le16: 0)
        header.append(name)
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: data)
        entries.append(Entry(name: name, crc: crc, size: UInt32(data.count), offset: offset))
        offset += UInt32(header.count + data.count)
    }

    func addText(_ path: String, _ text: String) throws {
        try add(path, Data(text.utf8))
    }

    func finish() throws {
        var directory = Data()
        for entry in entries {
            directory.append(le32: 0x0201_4B50)
            directory.append(le16: 20)     // made by
            directory.append(le16: 20)     // needed
            directory.append(le16: 0x0800)
            directory.append(le16: 0)
            directory.append(le16: 0)
            directory.append(le16: 0x21)
            directory.append(le32: entry.crc)
            directory.append(le32: entry.size)
            directory.append(le32: entry.size)
            directory.append(le16: UInt16(entry.name.count))
            directory.append(le16: 0)      // extra
            directory.append(le16: 0)      // comment
            directory.append(le16: 0)      // disk
            directory.append(le16: 0)      // internal attributes
            directory.append(le32: 0)      // external attributes
            directory.append(le32: entry.offset)
            directory.append(entry.name)
        }
        var end = Data()
        end.append(le32: 0x0605_4B50)
        end.append(le16: 0)
        end.append(le16: 0)
        end.append(le16: UInt16(entries.count))
        end.append(le16: UInt16(entries.count))
        end.append(le32: UInt32(directory.count))
        end.append(le32: offset)
        end.append(le16: 0)
        try handle.write(contentsOf: directory)
        try handle.write(contentsOf: end)
        try handle.close()
    }
}

/// Reads the entries of an archive written by `ZipWriter` (stored entries), for checking an export.
enum ZipReader {
    static func entries(_ data: Data) -> [String: Data] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { return [:] }
        var endIndex = bytes.count - 22
        while endIndex >= 0, readLE32(bytes, endIndex) != 0x0605_4B50 { endIndex -= 1 }
        guard endIndex >= 0 else { return [:] }
        let count = Int(readLE16(bytes, endIndex + 10))
        var position = Int(readLE32(bytes, endIndex + 16))
        var result: [String: Data] = [:]
        for _ in 0..<count {
            guard position + 46 <= bytes.count, readLE32(bytes, position) == 0x0201_4B50 else { break }
            let size = Int(readLE32(bytes, position + 20))
            let nameLength = Int(readLE16(bytes, position + 28))
            let extraLength = Int(readLE16(bytes, position + 30))
            let commentLength = Int(readLE16(bytes, position + 32))
            let local = Int(readLE32(bytes, position + 42))
            let name = String(decoding: bytes[(position + 46)..<(position + 46 + nameLength)], as: UTF8.self)
            let localName = Int(readLE16(bytes, local + 26))
            let localExtra = Int(readLE16(bytes, local + 28))
            let start = local + 30 + localName + localExtra
            if start + size <= bytes.count { result[name] = Data(bytes[start..<(start + size)]) }
            position += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    private static func readLE16(_ bytes: [UInt8], _ index: Int) -> UInt16 {
        UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
    }

    private static func readLE32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { buffer in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func append(le32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8(value >> 24))
    }
}
