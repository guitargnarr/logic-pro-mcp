import CoreMIDI
import Foundation

/// Parses inbound MIDI from Logic Pro and emits structured events.
enum MIDIFeedback {
    /// Parsed MIDI event types.
    enum Event: Sendable {
        case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
        case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
        case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
        case programChange(channel: UInt8, program: UInt8)
        case pitchBend(channel: UInt8, value: UInt16)
        case aftertouch(channel: UInt8, pressure: UInt8)
        case polyAftertouch(channel: UInt8, note: UInt8, pressure: UInt8)
        case sysEx([UInt8])
        case unknown([UInt8])
    }

    /// Parse a CoreMIDI packet list and yield events into an AsyncStream continuation.
    static func parse(packetList: MIDIPacketList, into continuation: AsyncStream<Event>.Continuation) {
        var list = packetList
        withUnsafePointer(to: &list.packet) { firstPacket in
            var packet = firstPacket
            for _ in 0..<list.numPackets {
                let p = packet.pointee
                let length = Int(p.length)
                let bytes = withUnsafeBytes(of: p.data) { raw in
                    Array(raw.prefix(length).bindMemory(to: UInt8.self))
                }
                for event in parseBytes(bytes) {
                    continuation.yield(event)
                }
                packet = UnsafePointer(MIDIPacketNext(packet))
            }
        }
    }

    /// Parse raw MIDI bytes into one or more events.
    /// Handles running status and SysEx spanning.
    static func parseBytes(_ bytes: [UInt8]) -> [Event] {
        var events: [Event] = []
        var i = 0

        while i < bytes.count {
            let byte = bytes[i]

            // SysEx start
            if byte == 0xF0 {
                // Find F7 end.
                if let endIndex = bytes[i...].firstIndex(of: 0xF7) {
                    let sysex = Array(bytes[i...endIndex])
                    events.append(.sysEx(sysex))
                    i = endIndex + 1
                } else {
                    // Incomplete SysEx — emit what we have.
                    events.append(.sysEx(Array(bytes[i...])))
                    break
                }
                continue
            }

            // Channel voice messages.
            guard byte & 0x80 != 0 else {
                // Data byte without a status — skip.
                i += 1
                continue
            }

            let status = byte & 0xF0
            let channel = byte & 0x0F

            switch status {
            case 0x90:
                guard i + 2 < bytes.count else { break }
                let note = bytes[i + 1] & 0x7F
                let vel = bytes[i + 2] & 0x7F
                if vel == 0 {
                    events.append(.noteOff(channel: channel, note: note, velocity: 0))
                } else {
                    events.append(.noteOn(channel: channel, note: note, velocity: vel))
                }
                i += 3
                continue
            case 0x80:
                guard i + 2 < bytes.count else { break }
                events.append(.noteOff(channel: channel, note: bytes[i + 1] & 0x7F, velocity: bytes[i + 2] & 0x7F))
                i += 3
                continue
            case 0xB0:
                guard i + 2 < bytes.count else { break }
                events.append(.controlChange(channel: channel, controller: bytes[i + 1] & 0x7F, value: bytes[i + 2] & 0x7F))
                i += 3
                continue
            case 0xC0:
                guard i + 1 < bytes.count else { break }
                events.append(.programChange(channel: channel, program: bytes[i + 1] & 0x7F))
                i += 2
                continue
            case 0xE0:
                guard i + 2 < bytes.count else { break }
                let lsb = UInt16(bytes[i + 1] & 0x7F)
                let msb = UInt16(bytes[i + 2] & 0x7F)
                events.append(.pitchBend(channel: channel, value: (msb << 7) | lsb))
                i += 3
                continue
            case 0xD0:
                guard i + 1 < bytes.count else { break }
                events.append(.aftertouch(channel: channel, pressure: bytes[i + 1] & 0x7F))
                i += 2
                continue
            case 0xA0:
                guard i + 2 < bytes.count else { break }
                events.append(.polyAftertouch(channel: channel, note: bytes[i + 1] & 0x7F, pressure: bytes[i + 2] & 0x7F))
                i += 3
                continue
            default:
                break
            }

            // Unknown or incomplete — skip this byte.
            i += 1
        }

        return events
    }
}
