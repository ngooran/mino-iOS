//
//  WorkbookSplitter.swift
//  Mino
//
//  The system renderer shows one sheet of an Excel workbook at a time, and
//  only the first can be reached from a web view. To convert every sheet,
//  Mino makes copies of the workbook in which all sheets but one are marked
//  hidden, and converts each copy. Nothing else in the file is changed.
//
//  .xlsx is a ZIP archive: the "state" attribute of the sheets in
//  xl/workbook.xml is edited. .xls is a compound file: the visibility byte
//  of each BOUNDSHEET record in the Workbook stream is patched.
//

import Foundation
import zlib

nonisolated enum WorkbookSplitter {

    enum SplitError: Error {
        /// The file isn't a workbook this code can read (encrypted, damaged, or an unusual variant).
        case unsupported
    }

    /// Indices of the worksheets that are visible in the workbook, in tab
    /// order. Nil when the file can't be read; the caller then converts what
    /// the renderer shows by itself.
    static func visibleSheets(in url: URL) -> [Int]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        if isZip(data) {
            return (try? XLSX(data: data))?.visibleSheets
        }
        if isCompoundFile(data) {
            return (try? XLS(data: data))?.visibleSheets
        }
        return nil
    }

    /// Writes a copy of the workbook in which only the sheet at `index`
    /// (an index from `visibleSheets`) is visible.
    static func writeCopy(of url: URL, showingOnly index: Int, to destination: URL) throws {
        let data = try Data(contentsOf: url)
        let result: Data
        if isZip(data) {
            result = try XLSX(data: data).copy(showingOnly: index)
        } else if isCompoundFile(data) {
            result = try XLS(data: data).copy(showingOnly: index)
        } else {
            throw SplitError.unsupported
        }
        try result.write(to: destination, options: .atomic)
    }

    private static func isZip(_ data: Data) -> Bool {
        data.count > 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
    }

    private static func isCompoundFile(_ data: Data) -> Bool {
        let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        return data.count > 512 && Array(data.prefix(8)) == magic
    }
}

// MARK: - Reading little-endian numbers

private nonisolated extension Data {
    func u16(_ offset: Int) -> Int {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return Int(self[startIndex + offset]) | Int(self[startIndex + offset + 1]) << 8
    }

    func u32(_ offset: Int) -> Int {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return u16(offset) | u16(offset + 2) << 16
    }

    mutating func appendU16(_ value: Int) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendU32(_ value: Int) {
        appendU16(value & 0xFFFF)
        appendU16((value >> 16) & 0xFFFF)
    }
}

// MARK: - .xlsx

private nonisolated struct XLSX {

    private struct Entry {
        var name: Data
        var flags: Int
        var method: Int
        var time: Int
        var date: Int
        var crc: Int
        var compressedSize: Int
        var uncompressedSize: Int
        var externalAttributes: Int
        /// Where the entry's compressed bytes start in the source archive.
        var dataOffset: Int
    }

    private let data: Data
    private var entries: [Entry] = []
    private var workbookIndex = -1
    private var workbookXML = ""
    /// The `<sheet ...>` tags of xl/workbook.xml, in tab order.
    private var sheetTags: [String] = []

    /// Positions in `sheetTags` of the sheets that are not hidden.
    private(set) var visibleSheets: [Int] = []

    init(data: Data) throws {
        self.data = data
        try readDirectory()
        guard workbookIndex >= 0 else { throw WorkbookSplitter.SplitError.unsupported }
        let raw = try contents(of: entries[workbookIndex])
        guard let xml = String(data: raw, encoding: .utf8) else { throw WorkbookSplitter.SplitError.unsupported }
        workbookXML = xml

        // <sheet .../> or <x:sheet .../>, but not <sheets> or <sheetView>.
        let pattern = try NSRegularExpression(pattern: "<(?:[A-Za-z0-9]+:)?sheet\\s[^>]*>")
        let range = NSRange(xml.startIndex..., in: xml)
        sheetTags = pattern.matches(in: xml, range: range).compactMap { Range($0.range, in: xml).map { String(xml[$0]) } }
        guard !sheetTags.isEmpty else { throw WorkbookSplitter.SplitError.unsupported }
        visibleSheets = sheetTags.indices.filter { !sheetTags[$0].contains("state=\"hidden\"") && !sheetTags[$0].contains("state=\"veryHidden\"") }
    }

    func copy(showingOnly index: Int) throws -> Data {
        guard sheetTags.indices.contains(index) else { throw WorkbookSplitter.SplitError.unsupported }
        var xml = workbookXML
        for (position, tag) in sheetTags.enumerated() {
            var changed = tag
                .replacingOccurrences(of: " state=\"hidden\"", with: "")
                .replacingOccurrences(of: " state=\"veryHidden\"", with: "")
                .replacingOccurrences(of: " state=\"visible\"", with: "")
            if position != index, let space = changed.firstIndex(of: " ") {
                changed.insert(contentsOf: " state=\"hidden\"", at: space)
            }
            if changed != tag {
                xml = xml.replacingOccurrences(of: tag, with: changed)
            }
        }
        // The workbook opens on the sheet that is left.
        if let pattern = try? NSRegularExpression(pattern: "activeTab=\"\\d+\"") {
            xml = pattern.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: "activeTab=\"\(index)\"")
        }
        return try rewrite(replacing: workbookIndex, with: Data(xml.utf8))
    }

    // MARK: ZIP

    private mutating func readDirectory() throws {
        // The end-of-central-directory record is at the end, before an optional comment.
        var end = -1
        var offset = data.count - 22
        let limit = max(0, data.count - 22 - 65_535)
        while offset >= limit {
            if data.u32(offset) == 0x0605_4B50 {
                end = offset
                break
            }
            offset -= 1
        }
        guard end >= 0 else { throw WorkbookSplitter.SplitError.unsupported }
        let count = data.u16(end + 10)
        var position = data.u32(end + 16)
        guard count > 0, count < 0xFFFF, position < data.count else { throw WorkbookSplitter.SplitError.unsupported }

        for _ in 0..<count {
            guard data.u32(position) == 0x0201_4B50 else { throw WorkbookSplitter.SplitError.unsupported }
            let nameLength = data.u16(position + 28)
            let extraLength = data.u16(position + 30)
            let commentLength = data.u16(position + 32)
            let localOffset = data.u32(position + 42)
            let compressedSize = data.u32(position + 20)
            let uncompressedSize = data.u32(position + 24)
            // ZIP64 archives and encrypted entries are left alone.
            guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF, localOffset != 0xFFFF_FFFF,
                  data.u16(position + 8) & 1 == 0,
                  data.u32(localOffset) == 0x0403_4B50 else { throw WorkbookSplitter.SplitError.unsupported }
            let name = data.subdata(in: (position + 46)..<(position + 46 + nameLength))
            let dataOffset = localOffset + 30 + data.u16(localOffset + 26) + data.u16(localOffset + 28)
            guard dataOffset + compressedSize <= data.count else { throw WorkbookSplitter.SplitError.unsupported }
            entries.append(Entry(
                name: name,
                flags: data.u16(position + 8),
                method: data.u16(position + 10),
                time: data.u16(position + 12),
                date: data.u16(position + 14),
                crc: data.u32(position + 16),
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                externalAttributes: data.u32(position + 38),
                dataOffset: dataOffset
            ))
            if String(data: name, encoding: .utf8)?.lowercased() == "xl/workbook.xml" {
                workbookIndex = entries.count - 1
            }
            position += 46 + nameLength + extraLength + commentLength
        }
    }

    private func contents(of entry: Entry) throws -> Data {
        let compressed = data.subdata(in: entry.dataOffset..<(entry.dataOffset + entry.compressedSize))
        switch entry.method {
        case 0:
            return compressed
        case 8:
            guard entry.uncompressedSize < 64 * 1024 * 1024 else { throw WorkbookSplitter.SplitError.unsupported }
            return try inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw WorkbookSplitter.SplitError.unsupported
        }
    }

    /// Raw deflate, as stored in ZIP archives.
    private func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw WorkbookSplitter.SplitError.unsupported
        }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(expectedSize, 1))
        let status: Int32 = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { target in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = target.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(target.count)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == expectedSize else {
            throw WorkbookSplitter.SplitError.unsupported
        }
        return output.prefix(expectedSize)
    }

    /// Writes the archive again. Every entry keeps its compressed bytes,
    /// except the one at `index`, which is stored uncompressed with new content.
    private func rewrite(replacing index: Int, with content: Data) throws -> Data {
        var output = Data(capacity: data.count + content.count)
        var directory = Data()

        for (position, entry) in entries.enumerated() {
            var entry = entry
            let body: Data
            if position == index {
                body = content
                entry.method = 0
                entry.compressedSize = content.count
                entry.uncompressedSize = content.count
                entry.crc = content.withUnsafeBytes { Int(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(content.count))) }
            } else {
                body = data.subdata(in: entry.dataOffset..<(entry.dataOffset + entry.compressedSize))
            }
            // Sizes are written in the header, so no data descriptor follows.
            let flags = entry.flags & ~0x0008
            let localOffset = output.count

            output.appendU32(0x0403_4B50)
            output.appendU16(20)
            output.appendU16(flags)
            output.appendU16(entry.method)
            output.appendU16(entry.time)
            output.appendU16(entry.date)
            output.appendU32(entry.crc)
            output.appendU32(entry.compressedSize)
            output.appendU32(entry.uncompressedSize)
            output.appendU16(entry.name.count)
            output.appendU16(0)
            output.append(entry.name)
            output.append(body)

            directory.appendU32(0x0201_4B50)
            directory.appendU16(20)
            directory.appendU16(20)
            directory.appendU16(flags)
            directory.appendU16(entry.method)
            directory.appendU16(entry.time)
            directory.appendU16(entry.date)
            directory.appendU32(entry.crc)
            directory.appendU32(entry.compressedSize)
            directory.appendU32(entry.uncompressedSize)
            directory.appendU16(entry.name.count)
            directory.appendU16(0)
            directory.appendU16(0)
            directory.appendU16(0)
            directory.appendU16(0)
            directory.appendU32(entry.externalAttributes)
            directory.appendU32(localOffset)
            directory.append(entry.name)
        }

        let directoryOffset = output.count
        output.append(directory)
        output.appendU32(0x0605_4B50)
        output.appendU16(0)
        output.appendU16(0)
        output.appendU16(entries.count)
        output.appendU16(entries.count)
        output.appendU32(directory.count)
        output.appendU32(directoryOffset)
        output.appendU16(0)
        return output
    }
}

// MARK: - .xls

private nonisolated struct XLS {

    private let data: Data
    private let sectorSize: Int
    /// File offsets of the sectors that hold the Workbook stream, in order.
    private var sectors: [Int] = []
    private var streamSize = 0

    /// File offset of each sheet's visibility byte, and whether it is a worksheet.
    private var sheets: [(offset: Int, isWorksheet: Bool, hidden: Bool)] = []
    /// File offsets of the two "selected tab" fields of the WINDOW1 record.
    private var windowTabOffsets: [Int] = []

    private(set) var visibleSheets: [Int] = []

    init(data: Data) throws {
        self.data = data
        let shift = data.u16(30)
        guard shift == 9 || shift == 12 else { throw WorkbookSplitter.SplitError.unsupported }
        sectorSize = 1 << shift
        try locateWorkbookStream()
        try readGlobals()
        visibleSheets = sheets.indices.filter { sheets[$0].isWorksheet && !sheets[$0].hidden }
    }

    func copy(showingOnly index: Int) throws -> Data {
        guard sheets.indices.contains(index) else { throw WorkbookSplitter.SplitError.unsupported }
        var copy = data
        for (position, sheet) in sheets.enumerated() {
            // The low two bits are the visibility: 0 visible, 1 hidden.
            let byte = copy[copy.startIndex + sheet.offset]
            copy[copy.startIndex + sheet.offset] = (byte & 0xFC) | (position == index ? 0 : 1)
        }
        for offset in windowTabOffsets {
            copy[copy.startIndex + offset] = UInt8(index & 0xFF)
            copy[copy.startIndex + offset + 1] = UInt8((index >> 8) & 0xFF)
        }
        return copy
    }

    // MARK: Compound file

    private func sectorOffset(_ sector: Int) -> Int {
        (sector + 1) * sectorSize
    }

    /// Follows a chain in the file allocation table.
    private func chain(from start: Int, fat: [Int]) throws -> [Int] {
        var result: [Int] = []
        var sector = start
        while sector >= 0, sector < fat.count, sector != 0xFFFF_FFFE {
            result.append(sector)
            // A loop in a damaged file would never end.
            guard result.count <= fat.count else { throw WorkbookSplitter.SplitError.unsupported }
            sector = fat[sector]
        }
        return result
    }

    private mutating func locateWorkbookStream() throws {
        let entriesPerSector = sectorSize / 4

        // The DIFAT lists the sectors that hold the FAT: 109 in the header, more in a chain.
        var fatSectors: [Int] = (0..<109).map { data.u32(76 + $0 * 4) }.filter { $0 < 0xFFFF_FFFA }
        var difat = data.u32(68)
        var guardCount = 0
        while difat < 0xFFFF_FFFA, guardCount < 4096 {
            let offset = sectorOffset(difat)
            guard offset + sectorSize <= data.count else { throw WorkbookSplitter.SplitError.unsupported }
            for index in 0..<(entriesPerSector - 1) {
                let sector = data.u32(offset + index * 4)
                if sector < 0xFFFF_FFFA { fatSectors.append(sector) }
            }
            difat = data.u32(offset + (entriesPerSector - 1) * 4)
            guardCount += 1
        }

        var fat: [Int] = []
        fat.reserveCapacity(fatSectors.count * entriesPerSector)
        for sector in fatSectors {
            let offset = sectorOffset(sector)
            guard offset + sectorSize <= data.count else { throw WorkbookSplitter.SplitError.unsupported }
            for index in 0..<entriesPerSector {
                fat.append(data.u32(offset + index * 4))
            }
        }

        // The directory: 128-byte entries with a UTF-16 name.
        let miniCutoff = data.u32(56)
        for sector in try chain(from: data.u32(48), fat: fat) {
            let base = sectorOffset(sector)
            guard base + sectorSize <= data.count else { throw WorkbookSplitter.SplitError.unsupported }
            for entry in 0..<(sectorSize / 128) {
                let offset = base + entry * 128
                let nameLength = data.u16(offset + 64)
                guard nameLength >= 2, nameLength <= 64, data[data.startIndex + offset + 66] == 2 else { continue }
                let nameData = data.subdata(in: offset..<(offset + nameLength - 2))
                let name = String(data: nameData, encoding: .utf16LittleEndian)?.lowercased() ?? ""
                guard name == "workbook" || name == "book" else { continue }
                let size = data.u32(offset + 120)
                // Small streams live in the mini stream; workbooks are larger in practice.
                guard size >= miniCutoff else { throw WorkbookSplitter.SplitError.unsupported }
                streamSize = size
                sectors = try chain(from: data.u32(offset + 116), fat: fat).map(sectorOffset)
                guard sectors.count * sectorSize >= size, (sectors.last ?? 0) + sectorSize <= data.count + sectorSize else {
                    throw WorkbookSplitter.SplitError.unsupported
                }
                return
            }
        }
        throw WorkbookSplitter.SplitError.unsupported
    }

    /// File offset of a byte of the Workbook stream.
    private func fileOffset(_ streamOffset: Int) throws -> Int {
        let sector = streamOffset / sectorSize
        guard streamOffset >= 0, streamOffset < streamSize, sector < sectors.count else {
            throw WorkbookSplitter.SplitError.unsupported
        }
        let offset = sectors[sector] + streamOffset % sectorSize
        guard offset < data.count else { throw WorkbookSplitter.SplitError.unsupported }
        return offset
    }

    private func streamU16(_ streamOffset: Int) throws -> Int {
        let low = try fileOffset(streamOffset)
        let high = try fileOffset(streamOffset + 1)
        return Int(data[data.startIndex + low]) | Int(data[data.startIndex + high]) << 8
    }

    // MARK: BIFF records

    /// Walks the workbook globals: the records before the first EOF.
    private mutating func readGlobals() throws {
        var position = 0
        guard try streamU16(0) == 0x0809 else { throw WorkbookSplitter.SplitError.unsupported }
        var records = 0
        while position + 4 <= streamSize, records < 200_000 {
            let identifier = try streamU16(position)
            let length = try streamU16(position + 2)
            switch identifier {
            case 0x002F:
                // FILEPASS: the workbook is encrypted.
                throw WorkbookSplitter.SplitError.unsupported
            case 0x0085 where length >= 6:
                // BOUNDSHEET: position (4 bytes), visibility, sheet type, name.
                let visibility = try fileOffset(position + 8)
                let type = data[data.startIndex + (try fileOffset(position + 9))]
                let hidden = data[data.startIndex + visibility] & 0x03 != 0
                sheets.append((visibility, type == 0, hidden))
            case 0x003D where length >= 14:
                // WINDOW1: the selected tab and the first displayed tab.
                for field in [10, 12] {
                    let low = try fileOffset(position + 4 + field)
                    // Both bytes must be in one sector to be patched as a pair.
                    if (try fileOffset(position + 4 + field + 1)) == low + 1 {
                        windowTabOffsets.append(low)
                    }
                }
            case 0x000A:
                guard !sheets.isEmpty else { throw WorkbookSplitter.SplitError.unsupported }
                return
            default:
                break
            }
            position += 4 + length
            records += 1
        }
        throw WorkbookSplitter.SplitError.unsupported
    }
}
