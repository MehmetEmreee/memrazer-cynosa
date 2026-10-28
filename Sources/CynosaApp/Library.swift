// SPDX-License-Identifier: GPL-2.0-or-later
import CynosaKit
import Foundation
import UniformTypeIdentifiers

/// Imported animations live in ~/Library/Application Support/memrazer-cynosa/GIFs.
final class GIFLibrary: ObservableObject {
    @Published private(set) var items: [String] = []
    let directory: URL

    static let types: [UTType] = [.gif, .png, .webP, .heic, .heif]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("memrazer-cynosa/GIFs", isDirectory: true)
        // Pre-1.2 builds stored the library under "Cynosa".
        let legacy = base.appendingPathComponent("Cynosa/GIFs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: legacy, to: directory)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    func url(for name: String) -> URL? {
        let u = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        items = files
            .filter { url in Self.types.contains { UTType(filenameExtension: url.pathExtension)?.conforms(to: $0) ?? false } }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a > b
            }
            .map(\.lastPathComponent)
    }

    /// Validates, copies into the library and returns the stored name.
    @discardableResult
    func add(_ source: URL) throws -> String {
        _ = try GIFAnimation(url: source)
        var name = source.lastPathComponent
        var target = directory.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            name = "\(source.deletingPathExtension().lastPathComponent) \(n).\(source.pathExtension)"
            target = directory.appendingPathComponent(name)
            n += 1
        }
        try FileManager.default.copyItem(at: source, to: target)
        reload()
        return name
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        reload()
    }
}
