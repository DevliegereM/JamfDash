import Foundation
import Security

/// Verifies that a jamf-cli binary is the genuine, Developer ID–signed build from JAMF Software.
///
/// The SHA-256 check in `CLIDownloader` only proves the download matches the checksum file
/// published in the same GitHub release; it says nothing about who produced it. The code
/// signature ties the binary to Jamf's Apple-issued Developer ID.
enum CodeSignatureVerifier {
    /// JAMF Software's Apple Developer Team ID.
    static let jamfTeamID = "483DWKW443"
    /// Signing identifier of jamf-cli builds.
    static let jamfCLIIdentifier = "com.jamf.concepts.jamf-cli"

    /// Apple-anchored Developer ID Application certificate issued to Jamf, for jamf-cli.
    static let jamfCLIRequirement =
        "anchor apple generic" +
        " and identifier \"\(jamfCLIIdentifier)\"" +
        " and certificate 1[field.1.2.840.113635.100.6.2.6] exists" +   // Developer ID CA
        " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" + // Developer ID Application
        " and certificate leaf[subject.OU] = \"\(jamfTeamID)\""

    /// Throws `CLIError.untrustedBinary` unless the file at `url` satisfies `jamfCLIRequirement`.
    static func verifyJamfCLI(at url: URL) throws {
        try verify(at: url, requirement: jamfCLIRequirement)
    }

    /// Checks the running process `pid` — the code the kernel actually loaded — against
    /// `jamfCLIRequirement`. Run before anything is sent to the process, so a binary
    /// replaced between the file check and the launch never receives input.
    static func verifyRunningJamfCLI(pid: pid_t) throws {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        var status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        guard status == errSecSuccess, let code else {
            throw CLIError.untrustedBinary(message(for: status, fallback: "cannot read the running jamf-cli"))
        }
        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(jamfCLIRequirement as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else {
            throw CLIError.untrustedBinary(message(for: status, fallback: "invalid signing requirement"))
        }
        status = SecCodeCheckValidity(code, [], requirement)
        guard status == errSecSuccess else {
            throw CLIError.untrustedBinary(message(for: status, fallback: "the running jamf-cli isn't signed by Jamf"))
        }
    }

    static func verify(at url: URL, requirement requirementText: String) throws {
        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            throw CLIError.untrustedBinary(message(for: status, fallback: "cannot read code signature"))
        }

        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
        guard status == errSecSuccess, let requirement else {
            throw CLIError.untrustedBinary(message(for: status, fallback: "invalid signing requirement"))
        }

        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        var cfError: Unmanaged<CFError>?
        status = SecStaticCodeCheckValidityWithErrors(code, flags, requirement, &cfError)
        guard status == errSecSuccess else {
            let detail = cfError?.takeRetainedValue().localizedDescription
            throw CLIError.untrustedBinary(detail ?? message(for: status, fallback: "signature is not valid"))
        }
    }

    // MARK: - App ↔ XPC worker peer validation

    /// Bundle identifier of the embedded CLI worker XPC service (also its XPC service name).
    static let workerIdentifier = "be.devliegere.JamfDash.CLIWorker"
    /// Bundle identifier of the host app allowed to talk to the worker.
    static let appIdentifier = "be.devliegere.JamfDash"

    /// Team ID the current process is signed with, or nil for ad-hoc / unsigned builds.
    static func currentTeamIdentifier() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Requirement for an XPC peer: the given identifier, signed by the same team as this process.
    ///
    /// Ad-hoc signed development builds have no team; Debug builds then fall back to an
    /// identifier-only check so the worker still runs locally, Release builds refuse.
    static func peerRequirement(identifier: String) -> String? {
        if let team = currentTeamIdentifier() {
            return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
        }
        #if DEBUG
        return "identifier \"\(identifier)\""
        #else
        return nil
        #endif
    }

    private static func message(for status: OSStatus, fallback: String) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "\(fallback) (OSStatus \(status))"
    }
}

/// `CLIExecuting` decorator that refuses to run a binary that fails `CodeSignatureVerifier`.
///
/// Verification hashes the whole binary, so the result is cached per file identity
/// (inode, size, modification date) and redone only when the file changes on disk —
/// e.g. after an update, rollback or tampering.
actor VerifyingCLIExecutor: CLIExecuting {
    private let base: any CLIExecuting
    private let verify: @Sendable (URL) throws -> Void
    private var verified: [String: FileStamp] = [:]

    private struct FileStamp: Equatable {
        let inode: UInt64
        let size: UInt64
        let modified: Date
    }

    init(
        wrapping base: any CLIExecuting,
        verify: @escaping @Sendable (URL) throws -> Void = CodeSignatureVerifier.verifyJamfCLI(at:)
    ) {
        self.base = base
        self.verify = verify
    }

    func execute(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        stdinData: Data?,
        timeout: TimeInterval
    ) async throws -> Data {
        try ensureTrusted(binary)
        return try await base.execute(
            binary: binary, arguments: arguments, environment: environment,
            stdinData: stdinData, timeout: timeout
        )
    }

    func executeScripted(
        binary: URL,
        arguments: [String],
        environment: [String: String],
        rules: [PromptRule],
        timeout: TimeInterval
    ) async throws -> Data {
        try ensureTrusted(binary)
        return try await base.executeScripted(
            binary: binary, arguments: arguments, environment: environment,
            rules: rules, timeout: timeout
        )
    }

    private func ensureTrusted(_ binary: URL) throws {
        let path = binary.resolvingSymlinksInPath().path
        let stamp = Self.stamp(ofFileAt: path)
        if let stamp, verified[path] == stamp { return }
        verified[path] = nil
        try verify(binary)
        if let stamp { verified[path] = stamp }
    }

    private static func stamp(ofFileAt path: String) -> FileStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let modified = attrs[.modificationDate] as? Date
        else { return nil }
        return FileStamp(inode: inode, size: size, modified: modified)
    }
}
