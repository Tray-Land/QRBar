/// A self-contained QR code encoder (ISO/IEC 18004, byte mode), so codes come out identical on
/// every Mac and macOS version without depending on Core Image or the GPU.
///
/// Follows the structure of Project Nayuki's reference implementation.
enum QREncoder {
    static let minVersion = 1
    static let maxVersion = 40

    /// The symbol's modules (without a quiet zone), row-major, or nil when `data` doesn't fit.
    static func encode(_ data: [UInt8], correction: QRErrorCorrection) -> (size: Int, modules: [Bool])? {
        guard let version = (minVersion...maxVersion).first(where: { dataBits(byteCount: data.count, version: $0) <= dataCodewords(version: $0, correction: correction) * 8 }) else {
            return nil
        }

        var symbol = Symbol(version: version, correction: correction)
        symbol.drawCodewords(addErrorCorrection(to: dataCodewords(for: data, version: version, correction: correction), version: version, correction: correction))
        symbol.applyBestMask()
        return (symbol.size, symbol.modules)
    }

    // MARK: - Capacity

    /// Bits needed for a single byte-mode segment: mode indicator, character count, then the bytes.
    static func dataBits(byteCount: Int, version: Int) -> Int {
        let countBits = version <= 9 ? 8 : 16
        guard byteCount < 1 << countBits else {
            return .max
        }

        return 4 + countBits + byteCount * 8
    }

    /// Modules available for data and error correction once function patterns are placed.
    static func rawDataModules(version: Int) -> Int {
        var result = (16 * version + 128) * version + 64
        if version >= 2 {
            let alignmentCount = version / 7 + 2
            result -= (25 * alignmentCount - 10) * alignmentCount - 55
            if version >= 7 {
                result -= 36
            }
        }

        return result
    }

    static func dataCodewords(version: Int, correction: QRErrorCorrection) -> Int {
        rawDataModules(version: version) / 8 - eccCodewordsPerBlock(correction)[version] * errorCorrectionBlocks(correction)[version]
    }

    // MARK: - Codewords

    private static func dataCodewords(for data: [UInt8], version: Int, correction: QRErrorCorrection) -> [UInt8] {
        let capacity = dataCodewords(version: version, correction: correction) * 8
        var bits = BitBuffer()
        bits.append(0b0100, count: 4)
        bits.append(data.count, count: version <= 9 ? 8 : 16)
        for byte in data {
            bits.append(Int(byte), count: 8)
        }

        // Terminator, then pad to a byte boundary, then alternate pad bytes until full.
        bits.append(0, count: min(4, capacity - bits.count))
        bits.append(0, count: (8 - bits.count % 8) % 8)
        var padByte = 0xEC
        while bits.count < capacity {
            bits.append(padByte, count: 8)
            padByte ^= 0xEC ^ 0x11
        }

        return bits.bytes
    }

    /// Splits data into blocks, appends Reed–Solomon codewords to each, and interleaves them.
    private static func addErrorCorrection(to data: [UInt8], version: Int, correction: QRErrorCorrection) -> [UInt8] {
        let blockCount = errorCorrectionBlocks(correction)[version]
        let eccLength = eccCodewordsPerBlock(correction)[version]
        let rawCodewords = rawDataModules(version: version) / 8
        let shortBlockCount = blockCount - rawCodewords % blockCount
        let shortBlockLength = rawCodewords / blockCount

        let divisor = reedSolomonDivisor(degree: eccLength)
        var blocks: [[UInt8]] = []
        var offset = 0
        for index in 0..<blockCount {
            let length = shortBlockLength - eccLength + (index < shortBlockCount ? 0 : 1)
            var block = Array(data[offset..<(offset + length)])
            offset += length
            let ecc = reedSolomonRemainder(block, divisor: divisor)
            if index < shortBlockCount {
                // Placeholder so every block has the same length; skipped when interleaving.
                block.append(0)
            }

            blocks.append(block + ecc)
        }

        var result: [UInt8] = []
        result.reserveCapacity(rawCodewords)
        for column in 0..<blocks[0].count {
            for (index, block) in blocks.enumerated() where column != shortBlockLength - eccLength || index >= shortBlockCount {
                result.append(block[column])
            }
        }

        return result
    }

    private static func reedSolomonDivisor(degree: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root: UInt8 = 1
        for _ in 0..<degree {
            for index in 0..<degree {
                result[index] = multiply(result[index], root)
                if index + 1 < degree {
                    result[index] ^= result[index + 1]
                }
            }

            root = multiply(root, 0x02)
        }

        return result
    }

    private static func reedSolomonRemainder(_ data: [UInt8], divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for byte in data {
            let factor = byte ^ result.removeFirst()
            result.append(0)
            for index in result.indices {
                result[index] ^= multiply(divisor[index], factor)
            }
        }

        return result
    }

    /// Multiplication in GF(2^8) modulo x^8 + x^4 + x^3 + x^2 + 1.
    private static func multiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
        var z = 0
        for bit in (0..<8).reversed() {
            z = (z << 1) ^ ((z >> 7) * 0x11D)
            z ^= ((Int(y) >> bit) & 1) * Int(x)
        }

        return UInt8(z)
    }

    // MARK: - Tables (index 0 unused)

    private static func eccCodewordsPerBlock(_ correction: QRErrorCorrection) -> [Int] {
        switch correction {
        case .low: [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
        case .medium: [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28]
        case .quartile: [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
        case .high: [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
        }
    }

    private static func errorCorrectionBlocks(_ correction: QRErrorCorrection) -> [Int] {
        switch correction {
        case .low: [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25]
        case .medium: [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49]
        case .quartile: [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68]
        case .high: [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81]
        }
    }
}

private extension QRErrorCorrection {
    /// The two format-information bits for this level.
    var formatBits: Int {
        switch self {
        case .low: 1
        case .medium: 0
        case .quartile: 3
        case .high: 2
        }
    }
}

private struct BitBuffer {
    private(set) var count = 0
    private(set) var bytes: [UInt8] = []

    mutating func append(_ value: Int, count length: Int) {
        for bit in stride(from: length - 1, through: 0, by: -1) {
            if count % 8 == 0 {
                bytes.append(0)
            }

            if (value >> bit) & 1 == 1 {
                bytes[count / 8] |= 0x80 >> (count % 8)
            }

            count += 1
        }
    }
}

/// The module grid while it's being drawn: function patterns first, then data, then the mask.
private struct Symbol {
    let version: Int
    let correction: QRErrorCorrection
    let size: Int
    private(set) var modules: [Bool]
    private var isFunction: [Bool]

    init(version: Int, correction: QRErrorCorrection) {
        self.version = version
        self.correction = correction
        size = version * 4 + 17
        modules = Array(repeating: false, count: size * size)
        isFunction = Array(repeating: false, count: size * size)
        drawFunctionPatterns()
    }

    private func isDark(_ x: Int, _ y: Int) -> Bool {
        modules[y * size + x]
    }

    private mutating func setFunction(_ x: Int, _ y: Int, _ dark: Bool) {
        modules[y * size + x] = dark
        isFunction[y * size + x] = true
    }

    // MARK: Function patterns

    private mutating func drawFunctionPatterns() {
        for index in 0..<size {
            setFunction(6, index, index % 2 == 0)
            setFunction(index, 6, index % 2 == 0)
        }

        drawFinder(x: 3, y: 3)
        drawFinder(x: size - 4, y: 3)
        drawFinder(x: 3, y: size - 4)

        let positions = alignmentPositions
        let last = positions.count - 1
        for (i, x) in positions.enumerated() {
            for (j, y) in positions.enumerated() where !(i == 0 && j == 0) && !(i == 0 && j == last) && !(i == last && j == 0) {
                drawAlignment(x: x, y: y)
            }
        }

        // Reserve the format areas now; the real bits are written once the mask is chosen.
        drawFormatBits(mask: 0)
        drawVersion()
    }

    /// A finder pattern with its light separator, clipped at the symbol's edge.
    private mutating func drawFinder(x: Int, y: Int) {
        for dy in -4...4 {
            for dx in -4...4 {
                let xx = x + dx, yy = y + dy
                guard (0..<size).contains(xx), (0..<size).contains(yy) else {
                    continue
                }

                let distance = max(abs(dx), abs(dy))
                setFunction(xx, yy, distance != 2 && distance != 4)
            }
        }
    }

    private mutating func drawAlignment(x: Int, y: Int) {
        for dy in -2...2 {
            for dx in -2...2 {
                setFunction(x + dx, y + dy, max(abs(dx), abs(dy)) != 1)
            }
        }
    }

    private var alignmentPositions: [Int] {
        guard version > 1 else {
            return []
        }

        let count = version / 7 + 2
        let step = (version * 8 + count * 3 + 5) / (count * 4 - 4) * 2
        var result = [6]
        for index in 0..<(count - 1) {
            result.insert(size - 7 - index * step, at: 1)
        }

        return result
    }

    private mutating func drawFormatBits(mask: Int) {
        let data = correction.formatBits << 3 | mask
        var remainder = data
        for _ in 0..<10 {
            remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537)
        }

        let bits = (data << 10 | remainder) ^ 0x5412
        func bit(_ index: Int) -> Bool { (bits >> index) & 1 == 1 }

        // First copy, around the top-left finder.
        for index in 0...5 {
            setFunction(8, index, bit(index))
        }

        setFunction(8, 7, bit(6))
        setFunction(8, 8, bit(7))
        setFunction(7, 8, bit(8))
        for index in 9..<15 {
            setFunction(14 - index, 8, bit(index))
        }

        // Second copy, split between the top-right and bottom-left finders.
        for index in 0..<8 {
            setFunction(size - 1 - index, 8, bit(index))
        }

        for index in 8..<15 {
            setFunction(8, size - 15 + index, bit(index))
        }

        // The dark module, always set.
        setFunction(8, size - 8, true)
    }

    private mutating func drawVersion() {
        guard version >= 7 else {
            return
        }

        var remainder = version
        for _ in 0..<12 {
            remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25)
        }

        let bits = version << 12 | remainder
        for index in 0..<18 {
            let dark = (bits >> index) & 1 == 1
            let a = size - 11 + index % 3, b = index / 3
            setFunction(a, b, dark)
            setFunction(b, a, dark)
        }
    }

    // MARK: Data and masking

    /// Places codewords in the zigzag order: two-module columns from the right, alternating up and down.
    mutating func drawCodewords(_ data: [UInt8]) {
        var bitIndex = 0
        var right = size - 1
        while right >= 1 {
            if right == 6 {
                // Skip the vertical timing pattern.
                right = 5
            }

            for vertical in 0..<size {
                for offset in 0..<2 {
                    let x = right - offset
                    let upward = (right + 1) & 2 == 0
                    let y = upward ? size - 1 - vertical : vertical
                    if !isFunction[y * size + x], bitIndex < data.count * 8 {
                        modules[y * size + x] = (data[bitIndex >> 3] >> (7 - (bitIndex & 7))) & 1 == 1
                        bitIndex += 1
                    }
                }
            }

            right -= 2
        }
    }

    /// Tries all eight masks and keeps the one the spec's penalty rules score lowest.
    mutating func applyBestMask() {
        var best = 0
        var bestPenalty = Int.max
        for mask in 0..<8 {
            applyMask(mask)
            drawFormatBits(mask: mask)
            let penalty = penaltyScore
            if penalty < bestPenalty {
                best = mask
                bestPenalty = penalty
            }

            // Masking is an XOR, so applying it again undoes it.
            applyMask(mask)
        }

        applyMask(best)
        drawFormatBits(mask: best)
    }

    private mutating func applyMask(_ mask: Int) {
        for y in 0..<size {
            for x in 0..<size where !isFunction[y * size + x] {
                let invert = switch mask {
                case 0: (x + y) % 2 == 0
                case 1: y % 2 == 0
                case 2: x % 3 == 0
                case 3: (x + y) % 3 == 0
                case 4: (x / 3 + y / 2) % 2 == 0
                case 5: x * y % 2 + x * y % 3 == 0
                case 6: (x * y % 2 + x * y % 3) % 2 == 0
                default: ((x + y) % 2 + x * y % 3) % 2 == 0
                }

                if invert {
                    modules[y * size + x].toggle()
                }
            }
        }
    }

    private var penaltyScore: Int {
        var result = 0

        // Runs of five or more same-colored modules, and finder-like patterns, in rows then columns.
        for transposed in [false, true] {
            for line in 0..<size {
                var runColor = false
                var runLength = 0
                var history = [Int](repeating: 0, count: 7)
                for position in 0..<size {
                    let dark = transposed ? isDark(line, position) : isDark(position, line)
                    if dark == runColor {
                        runLength += 1
                        if runLength == 5 {
                            result += 3
                        } else if runLength > 5 {
                            result += 1
                        }
                    } else {
                        addHistory(runLength, to: &history)
                        if !runColor {
                            result += finderPatternCount(history) * 40
                        }

                        runColor = dark
                        runLength = 1
                    }
                }

                if runColor {
                    addHistory(runLength, to: &history)
                    runLength = 0
                }

                addHistory(runLength + size, to: &history)
                result += finderPatternCount(history) * 40
            }
        }

        // 2×2 blocks of one color.
        for y in 0..<(size - 1) {
            for x in 0..<(size - 1) {
                let color = isDark(x, y)
                if color == isDark(x + 1, y), color == isDark(x, y + 1), color == isDark(x + 1, y + 1) {
                    result += 3
                }
            }
        }

        // Imbalance between dark and light, in 5% steps away from 50%.
        let dark = modules.count(where: \.self)
        let total = size * size
        result += ((abs(dark * 20 - total * 10) + total - 1) / total - 1) * 10
        return result
    }

    private func addHistory(_ runLength: Int, to history: inout [Int]) {
        // The light border before the symbol counts toward the first run.
        let length = history[0] == 0 ? runLength + size : runLength
        history.removeLast()
        history.insert(length, at: 0)
    }

    private func finderPatternCount(_ history: [Int]) -> Int {
        let n = history[1]
        let core = n > 0 && history[2] == n && history[3] == n * 3 && history[4] == n && history[5] == n
        return (core && history[0] >= n * 4 && history[6] >= n ? 1 : 0)
            + (core && history[6] >= n * 4 && history[0] >= n ? 1 : 0)
    }
}
