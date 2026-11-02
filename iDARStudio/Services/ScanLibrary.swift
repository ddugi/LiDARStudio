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
        if let index = scans.firstIndex(where: { $0.id == scan.id }) {
            scans[index] = scan
        } else {
            scans.append(scan)
        }
        scans.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            scans.remove(at: index)
        }
        persist()
    }

    private func persist() {
        do {
            try repository.save(scans)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    static var preview: ScanLibrary {
        ScanLibrary(autoLoad: false)
    }
}
