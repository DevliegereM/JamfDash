import CryptoKit
import Foundation
import OSLog

// MARK: - Download Source

/// Ordered list of sources tried in sequence until one succeeds.
enum DownloadSource: Sendable {
    /// GitHub Releases API for a given `owner/repo` slug.
    case gitHubReleases(repo: String)
    /// A fully-resolved download URL with a known version string.
    case directURL(url: URL, version: String)
}

// MARK: - CLIDownloader

actor CLIDownloader {
    private let session: URLSession
    private let sources: [DownloadSource]
    private let logger = Logger(subsystem: "com.jamfdash", category: "CLIDownloader")

    init(
        session: URLSession = .shared,
        additionalSources: [DownloadSource] = []
    ) {
        self.session = session
        self.sources = [.gitHubReleases(repo: "Jamf-Concepts/jamf-cli")] + additionalSources
    }

    // MARK: - Latest version query (used by CLIManager.checkForUpdate)

    func latestVersion() async throws -> String {
        for source in sources {
            if case .gitHubReleases(let repo) = source {
                return try await fetchTagName(repo: repo, version: nil)
            }
        }
        throw CLIError.downloadFailed("No GitHub source configured")
    }

    // MARK: - List available versions

    func availableVersions(limit: Int = 10) async throws -> [String] {
        for source in sources {
            if case .gitHubReleases(let repo) = source {
                let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=\(limit)")!
                var req = URLRequest(url: url)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                let (data, _) = try await session.data(for: req)
                struct R: Decodable { let tag_name: String }
                return try JSONDecoder().decode([R].self, from: data).map { $0.tag_name }
            }
        }
        return []
    }

    // MARK: - Download latest

    /// Downloads the latest available release to `destination`.
    /// - Returns: The version tag that was installed (e.g. "v1.6.0").
    @discardableResult
    func download(to destination: URL, arch: CLIVersion.Architecture) async throws -> String {
        var lastError: Error = CLIError.downloadFailed("All download sources exhausted")
        for source in sources {
            do {
                switch source {
                case .gitHubReleases(let repo):
                    let release = try await fetchRelease(repo: repo, version: nil)
                    try await downloadRelease(release, to: destination, arch: arch)
                    return release.tag_name
                case .directURL(let url, let version):
                    try await downloadDirect(url: url, to: destination)
                    return version
                }
            } catch {
                logger.warning("Source failed: \(error.localizedDescription). Trying next source.")
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Download specific version

    /// Downloads a specific tagged release to `destination`.
    /// - Returns: The normalised version tag.
    @discardableResult
    func download(version: String, to destination: URL, arch: CLIVersion.Architecture) async throws -> String {
        for source in sources {
            if case .gitHubReleases(let repo) = source {
                let release = try await fetchRelease(repo: repo, version: version)
                try await downloadRelease(release, to: destination, arch: arch)
                return release.tag_name
            }
        }
        throw CLIError.versionNotFound(version)
    }

    // MARK: - Private: Release fetch

    private func fetchTagName(repo: String, version: String?) async throws -> String {
        let urlString = version == nil
            ? "https://api.github.com/repos/\(repo)/releases/latest"
            : "https://api.github.com/repos/\(repo)/releases/tags/\(tagify(version!))"
        var req = URLRequest(url: URL(string: urlString)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                throw CLIError.versionNotFound(version ?? "latest")
            }
            throw CLIError.downloadFailed("GitHub API returned non-200")
        }
        struct R: Decodable { let tag_name: String }
        return try JSONDecoder().decode(R.self, from: data).tag_name
    }

    private func fetchRelease(repo: String, version: String?) async throws -> ReleasePayload {
        let urlString = version == nil
            ? "https://api.github.com/repos/\(repo)/releases/latest"
            : "https://api.github.com/repos/\(repo)/releases/tags/\(tagify(version!))"
        var req = URLRequest(url: URL(string: urlString)!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                throw CLIError.versionNotFound(version ?? "latest")
            }
            throw CLIError.downloadFailed("GitHub API error fetching release")
        }
        return try JSONDecoder().decode(ReleasePayload.self, from: data)
    }

    // MARK: - Private: Download & verify

    private func downloadRelease(_ release: ReleasePayload, to destination: URL, arch: CLIVersion.Architecture) async throws {
        let assetURL = try assetURL(from: release, arch: arch)
        let expectedChecksum = try? await fetchChecksum(for: assetURL.lastPathComponent, from: release)

        logger.info("Downloading jamf-cli \(release.tag_name) from \(assetURL.absoluteString)")

        let (tempURL, _) = try await session.download(from: assetURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        if let expected = expectedChecksum {
            let actual = try sha256Hex(of: tempURL)
            guard actual.lowercased() == expected.lowercased() else {
                throw CLIError.checksumMismatch(expected: expected, actual: actual)
            }
            logger.info("SHA256 verified for jamf-cli \(release.tag_name)")
        } else {
            logger.warning("No checksum asset found for release '\(release.tag_name)' — skipping integrity check")
        }

        try extract(archive: tempURL, binaryName: "jamf-cli", to: destination)
        logger.info("jamf-cli \(release.tag_name) installed at \(destination.path)")
    }

    private func downloadDirect(url: URL, to destination: URL) async throws {
        logger.info("Downloading from direct URL: \(url.absoluteString)")
        let (tempURL, _) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try extract(archive: tempURL, binaryName: "jamf-cli", to: destination)
    }

    // MARK: - Private: Checksum

    private func fetchChecksum(for assetName: String, from release: ReleasePayload) async throws -> String? {
        let checksumAsset = release.assets.first { asset in
            let n = asset.name.lowercased()
            return n.hasSuffix("checksums.txt") || n.hasSuffix("sha256sums") ||
                   n.hasSuffix("sha256sums.txt") || n.hasSuffix(".sha256")
        }
        guard let asset = checksumAsset, let url = URL(string: asset.browser_download_url) else {
            return nil
        }
        let (data, _) = try await session.data(from: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.components(separatedBy: .newlines) {
            // Typical format: "<hash>  <filename>" or "<hash>  *<filename>"
            let parts = line.trimmingCharacters(in: .whitespaces)
                            .components(separatedBy: .whitespaces)
            guard parts.count >= 2 else { continue }
            let hash = parts[0]
            let name = parts.last?.trimmingCharacters(in: CharacterSet(charactersIn: "*")) ?? ""
            if name == assetName || name.hasSuffix("/\(assetName)") {
                return hash
            }
        }
        return nil
    }

    private func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private: Asset selection

    private func assetURL(from release: ReleasePayload, arch: CLIVersion.Architecture) throws -> URL {
        let candidates: [String]
        switch arch {
        case .arm64:
            candidates = ["darwin-universal", "darwin-arm64", "macos-universal", "macos-arm64"]
        case .x86_64:
            candidates = ["darwin-universal", "darwin-amd64", "darwin-x86_64", "macos-universal", "macos-amd64"]
        }
        for candidate in candidates {
            if let asset = release.assets.first(where: { $0.name.contains(candidate) }),
               let url = URL(string: asset.browser_download_url) { return url }
        }
        if let asset = release.assets.first(where: { $0.name.contains("darwin") || $0.name.contains("macos") }),
           let url = URL(string: asset.browser_download_url) { return url }
        throw CLIError.downloadFailed("No compatible binary in release \(release.tag_name) for \(arch.rawValue)")
    }

    // MARK: - Private: Archive extraction

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
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            p.arguments = ["-xzf", archive.path, "-C", extractDir.path]
            try p.run(); p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw CLIError.downloadFailed("tar extraction failed (code \(p.terminationStatus))")
            }
        case .zip:
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-q", archive.path, "-d", extractDir.path]
            try p.run(); p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                throw CLIError.downloadFailed("unzip failed (code \(p.terminationStatus))")
            }
        case .raw:
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: archive, to: destination)
            return
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: extractDir, includingPropertiesForKeys: nil) else {
            throw CLIError.downloadFailed("Failed to enumerate extracted archive")
        }
        var found: URL?
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == binaryName { found = fileURL; break }
        }
        guard let foundBinary = found else {
            throw CLIError.downloadFailed("'\(binaryName)' not found in archive")
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: foundBinary, to: destination)
    }

    // MARK: - Helpers

    /// Ensures version strings have a "v" prefix for GitHub tags.
    private func tagify(_ version: String) -> String {
        version.hasPrefix("v") ? version : "v\(version)"
    }
}

// MARK: - GitHub API types

private struct ReleasePayload: Decodable {
    let tag_name: String
    let assets: [ReleaseAsset]
}

private struct ReleaseAsset: Decodable {
    let name: String
    let browser_download_url: String
}
