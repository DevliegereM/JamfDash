import Foundation
import OSLog

/// Downloads and updates the jamf-cli binary from GitHub Releases.
actor CLIDownloader {
    private let session: URLSession
    private let repo = "Jamf-Concepts/jamf-cli"
    private let logger = Logger(subsystem: "com.jamfdash", category: "CLIDownloader")

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Latest Version Query

    func latestVersion() async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CLIError.downloadFailed("GitHub API returned non-200 response")
        }

        struct Release: Decodable { let tag_name: String }
        let release = try JSONDecoder().decode(Release.self, from: data)
        return release.tag_name
    }

    // MARK: - Download

    func download(to destination: URL, arch: CLIVersion.Architecture) async throws {
        let releaseData = try await fetchLatestRelease()
        let downloadURL = try assetURL(from: releaseData, arch: arch)

        logger.info("Downloading jamf-cli from \(downloadURL.absoluteString)")

        let (tempURL, _) = try await session.download(from: downloadURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try extract(archive: tempURL, binaryName: "jamf-cli", to: destination)
        logger.info("jamf-cli installed at \(destination.path)")
    }

    // MARK: - Private Helpers

    private func fetchLatestRelease() async throws -> ReleasePayload {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CLIError.downloadFailed("GitHub API error fetching release")
        }
        return try JSONDecoder().decode(ReleasePayload.self, from: data)
    }

    private func assetURL(from release: ReleasePayload, arch: CLIVersion.Architecture) throws -> URL {
        // Prefer universal binary, fall back to arch-specific
        let candidates: [String]
        switch arch {
        case .arm64:
            candidates = ["darwin-universal", "darwin-arm64", "macos-universal", "macos-arm64"]
        case .x86_64:
            candidates = ["darwin-universal", "darwin-amd64", "darwin-x86_64", "macos-universal", "macos-amd64"]
        }

        for candidate in candidates {
            if let asset = release.assets.first(where: { $0.name.contains(candidate) }) {
                guard let url = URL(string: asset.browser_download_url) else { continue }
                return url
            }
        }

        // Last resort: first asset that contains "darwin" or "macos"
        if let asset = release.assets.first(where: { $0.name.contains("darwin") || $0.name.contains("macos") }),
           let url = URL(string: asset.browser_download_url) {
            return url
        }

        throw CLIError.downloadFailed("No compatible binary found in release \(release.tag_name) for arch \(arch.rawValue)")
    }

    /// Detect archive type from magic bytes — reliable regardless of temp-file naming.
    private enum ArchiveType { case tarGz, zip, raw }

    private func archiveType(at url: URL) -> ArchiveType {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .raw }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4), header.count >= 2 else { return .raw }
        if header[0] == 0x1F && header[1] == 0x8B { return .tarGz }
        if header.count >= 4 && header[0] == 0x50 && header[1] == 0x4B &&
           header[2] == 0x03 && header[3] == 0x04 { return .zip }
        return .raw
    }

    private func extract(archive: URL, binaryName: String, to destination: URL) throws {
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JamfDash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractDir) }

        switch archiveType(at: archive) {
        case .tarGz:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", archive.path, "-C", extractDir.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CLIError.downloadFailed("tar extraction failed with code \(process.terminationStatus)")
            }
        case .zip:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", archive.path, "-d", extractDir.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CLIError.downloadFailed("unzip failed with code \(process.terminationStatus)")
            }
        case .raw:
            // Treat as a bare binary — copy directly
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: archive, to: destination)
            removeQuarantine(at: destination)
            return
        }

        // Find the binary in extracted contents
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil) else {
            throw CLIError.downloadFailed("Failed to enumerate extracted archive")
        }

        var binaryURL: URL?
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == binaryName {
                binaryURL = fileURL
                break
            }
        }

        guard let foundBinary = binaryURL else {
            throw CLIError.downloadFailed("Binary '\(binaryName)' not found in archive")
        }

        // Remove existing binary if present
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        try fm.copyItem(at: foundBinary, to: destination)
        removeQuarantine(at: destination)
    }

    private func removeQuarantine(at url: URL) {
        // Remove com.apple.quarantine directly via syscall — no subprocess needed.
        // Gatekeeper blocks execution of downloaded files that still carry this attribute.
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            removexattr(path, "com.apple.quarantine", 0)
        }
    }
}

// MARK: - GitHub API Decodable

private struct ReleasePayload: Decodable {
    let tag_name: String
    let assets: [ReleaseAsset]
}

private struct ReleaseAsset: Decodable {
    let name: String
    let browser_download_url: String
}
