import Foundation

/// Channel that routes operations through CoreMIDI / MMC.
actor CoreMIDIChannel: Channel {
    let id: ChannelID = .coreMIDI
    private let engine: MIDIEngine

    init(engine: MIDIEngine) {
        self.engine = engine
    }

    func start() async throws {
        try await engine.start()
        Log.info("CoreMIDIChannel started", subsystem: "midi")
    }

    func stop() async {
        await engine.stop()
        Log.info("CoreMIDIChannel stopped", subsystem: "midi")
    }

    func execute(operation: String, params: [String: String]) async -> ChannelResult {
        switch operation {
        // MARK: - Transport (MMC)

        case "transport.play":
            await engine.sendSysEx(MMCCommands.play())
            return .success("MMC play sent")

        case "transport.stop":
            await engine.sendSysEx(MMCCommands.stop())
            return .success("MMC stop sent")

        case "transport.pause":
            await engine.sendSysEx(MMCCommands.pause())
            return .success("MMC pause sent")

        case "transport.record_strobe":
            await engine.sendSysEx(MMCCommands.recordStrobe())
            return .success("MMC record strobe sent")

        case "transport.record_exit":
            await engine.sendSysEx(MMCCommands.recordExit())
            return .success("MMC record exit sent")

        case "transport.fast_forward":
            await engine.sendSysEx(MMCCommands.fastForward())
            return .success("MMC fast forward sent")

        case "transport.rewind":
            await engine.sendSysEx(MMCCommands.rewind())
            return .success("MMC rewind sent")

        case "transport.locate":
            guard let h = params["hours"].flatMap(UInt8.init),
                  let m = params["minutes"].flatMap(UInt8.init),
                  let s = params["seconds"].flatMap(UInt8.init),
                  let f = params["frames"].flatMap(UInt8.init) else {
                return .error("locate requires hours, minutes, seconds, frames")
            }
            let sf = params["subframes"].flatMap(UInt8.init) ?? 0
            await engine.sendSysEx(MMCCommands.locate(hours: h, minutes: m, seconds: s, frames: f, subframes: sf))
            return .success("MMC locate sent to \(h):\(m):\(s):\(f).\(sf)")

        // MARK: - Note Send

        case "midi.send_note":
            guard let note = params["note"].flatMap(UInt8.init) else {
                return .error("send_note requires 'note' (0-127)")
            }
            let channel = params["channel"].flatMap(UInt8.init) ?? 0
            let velocity = params["velocity"].flatMap(UInt8.init) ?? 100
            let durationMs = params["duration_ms"].flatMap(UInt64.init) ?? 250
            await engine.sendNoteOn(channel: channel, note: note, velocity: velocity)
            try? await Task.sleep(nanoseconds: durationMs * 1_000_000)
            await engine.sendNoteOff(channel: channel, note: note)
            return .success("Note \(note) on ch \(channel) vel \(velocity) dur \(durationMs)ms")

        case "midi.send_chord":
            // Parse comma-separated notes
            guard let notesStr = params["notes"], !notesStr.isEmpty else {
                return .error("send_chord requires 'notes' (comma-separated MIDI note numbers)")
            }
            let chordNotes = notesStr.split(separator: ",").compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
            guard !chordNotes.isEmpty else {
                return .error("send_chord: no valid note numbers in '\(notesStr)'")
            }
            let chordChannel = params["channel"].flatMap(UInt8.init) ?? 0
            let chordVelocity = params["velocity"].flatMap(UInt8.init) ?? 100
            let chordDurationMs = params["duration_ms"].flatMap(UInt64.init) ?? 500
            // All notes on simultaneously
            for n in chordNotes {
                await engine.sendNoteOn(channel: chordChannel, note: n, velocity: chordVelocity)
            }
            try? await Task.sleep(nanoseconds: chordDurationMs * 1_000_000)
            // All notes off simultaneously
            for n in chordNotes {
                await engine.sendNoteOff(channel: chordChannel, note: n)
            }
            return .success("Chord [\(chordNotes.map(String.init).joined(separator: ","))] on ch \(chordChannel) vel \(chordVelocity) dur \(chordDurationMs)ms")

        case "midi.send_sequence":
            // Parse JSON-encoded sequence of timed events -- returns IMMEDIATELY, plays in background.
            // This prevents the MCP connection from timing out on long sequences.
            guard let eventsJSON = params["events"] else {
                return .error("send_sequence requires 'events' (JSON array of timed events)")
            }
            guard let eventsData = eventsJSON.data(using: .utf8),
                  let events = try? JSONSerialization.jsonObject(with: eventsData) as? [[String: Any]] else {
                return .error("send_sequence: 'events' must be a valid JSON array")
            }
            guard !events.isEmpty else {
                return .error("send_sequence: events array is empty")
            }

            let seqChannel = params["channel"].flatMap(UInt8.init) ?? 0
            let eventCount = events.count

            // Estimate total duration from events for the response message
            var estimatedDurationMs: UInt64 = 0
            for event in events {
                let timeMs = (event["time_ms"] as? Int).map(UInt64.init) ?? 0
                let dur = (event["duration_ms"] as? Int).map(UInt64.init) ?? 0
                let end = timeMs + dur
                if end > estimatedDurationMs { estimatedDurationMs = end }
            }

            // Fire and forget -- play sequence in detached task
            let engineRef = self.engine
            Task.detached {
                let sorted = events.sorted {
                    let a = ($0["time_ms"] as? Int).map(UInt64.init) ?? 0
                    let b = ($1["time_ms"] as? Int).map(UInt64.init) ?? 0
                    return a < b
                }
                var lastTimeMs: UInt64 = 0

                for event in sorted {
                    let eventType = event["type"] as? String ?? "note"
                    let timeMs = (event["time_ms"] as? Int).map(UInt64.init) ?? 0

                    if timeMs > lastTimeMs {
                        let delta = timeMs - lastTimeMs
                        try? await Task.sleep(nanoseconds: delta * 1_000_000)
                    }
                    lastTimeMs = timeMs

                    let ch = (event["channel"] as? Int).map(UInt8.init) ?? seqChannel

                    switch eventType {
                    case "note":
                        let note = UInt8(event["note"] as? Int ?? 60)
                        let vel = UInt8(event["velocity"] as? Int ?? 100)
                        let dur = UInt64(event["duration_ms"] as? Int ?? 250)
                        await engineRef.sendNoteOn(channel: ch, note: note, velocity: vel)
                        try? await Task.sleep(nanoseconds: dur * 1_000_000)
                        await engineRef.sendNoteOff(channel: ch, note: note)
                        lastTimeMs += dur

                    case "chord":
                        let notes: [Int] = event["notes"] as? [Int] ?? []
                        let vel = UInt8(event["velocity"] as? Int ?? 100)
                        let dur = UInt64(event["duration_ms"] as? Int ?? 500)
                        for n in notes {
                            await engineRef.sendNoteOn(channel: ch, note: UInt8(n), velocity: vel)
                        }
                        try? await Task.sleep(nanoseconds: dur * 1_000_000)
                        for n in notes {
                            await engineRef.sendNoteOff(channel: ch, note: UInt8(n))
                        }
                        lastTimeMs += dur

                    case "rest":
                        let dur = UInt64(event["duration_ms"] as? Int ?? 250)
                        try? await Task.sleep(nanoseconds: dur * 1_000_000)
                        lastTimeMs += dur

                    case "cc":
                        let controller = UInt8(event["controller"] as? Int ?? 0)
                        let value = UInt8(event["value"] as? Int ?? 0)
                        await engineRef.sendCC(channel: ch, controller: controller, value: value)

                    case "program_change":
                        let program = UInt8(event["program"] as? Int ?? 0)
                        await engineRef.sendProgramChange(channel: ch, program: program)

                    default:
                        Log.warn("send_sequence: unknown event type '\(eventType)', skipping", subsystem: "midi")
                    }
                }
                Log.info("Sequence playback complete: \(sorted.count) events over \(lastTimeMs)ms", subsystem: "midi")
            }

            return .success("Sequence started: \(eventCount) events, ~\(estimatedDurationMs)ms duration (playing in background)")

        case "midi.note_on":
            guard let note = params["note"].flatMap(UInt8.init) else {
                return .error("note_on requires 'note' (0-127)")
            }
            let channel = params["channel"].flatMap(UInt8.init) ?? 0
            let velocity = params["velocity"].flatMap(UInt8.init) ?? 100
            await engine.sendNoteOn(channel: channel, note: note, velocity: velocity)
            return .success("Note on \(note) ch \(channel) vel \(velocity)")

        case "midi.note_off":
            guard let note = params["note"].flatMap(UInt8.init) else {
                return .error("note_off requires 'note' (0-127)")
            }
            let channel = params["channel"].flatMap(UInt8.init) ?? 0
            await engine.sendNoteOff(channel: channel, note: note)
            return .success("Note off \(note) ch \(channel)")

        // MARK: - CC

        case "midi.send_cc":
            guard let controller = params["controller"].flatMap(UInt8.init),
                  let value = params["value"].flatMap(UInt8.init) else {
                return .error("send_cc requires 'controller' and 'value' (0-127)")
            }
            let channel = params["channel"].flatMap(UInt8.init) ?? 0
            await engine.sendCC(channel: channel, controller: controller, value: value)
            return .success("CC \(controller)=\(value) on ch \(channel)")

        // MARK: - Program Change

        case "midi.program_change":
            guard let program = params["program"].flatMap(UInt8.init) else {
                return .error("program_change requires 'program' (0-127)")
            }
            let channel = params["channel"].flatMap(UInt8.init) ?? 0
            await engine.sendProgramChange(channel: channel, program: program)
            return .success("Program change \(program) on ch \(channel)")

        // MARK: - Pitch Bend

        case "midi.pitch_bend":
            guard let value = params["value"].flatMap(UInt16.init) else {
                return .error("pitch_bend requires 'value' (0-16383, center=8192)")
            }
            let channel = params["channel"].flatMap(UInt8.init) ?? 0
            await engine.sendPitchBend(channel: channel, value: value)
            return .success("Pitch bend \(value) on ch \(channel)")

        // MARK: - Aftertouch

        case "midi.aftertouch":
            guard let pressure = params["pressure"].flatMap(UInt8.init) else {
                return .error("aftertouch requires 'pressure' (0-127)")
            }
            let channel = params["channel"].flatMap(UInt8.init) ?? 0
            await engine.sendAftertouch(channel: channel, pressure: pressure)
            return .success("Aftertouch \(pressure) on ch \(channel)")

        // MARK: - Raw SysEx

        case "midi.send_sysex":
            guard let hexString = params["bytes"] else {
                return .error("send_sysex requires 'bytes' (hex string, e.g. 'F0 7F 7F 06 02 F7')")
            }
            let bytes = hexString.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            guard bytes.first == 0xF0, bytes.last == 0xF7 else {
                return .error("SysEx must start with F0 and end with F7")
            }
            await engine.sendSysEx(bytes)
            return .success("SysEx sent (\(bytes.count) bytes)")

        default:
            return .error("Unknown CoreMIDI operation: \(operation)")
        }
    }

    func healthCheck() async -> ChannelHealth {
        let active = await engine.isActive
        if active {
            return .healthy(detail: "CoreMIDI client active, virtual ports created")
        } else {
            return .unavailable("CoreMIDI client not initialized")
        }
    }
}
