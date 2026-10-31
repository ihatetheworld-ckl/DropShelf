import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

public enum ShelfItemKind: String, Codable {
    case file
    case folder
    case image
    case text
    case webURL
}

public final class ShelfItem: ObservableObject, Identifiable, Equatable {
    public let id: UUID
    public let fileURL: URL
    public let originalURL: URL?
    public let displayName: String
    public let kind: ShelfItemKind
    public let fileSize: Int64
    public let isTemporaryFile: Bool
    public let createdAt: Date

    @Published public var thumbnail: NSImage

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        originalURL: URL? = nil,
        displayName: String? = nil,
        kind: ShelfItemKind? = nil,
        isTemporaryFile: Bool = false
    ) {
        self.id = id
        self.fileURL = fileURL
        self.originalURL = originalURL
        self.displayName = displayName ?? fileURL.lastPathComponent
        self.isTemporaryFile = isTemporaryFile
        self.createdAt = Date()

        let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        let isDir = resourceValues?.isDirectory ?? false
        self.fileSize = Int64(resourceValues?.fileSize ?? resourceValues?.totalFileAllocatedSize ?? 0)

        if let explicitKind = kind {
            self.kind = explicitKind
        } else if isDir {
            self.kind = .folder
        } else {
            let ext = fileURL.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svg", "icns"].contains(ext) {
                self.kind = .image
            } else if ["txt", "md", "json", "csv", "log", "rtf"].contains(ext) {
                self.kind = .text
            } else if ["webloc", "url"].contains(ext) {
                self.kind = .webURL
            } else {
                self.kind = .file
            }
        }

        let defaultIcon = NSWorkspace.shared.icon(forFile: fileURL.path)
        defaultIcon.size = NSSize(width: 128, height: 128)
        self.thumbnail = defaultIcon

        generateQuickLookThumbnail()
    }

    public static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }

    public var formattedSize: String {
        if kind == .folder {
            return "文件夹"
        }
        if fileSize <= 0 {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    private func generateQuickLookThumbnail() {
        let size = CGSize(width: 160, height: 160)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: scale,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let self = self, let cgImage = representation?.cgImage else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                self.thumbnail = image
            }
        }
    }

    public func cleanupIfNeeded() {
        if isTemporaryFile {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}

public enum PasteboardExtractor {
    private static var tempDirectory: URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("DropShelfItems", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    public static func extractItems(from pasteboard: NSPasteboard) -> [ShelfItem] {
        var result: [ShelfItem] = []
        var seenPaths = Set<String>()

        // 1. Read File URLs first
        let classes: [AnyClass] = [NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let fileURLs = pasteboard.readObjects(forClasses: classes, options: options) as? [URL], !fileURLs.isEmpty {
            for url in fileURLs {
                let standardized = url.standardizedFileURL
                guard FileManager.default.fileExists(atPath: standardized.path),
                      !seenPaths.contains(standardized.path) else { continue }
                seenPaths.insert(standardized.path)
                result.append(ShelfItem(fileURL: standardized))
            }
        }

        if !result.isEmpty {
            return result
        }

        // 2. Check legacy NSFilenamesPboardType if any
        if let filenames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for path in filenames {
                let url = URL(fileURLWithPath: path).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path),
                      !seenPaths.contains(url.path) else { continue }
                seenPaths.insert(url.path)
                result.append(ShelfItem(fileURL: url))
            }
            if !result.isEmpty {
                return result
            }
        }

        // 3. Check Images (e.g. dragged from browser or screenshot)
        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let timestamp = Self.timestampString()
            let filename = "Image-\(timestamp).png"
            let fileURL = uniqueTempURL(filename: filename)
            if (try? pngData.write(to: fileURL)) != nil {
                result.append(ShelfItem(fileURL: fileURL, displayName: filename, kind: .image, isTemporaryFile: true))
                return result
            }
        }

        // 4. Check Web URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let webURL = urls.first(where: { !$0.isFileURL }) {
            let host = webURL.host ?? "Link"
            let filename = "\(host)-\(Self.timestampString()).webloc"
            let fileURL = uniqueTempURL(filename: filename)
            let plistDict: [String: Any] = ["URL": webURL.absoluteString]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0),
               (try? data.write(to: fileURL)) != nil {
                result.append(
                    ShelfItem(
                        fileURL: fileURL,
                        originalURL: webURL,
                        displayName: webURL.absoluteString,
                        kind: .webURL,
                        isTemporaryFile: true
                    )
                )
                return result
            }
        }

        // 5. Check Plain TextSnippet
        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            let previewTitle = String(text.prefix(24))
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let safeName = previewTitle.isEmpty ? "Snippet-\(Self.timestampString())" : previewTitle
            let filename = "\(safeName).txt"
            let fileURL = uniqueTempURL(filename: filename)
            if (try? text.write(to: fileURL, atomically: true, encoding: .utf8)) != nil {
                result.append(ShelfItem(fileURL: fileURL, displayName: filename, kind: .text, isTemporaryFile: true))
                return result
            }
        }

        return result
    }

    private static func uniqueTempURL(filename: String) -> URL {
        var candidate = tempDirectory.appendingPathComponent(filename)
        var counter = 1
        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            candidate = tempDirectory.appendingPathComponent(nextName)
            counter += 1
        }
        return candidate
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        return formatter.string(from: Date())
    }
}
