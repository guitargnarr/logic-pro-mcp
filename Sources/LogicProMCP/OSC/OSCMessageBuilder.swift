import Foundation

/// A single OSC argument value.
enum OSCArgument: Sendable {
    case int(Int32)
    case float(Float)
    case string(String)
    case blob(Data)

    /// OSC type tag character for this argument.
    var typeTag: Character {
        switch self {
        case .int: return "i"
        case .float: return "f"
        case .string: return "s"
        case .blob: return "b"
        }
    }
}

/// An OSC 1.0 message: address pattern + typed arguments.
struct OSCMessage: Sendable {
    let address: String
    let arguments: [OSCArgument]

    init(address: String, arguments: [OSCArgument] = []) {
        self.address = address
        self.arguments = arguments
    }

    /// Encode this message into OSC 1.0 binary format.
    func encode() -> Data {
        var data = Data()
        // Address pattern — null-terminated, padded to 4-byte boundary.
        data.append(oscString(address))
        // Type tag string: comma followed by one char per argument.
        let tags = "," + String(arguments.map(\.typeTag))
        data.append(oscString(tags))
        // Arguments.
        for arg in arguments {
            switch arg {
            case .int(let v):
                data.append(bigEndianBytes(v))
            case .float(let v):
                data.append(bigEndianBytes(v.bitPattern))
            case .string(let v):
                data.append(oscString(v))
            case .blob(let v):
                data.append(bigEndianBytes(Int32(v.count)))
                data.append(v)
                data.append(oscPadding(v.count))
            }
        }
        return data
    }

    /// Attempt to decode an OSC 1.0 message from raw data.
    static func decode(_ data: Data) -> OSCMessage? {
        var offset = 0

        guard let address = readOSCString(data, offset: &offset) else { return nil }
        guard let typeTags = readOSCString(data, offset: &offset) else { return nil }
        guard typeTags.hasPrefix(",") else { return nil }

        var arguments: [OSCArgument] = []
        for tag in typeTags.dropFirst() {
            switch tag {
            case "i":
                guard let value: Int32 = readBigEndian(data, offset: &offset) else { return nil }
                arguments.append(.int(value))
            case "f":
                guard let bits: UInt32 = readBigEndian(data, offset: &offset) else { return nil }
                arguments.append(.float(Float(bitPattern: bits)))
            case "s":
                guard let value = readOSCString(data, offset: &offset) else { return nil }
                arguments.append(.string(value))
            case "b":
                guard let size: Int32 = readBigEndian(data, offset: &offset) else { return nil }
                let count = Int(size)
                guard offset + count <= data.count else { return nil }
                let blob = data[offset..<(offset + count)]
                offset += count
                // Skip padding.
                offset += (4 - (count % 4)) % 4
                arguments.append(.blob(Data(blob)))
            default:
                // Unknown type tag — skip decoding.
                return nil
            }
        }
        return OSCMessage(address: address, arguments: arguments)
    }
}

// MARK: - Encoding Helpers

/// Null-terminate and pad a string to a 4-byte boundary.
private func oscString(_ string: String) -> Data {
    var bytes = Data(string.utf8)
    bytes.append(0) // null terminator
    bytes.append(oscPadding(bytes.count))
    return bytes
}

/// Returns zero-padding bytes needed to reach the next 4-byte boundary.
private func oscPadding(_ length: Int) -> Data {
    let remainder = length % 4
    guard remainder != 0 else { return Data() }
    return Data(repeating: 0, count: 4 - remainder)
}

private func bigEndianBytes(_ value: Int32) -> Data {
    var big = value.bigEndian
    return Data(bytes: &big, count: 4)
}

private func bigEndianBytes(_ value: UInt32) -> Data {
    var big = value.bigEndian
    return Data(bytes: &big, count: 4)
}

// MARK: - Decoding Helpers

/// Read a null-terminated, 4-byte-padded OSC string.
private func readOSCString(_ data: Data, offset: inout Int) -> String? {
    guard let nullIndex = data[offset...].firstIndex(of: 0) else { return nil }
    let stringBytes = data[offset..<nullIndex]
    guard let string = String(bytes: stringBytes, encoding: .utf8) else { return nil }
    let rawLength = nullIndex - offset + 1 // include null terminator
    offset += rawLength + ((4 - (rawLength % 4)) % 4)
    return string
}

/// Read a big-endian integer type from data.
private func readBigEndian<T: FixedWidthInteger>(_ data: Data, offset: inout Int) -> T? {
    let size = MemoryLayout<T>.size
    guard offset + size <= data.count else { return nil }
    let slice = data[offset..<(offset + size)]
    offset += size
    return slice.withUnsafeBytes { $0.loadUnaligned(as: T.self) }.bigEndian
}
