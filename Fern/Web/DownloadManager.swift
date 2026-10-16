import AppKit
import Observation
import WebKit

/// Um download, em andamento ou já terminado.
@MainActor
@Observable
final class DownloadItem: Identifiable {
    enum State: Equatable {
        case inProgress
        case finished
        case failed(String)
        case cancelled
    }

    let id: UUID
    let date: Date
    let sourceURL: URL?
    let isPrivate: Bool
    private(set) var filename: String
    private(set) var destination: URL?
    /// De 0 a 1; `nil` quando o servidor não informa o tamanho.
    private(set) var progress: Double?
    fileprivate(set) var state: State

    @ObservationIgnored fileprivate var download: WKDownload?
    @ObservationIgnored fileprivate var progressObservation: NSKeyValueObservation?
    /// Janela que iniciou o download, para mostrar a lista só nela.
    @ObservationIgnored fileprivate weak var window: BrowserWindow?

    fileprivate init(
        id: UUID = UUID(), date: Date = .now, sourceURL: URL?, filename: String, destination: URL? = nil,
        state: State, isPrivate: Bool
    ) {
        self.id = id
        self.date = date
        self.sourceURL = sourceURL
        self.filename = filename
        self.destination = destination
        self.state = state
        self.isPrivate = isPrivate
    }

    fileprivate func setDestination(_ url: URL) {
        destination = url
        filename = url.lastPathComponent
    }

    fileprivate func setProgress(_ value: Double?) {
        progress = value
    }
}

/// Recebe os downloads do WebKit, salva na pasta Downloads e mantém a lista mostrada no
/// botão de downloads. Os concluídos ficam guardados entre execuções (exceto os de
/// janelas privadas).
@MainActor
@Observable
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()

    private static let storageKey = "downloads"
    private static let storedLimit = 50

    private(set) var items: [DownloadItem] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let fileManager = FileManager.default

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        items = loadStoredItems()
    }

    var hasActiveDownloads: Bool {
        items.contains { $0.state == .inProgress }
    }

    // MARK: - Ações

    func track(_ download: WKDownload, from window: BrowserWindow?) {
        let item = DownloadItem(
            sourceURL: download.originalRequest?.url,
            filename: download.originalRequest?.url?.lastPathComponent ?? "",
            state: .inProgress,
            isPrivate: window?.isPrivate ?? false
        )
        item.download = download
        item.window = window
        download.delegate = self
        item.progressObservation = download.progress.observe(\.fractionCompleted) { [weak item] progress, _ in
            let indeterminate = progress.isIndeterminate
            let fraction = progress.fractionCompleted
            Task { @MainActor in item?.setProgress(indeterminate ? nil : fraction) }
        }
        items.insert(item, at: 0)
        window?.showDownloads()
    }

    func cancel(_ item: DownloadItem) {
        item.download?.cancel { _ in }
        finish(item, as: .cancelled)
    }

    func reveal(_ item: DownloadItem) {
        guard let destination = item.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    func open(_ item: DownloadItem) {
        guard let destination = item.destination else { return }
        NSWorkspace.shared.open(destination)
    }

    /// Tira da lista os que já terminaram. Os arquivos continuam na pasta Downloads.
    func clearFinished() {
        items.removeAll { $0.state != .inProgress }
        saveItems()
    }

    // MARK: - WKDownloadDelegate

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        guard let item = item(for: download),
            let folder = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        else {
            completionHandler(nil)
            return
        }
        let destination = Self.uniqueDestination(for: suggestedFilename, in: folder) {
            self.fileManager.fileExists(atPath: $0.path)
        }
        item.setDestination(destination)
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else { return }
        finish(item, as: .finished)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let item = item(for: download), item.state == .inProgress else { return }
        finish(item, as: .failed(error.localizedDescription))
    }

    // MARK: - Interno

    /// "relatorio.pdf" vira "relatorio 2.pdf" se já existir, e assim por diante.
    nonisolated static func uniqueDestination(for filename: String, in folder: URL, exists: (URL) -> Bool) -> URL {
        let clean = filename.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = clean.isEmpty ? "download" : clean
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while exists(candidate) {
            let numbered = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            number += 1
        }
        return candidate
    }

    private func item(for download: WKDownload) -> DownloadItem? {
        items.first { $0.download === download }
    }

    private func finish(_ item: DownloadItem, as state: DownloadItem.State) {
        item.state = state
        if state == .finished { item.setProgress(1) }
        item.progressObservation = nil
        item.download = nil
        saveItems()
    }

    // MARK: - Lista salva

    private struct StoredItem: Codable {
        var id: UUID
        var date: Date
        var sourceURL: URL?
        var filename: String
        var destination: URL?
        var succeeded: Bool
    }

    private func saveItems() {
        let stored = items.prefix(Self.storedLimit).compactMap { item -> StoredItem? in
            guard !item.isPrivate, item.state != .inProgress else { return nil }
            return StoredItem(
                id: item.id, date: item.date, sourceURL: item.sourceURL, filename: item.filename,
                destination: item.destination, succeeded: item.state == .finished)
        }
        defaults.set(try? JSONEncoder().encode(Array(stored)), forKey: Self.storageKey)
    }

    private func loadStoredItems() -> [DownloadItem] {
        guard let data = defaults.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode([StoredItem].self, from: data)
        else { return [] }
        return stored.map {
            DownloadItem(
                id: $0.id, date: $0.date, sourceURL: $0.sourceURL, filename: $0.filename,
                destination: $0.destination,
                state: $0.succeeded ? .finished : .failed(""), isPrivate: false)
        }
    }
}
