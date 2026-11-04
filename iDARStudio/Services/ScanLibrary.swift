import Foundation
import Combine

@MainActor
final class ScanLibrary: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var scans: [ScanMetadata] = []
    @Published private(set) var state: State = .loading

    private let repository: LocalScanRepository

    init(repository: LocalScanRepository? = nil, autoLoad: Bool = true) {
        self.repository = repository ?? LocalScanRepository()
        if autoLoad { reload() }
    }

    func reload() {
        state = .loading
        do {
            scans = try repository.load()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func upsert(_ scan: ScanMetadata) {
        var updatedScans = scans
        if let index = updatedScans.firstIndex(where: { $0.id == scan.id }) {
            updatedScans[index] = scan
        } else {
            updatedScans.append(scan)
        }
        updatedScans.sort { $0.updatedAt > $1.updatedAt }
        persist(updatedScans)
    }

    func delete(at offsets: IndexSet) {
        var updatedScans = scans
        for index in offsets.sorted(by: >) {
            updatedScans.remove(at: index)
        }
        persist(updatedScans)
    }

    func modelURL(for scan: ScanMetadata) -> URL? {
        try? repository.existingModelURL(for: scan)
    }

    private func persist(_ updatedScans: [ScanMetadata]) {
        do {
            try repository.save(updatedScans)
            scans = updatedScans
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    static var preview: ScanLibrary {
        ScanLibrary(autoLoad: false)
    }
}
