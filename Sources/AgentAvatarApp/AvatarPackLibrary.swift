import AgentAvatarCore
import Foundation

struct InstalledAvatarPack: Equatable, Sendable {
    let directory: URL
    let validation: AvatarPackValidation

    var id: String { validation.manifest.id }
    var name: String { validation.manifest.name }
    var isCertified: Bool { validation.isCertified }

    func state(_ id: AvatarStateID) -> AvatarPackManifest.State? {
        validation.manifest.states.first { $0.id == id }
    }
}

enum AvatarPackLibraryError: LocalizedError {
    case archiveTooLarge
    case extractedPackTooLarge
    case unsafeArchiveEntry(String)
    case duplicatePack(String)
    case cannotDeleteSelectedPack

    var errorDescription: String? {
        switch self {
        case .archiveTooLarge: "The avatar pack archive exceeds 200 MB"
        case .extractedPackTooLarge: "The expanded avatar pack exceeds 500 MB"
        case let .unsafeArchiveEntry(path): "The avatar pack contains an unsafe link or path: \(path)"
        case let .duplicatePack(id): "The avatar pack already exists: \(id)"
        case .cannotDeleteSelectedPack: "Switch to another avatar pack before deleting this one"
        }
    }
}

@MainActor
final class AvatarPackLibrary {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let selectedKey = "selectedAvatarPackID"
    private(set) var packs: [InstalledAvatarPack] = []

    convenience init() throws {
        try self.init(fileManager: .default)
    }

    init(fileManager: FileManager) throws {
        self.fileManager = fileManager
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        rootDirectory = applicationSupport
            .appendingPathComponent("Joyride", isDirectory: true)
            .appendingPathComponent("Packs", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try reload()
    }

    var selectedPack: InstalledAvatarPack? {
        let selectedID = UserDefaults.standard.string(forKey: selectedKey)
        return packs.first { $0.id == selectedID } ?? packs.first
    }

    func installBundledPackIfNeeded(from directory: URL) throws {
        let validation = try AvatarPackValidator.validate(directory: directory)
        let destination = rootDirectory.appendingPathComponent(validation.manifest.id, isDirectory: true)
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: directory, to: destination)
        }
        try reload()
        if UserDefaults.standard.string(forKey: selectedKey) == nil {
            UserDefaults.standard.set(validation.manifest.id, forKey: selectedKey)
        }
    }

    @discardableResult
    func importArchive(at archiveURL: URL) throws -> InstalledAvatarPack {
        let values = try archiveURL.resourceValues(forKeys: [.fileSizeKey])
        if (values.fileSize ?? 0) > 200 * 1_024 * 1_024 {
            throw AvatarPackLibraryError.archiveTooLarge
        }

        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("agent-avatar-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, staging.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "unknown archive error"
            throw AvatarPackValidationError.malformedManifest(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        try validateExtractedTree(staging)
        let packRoot = try locatePackRoot(in: staging)
        let validation = try AvatarPackValidator.validate(directory: packRoot)
        let destination = rootDirectory.appendingPathComponent(validation.manifest.id, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw AvatarPackLibraryError.duplicatePack(validation.manifest.id)
        }
        try fileManager.copyItem(at: packRoot, to: destination)
        try reload()
        return packs.first { $0.id == validation.manifest.id }!
    }

    func select(id: String) throws -> InstalledAvatarPack {
        guard let pack = packs.first(where: { $0.id == id }) else {
            throw AvatarPackValidationError.malformedManifest("Avatar pack not found: \(id)")
        }
        UserDefaults.standard.set(id, forKey: selectedKey)
        return pack
    }

    func delete(id: String) throws {
        if selectedPack?.id == id {
            throw AvatarPackLibraryError.cannotDeleteSelectedPack
        }
        guard let pack = packs.first(where: { $0.id == id }) else { return }
        try fileManager.trashItem(at: pack.directory, resultingItemURL: nil)
        try reload()
    }

    @discardableResult
    func installGeneratedPack(from directory: URL) throws -> InstalledAvatarPack {
        let validation = try AvatarPackValidator.validate(directory: directory)
        let destination = rootDirectory.appendingPathComponent(validation.manifest.id, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw AvatarPackLibraryError.duplicatePack(validation.manifest.id)
        }
        try fileManager.copyItem(at: directory, to: destination)
        try reload()
        return packs.first { $0.id == validation.manifest.id }!
    }

    private func reload() throws {
        let directories = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        packs = directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let validation = try? AvatarPackValidator.validate(directory: directory) else {
                return nil
            }
            return InstalledAvatarPack(directory: directory, validation: validation)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func locatePackRoot(in staging: URL) throws -> URL {
        if fileManager.fileExists(atPath: staging.appendingPathComponent("manifest.json").path) {
            return staging
        }
        let children = try fileManager.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard children.count == 1,
              fileManager.fileExists(atPath: children[0].appendingPathComponent("manifest.json").path) else {
            throw AvatarPackValidationError.missingManifest
        }
        return children[0]
    }

    private func validateExtractedTree(_ directory: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var totalSize = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true {
                throw AvatarPackLibraryError.unsafeArchiveEntry(url.lastPathComponent)
            }
            totalSize += values.fileSize ?? 0
            if totalSize > 500 * 1_024 * 1_024 {
                throw AvatarPackLibraryError.extractedPackTooLarge
            }
        }
    }
}
