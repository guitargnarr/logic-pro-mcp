import Foundation

/// Encode any Codable value to a pretty-printed JSON string for MCP tool responses.
func encodeJSON<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "{\"error\": \"Failed to encode response\"}"
    }
    return string
}
