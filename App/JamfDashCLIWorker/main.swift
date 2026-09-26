import Foundation
import OSLog

// XPC Service entry point.
// NSXPCListener.service() uses the bundle ID from Info.plist as the service name and blocks
// until the service is terminated by launchd.

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let logger = Logger(subsystem: "com.jamfdash", category: "CLIWorker")

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // launchd only lets processes in the same app bundle look up an embedded service,
        // but the app is unsandboxed, so additionally require the peer to be JamfDash
        // signed by the same team as this worker.
        guard let requirement = CodeSignatureVerifier.peerRequirement(identifier: CodeSignatureVerifier.appIdentifier) else {
            logger.error("Worker is not signed with a Team ID — rejecting connection")
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: CLIWorkerXPCProtocol.self)
        connection.exportedObject = CLIWorkerService()
        connection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
