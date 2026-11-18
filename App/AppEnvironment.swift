import SwiftUI
import KomaCore

@MainActor
final class AppEnvironment: ObservableObject {
    let db: AppDatabase
    let library: LibraryRepository
    let history: HistoryRepository
    let sources: SourceRegistry
    let importer: ImportService
    let toast = ToastCenter()
    @Published private(set) var importingCount = 0

    init() {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let libraryRoot = documents.appendingPathComponent("Library", isDirectory: true)
        try? fm.createDirectory(at: libraryRoot, withIntermediateDirectories: true)

        let database: AppDatabase
        var databaseFellBack = false
        if let onDisk = try? AppDatabase.onDisk(at: support.appendingPathComponent("koma.sqlite")) {
            database = onDisk
        } else if let memory = try? AppDatabase.inMemory() {
            database = memory
            databaseFellBack = true
        } else {
            fatalError("Unable to create database")
        }
        db = database
        let resolver = CoverURLResolver(libraryRoot: libraryRoot)
        library = LibraryRepository(database, coverResolver: resolver)
        history = HistoryRepository(database, coverResolver: resolver)
        sources = SourceRegistry(sources: [LocalSource(libraryRoot: libraryRoot)])
        importer = ImportService(libraryRoot: libraryRoot, library: library)
        if databaseFellBack {
            Task { [toast] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                toast.show("数据库打开失败，本次修改不会被保存")
            }
        }
    }

    /// Imports the given files and reports the outcome with a toast.
    func importAndReport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        importingCount += urls.count
        Task {
            let results = await importer.importFiles(urls)
            importingCount -= urls.count
            let failures = results.compactMap { result -> Error? in
                if case .failure(let error) = result { return error }
                return nil
            }
            let successes = results.count - failures.count
            if failures.isEmpty {
                Theme.haptic(.medium)
                if successes == 1, case .success(let ref) = results[0] {
                    toast.show("已导入《\(ref.title)》")
                } else {
                    toast.show("已导入 \(successes) 部漫画")
                }
            } else if successes == 0 {
                toast.show(ImportService.message(for: failures[0]))
            } else {
                toast.show("已导入 \(successes) 部，\(failures.count) 个失败")
            }
        }
    }
}
