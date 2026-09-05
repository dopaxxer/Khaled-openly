import Foundation
// Legacy entry point uses the same artwork and sizes as CI.
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["python3", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("generate_icons.py").path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
