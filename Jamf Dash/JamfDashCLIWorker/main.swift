import Foundation
import Security

// XPC Service entry point.
// NSXPCListener.service() uses the bundle ID from Info.plist as the service name and blocks
// until the service is terminated by launchd.

final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // The OS enforces XPC service bundle locality, ensuring only processes within
        // the same app bundle can connect to this embedded XPC service.
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
