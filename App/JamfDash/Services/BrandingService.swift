import Foundation
import AppKit

enum BrandingService {
    private static var brandingDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JamfDash/branding", isDirectory: true)
    }

    static var logoURL: URL? {
        let url = brandingDirectory.appendingPathComponent("logo.png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static var logoImage: NSImage? {
        guard let url = logoURL else { return nil }
        return NSImage(contentsOf: url)
    }

    static func saveLogo(from source: URL) throws {
        let dir = brandingDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let destination = dir.appendingPathComponent("logo.png")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        // Convert to PNG if needed
        if let image = NSImage(contentsOf: source),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try pngData.write(to: destination)
        } else {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    static func removeLogo() throws {
        guard let url = logoURL else { return }
        try FileManager.default.removeItem(at: url)
    }
}
