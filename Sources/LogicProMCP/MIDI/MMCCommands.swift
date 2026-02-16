import Foundation

/// Builds MIDI Machine Control (MMC) SysEx byte arrays.
/// Format: F0 7F <device-id> 06 <command> F7
enum MMCCommands {
    /// Play: command 0x02
    static func play(deviceID: UInt8 = ServerConfig.mmcDeviceID) -> [UInt8] {
        sysEx(deviceID: deviceID, command: 0x02)
    }

    /// Stop: command 0x01
    static func stop(deviceID: UInt8 = ServerConfig.mmcDeviceID) -> [UInt8] {
        sysEx(deviceID: deviceID, command: 0x01)
    }

    /// Record Strobe (punch-in): command 0x06
    static func recordStrobe(deviceID: UInt8 = ServerConfig.mmcDeviceID) -> [UInt8] {
        sysEx(deviceID: deviceID, command: 0x06)
    }

    /// Record Exit (punch-out): command 0x07
    static func recordExit(deviceID: UInt8 = ServerConfig.mmcDeviceID) -> [UInt8] {
        sysEx(deviceID: deviceID, command: 0x07)
    }

    /// Pause: command 0x09
    static func pause(deviceID: UInt8 = ServerConfig.mmcDeviceID) -> [UInt8] {
        sysEx(deviceID: deviceID, command: 0x09)
    }

    /// Fast Forward: command 0x04
    static func fastForward(deviceID: UInt8 = ServerConfig.mmcDeviceID) -> [UInt8] {
        sysEx(deviceID: deviceID, command: 0x04)
    }

    /// Rewind: command 0x05
    static func rewind(deviceID: UInt8 = ServerConfig.mmcDeviceID) -> [UInt8] {
        sysEx(deviceID: deviceID, command: 0x05)
    }

    /// Locate to a specific SMPTE time position.
    /// Format: F0 7F <device-id> 06 44 06 01 hh mm ss ff sf F7
    /// - Parameters:
    ///   - hours: 0-23
    ///   - minutes: 0-59
    ///   - seconds: 0-59
    ///   - frames: 0-29 (depends on frame rate)
    ///   - subframes: 0-99
    static func locate(
        hours: UInt8,
        minutes: UInt8,
        seconds: UInt8,
        frames: UInt8,
        subframes: UInt8 = 0,
        deviceID: UInt8 = ServerConfig.mmcDeviceID
    ) -> [UInt8] {
        [
            0xF0, 0x7F, deviceID, 0x06, 0x44,
            0x06, 0x01,
            hours, minutes, seconds, frames, subframes,
            0xF7,
        ]
    }

    // MARK: - Private

    private static func sysEx(deviceID: UInt8, command: UInt8) -> [UInt8] {
        [0xF0, 0x7F, deviceID, 0x06, command, 0xF7]
    }
}
