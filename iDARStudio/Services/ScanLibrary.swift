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
    @Published private(set) var operationError: String?

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

    @discardableResult
    func rename(_ scan: ScanMetadata, to proposedName: String) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            operationError = LocalScanRepository.RepositoryError.invalidScanName.localizedDescription
            return false
        }
        var updated = scan
        updated.name = name
        updated.updatedAt = Date()
        upsert(updated)
        return operationError == nil
    }

    func toggleFavorite(_ scan: ScanMetadata) {
        var updated = scan
        updated.isFavorite.toggle()
        updated.updatedAt = Date()
        upsert(updated)
    }

    @discardableResult
    func delete(_ scan: ScanMetadata) -> Bool {
        let remaining = scans.filter { $0.id != scan.id }
        do {
            try repository.delete(scan, keeping: remaining)
            scans = remaining
            state = .loaded
            operationError = nil
            return true
        } catch {
            let message = error.localizedDescription
            do {
                scans = try repository.load()
                state = .loaded
            } catch {
                state = .failed(error.localizedDescription)
            }
            operationError = message
            return false
        }
    }

    func modelURL(for scan: ScanMetadata) -> URL? {
        try? repository.existingModelURL(for: scan)
    }

    func previewURL(for scan: ScanMetadata) -> URL? {
        try? repository.existingPreviewURL(for: scan)
    }

    func storageUsageBytes() -> Int64? {
        try? repository.storageUsageBytes()
    }

    func storageBreakdown() -> LocalStorageBreakdown? {
        try? repository.storageBreakdown()
    }

    func clearOperationError() {
        operationError = nil
    }

    private func persist(_ updatedScans: [ScanMetadata]) {
        do {
            try repository.save(updatedScans)
            scans = updatedScans
            state = .loaded
            operationError = nil
        } catch {
            operationError = error.localizedDescription
        }
    }

    static var preview: ScanLibrary {
        ScanLibrary(autoLoad: false)
    }
}
