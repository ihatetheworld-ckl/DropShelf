import AppKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ImageIO

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
    private var temporaryResource: TemporaryResource?
    public var isTemporaryFile: Bool { temporaryResource != nil }
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
        self.temporaryResource = TemporaryFileStore.shared.resource(for: fileURL)
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

    convenience init(resource: TemporaryResource, originalURL: URL? = nil,
                     displayName: String? = nil, kind: ShelfItemKind? = nil) {
        self.init(fileURL: resource.fileURL, originalURL: originalURL, displayName: displayName, kind: kind)
        self.temporaryResource = resource
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
            DispatchQueue.main.async { [weak self] in
                self?.thumbnail = image
            }
        }
    }

    /// Persist the export before publishing its URL to another process.
    @discardableResult
    public func preserveForExternalUse() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        do { try temporaryResource?.preserveForExternalUse(); return true }
        catch { return false }
    }
}

public enum PasteboardExtractor {
    private enum Payload {
        case file(URL, TemporaryResource?)
        case image(Data)
        case web(URL)
        case text(String)
    }
    private struct PreparedItem {
        let url: URL
        var resource: TemporaryResource? = nil
        var original: URL? = nil
        var name: String? = nil
        var kind: ShelfItemKind? = nil
        func makeItem() -> ShelfItem {
            if let resource = resource {
                return ShelfItem(resource: resource, originalURL: original, displayName: name, kind: kind)
            }
            return ShelfItem(fileURL: url, displayName: name, kind: kind)
        }
    }
    // Pasteboard data must be captured before the drag session ends. PNG encoding
    // and disk IO run on a worker; AppKit thumbnails and shelf state stay on main.
    @discardableResult
    static func extractItemsAsync(from pasteboard: NSPasteboard,
                                  completion: @escaping ([ShelfItem], [String]) -> Void) -> Bool {
        let payloads = capture(pasteboard)
        guard !payloads.isEmpty else { return false }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = prepare(payloads)
            DispatchQueue.main.async { completion(result.0.map { $0.makeItem() }, result.1) }
        }
        return true
    }
    /// Synchronous extraction is retained for small, in-process callers and tests.
    public static func extractItems(from pasteboard: NSPasteboard) -> [ShelfItem] {
        prepare(capture(pasteboard)).0.map { $0.makeItem() }
    }
    private static func capture(_ pb: NSPasteboard) -> [Payload] {
        if let paths = pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String], !paths.isEmpty {
            return paths.map { let url = URL(fileURLWithPath: $0).standardizedFileURL; return .file(url, TemporaryFileStore.shared.resource(for: url)) }
        }
        return (pb.pasteboardItems ?? []).compactMap { item in
            if let string = item.string(forType: .fileURL), let url = URL(string: string), url.isFileURL {
                return .file(url.standardizedFileURL, TemporaryFileStore.shared.resource(for: url))
            }
            if let data = item.data(forType: .png) ?? item.data(forType: .tiff) { return .image(data) }
            if let string = item.string(forType: .URL), let url = URL(string: string), !url.isFileURL { return .web(url) }
            if let text = item.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .text(text) }
            return nil
        }
    }
    private static func prepare(_ payloads: [Payload]) -> ([PreparedItem], [String]) {
        var items: [PreparedItem] = []
        var errors: [String] = []
        var paths = Set<String>()
        for payload in payloads {
            do {
                switch payload {
                case .file(let url, let lease):
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        throw NSError(domain: "DropShelf.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件不存在：" + url.lastPathComponent])
                    }
                    if paths.insert(url.path).inserted { items.append(PreparedItem(url: url, resource: lease)) }
                case .image(let data):
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
                    let png = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
                    let resource = try TemporaryFileStore.shared.createResource(filename: "Image.png")
                    try (png as Data).write(to: resource.fileURL, options: .atomic)
                    items.append(PreparedItem(url: resource.fileURL, resource: resource, kind: .image))
                case .web(let url):
                    let resource = try TemporaryFileStore.shared.createResource(filename: (url.host ?? "Link") + ".webloc")
                    let data = try PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
                    try data.write(to: resource.fileURL, options: .atomic)
                    items.append(PreparedItem(url: resource.fileURL, resource: resource, original: url, name: url.absoluteString, kind: .webURL))
                case .text(let text):
                    let title = String(text.prefix(24)).replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = (title.isEmpty || title.hasPrefix(".") ? "Snippet" : title) + ".txt"
                    let resource = try TemporaryFileStore.shared.createResource(filename: name)
                    try text.write(to: resource.fileURL, atomically: true, encoding: .utf8)
                    items.append(PreparedItem(url: resource.fileURL, resource: resource, kind: .text))
                }
            } catch { errors.append(error.localizedDescription) }
        }
        return (items, errors)
    }
}
