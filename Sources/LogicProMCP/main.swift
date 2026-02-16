import Foundation

// Handle --check-permissions flag
if CommandLine.arguments.contains("--check-permissions") {
    let status = PermissionChecker.check()
    FileHandle.standardError.write(Data((status.summary + "\n").utf8))
    if status.allGranted {
        exit(0)
    } else {
        exit(1)
    }
}

// Start the MCP server
let server = LogicProServer()
do {
    try await server.start()
} catch {
    Log.error("Server failed: \(error)", subsystem: "main")
    exit(1)
}
