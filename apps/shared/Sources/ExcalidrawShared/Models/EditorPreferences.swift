import Foundation

public enum EditorPreferences {
    public static let attachmentDirectoryKey = "siye.attachmentDirectory"
    private static let historyKey = "siye.attachmentDirectories"
    public static let defaultAttachmentDirectory = "attachments"

    public static func normalizedDirectory(_ value: String) -> String? {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\\"), !path.contains(":"),
              !path.contains("%"), !path.contains("?"), !path.contains("#"),
              path.rangeOfCharacter(from: .controlCharacters) == nil,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return path
    }

    public static func attachmentDirectory(defaults: UserDefaults = .standard) -> String {
        normalizedDirectory(defaults.string(forKey: attachmentDirectoryKey) ?? "") ?? defaultAttachmentDirectory
    }

    public static func setAttachmentDirectory(_ value: String, defaults: UserDefaults = .standard) -> Bool {
        guard let path = normalizedDirectory(value) else { return false }
        var directories = Set(attachmentDirectories(defaults: defaults))
        directories.insert(path)
        defaults.set(Array(directories).sorted(), forKey: historyKey)
        defaults.set(path, forKey: attachmentDirectoryKey)
        return true
    }

    public static func attachmentDirectories(defaults: UserDefaults = .standard) -> [String] {
        Array(Set([defaultAttachmentDirectory, attachmentDirectory(defaults: defaults)] + (defaults.stringArray(forKey: historyKey) ?? []).compactMap(normalizedDirectory)))
    }
}
