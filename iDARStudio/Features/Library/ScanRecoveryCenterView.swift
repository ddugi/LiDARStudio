import SwiftUI

struct ScanRecoveryCenterView: View {
    @EnvironmentObject private var library: ScanLibrary
    private enum LoadState {
        case loading
        case loaded(RecoveryInventory)
        case failed(String)
    }

    @State private var state: LoadState = .loading
    private let service: ScanRecoveryInventoryService
    private let recoveryService: ScanModelRecoveryService

    init(
        service: ScanRecoveryInventoryService = ScanRecoveryInventoryService(),
        recoveryService: ScanModelRecoveryService = ScanModelRecoveryService()
    ) {
        self.service = service
        self.recoveryService = recoveryService
    }

    var body: some View {
        ZStack {
            StudioBackground()
            content
        }
        .navigationTitle("Recovery Center")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Inspecting local projects…")
                .tint(StudioTheme.accent)
                .accessibilityLabel("Inspecting local scan projects")
        case .failed(let message):
            ContentUnavailableView {
                Label("Inventory unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.accent)
                    .foregroundStyle(.black)
            }
        case .loaded(let inventory):
            inventoryList(inventory)
        }
    }

    private func inventoryList(_ inventory: RecoveryInventory) -> some View {
        List {
            Section {
                Label("Read-only inspection", systemImage: "lock.shield")
                    .foregroundStyle(StudioTheme.accent)
                Text("Recovery Center does not rename, move, delete, reconstruct, or add files to My Scans. Unknown projects remain preserved for inspection.")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Inventory") {
                ForEach(RecoveryClassification.allCases, id: \.self) { classification in
                    LabeledContent(classification.title, value: "\(inventory.count(for: classification))")
                }
            }

            ForEach(RecoveryClassification.allCases, id: \.self) { classification in
                let candidates = inventory.candidates.filter { $0.classification == classification }
                if !candidates.isEmpty {
                    Section(classification.title) {
                        ForEach(candidates) { candidate in
                            NavigationLink {
                                RecoveryCandidateDetailView(
                                    candidate: candidate,
                                    recoveryService: recoveryService
                                ) {
                                    library.reload()
                                    Task { await load() }
                                }
                            } label: {
                                RecoveryCandidateRow(candidate: candidate)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    @MainActor
    private func load() async {
        state = .loading
        let result = await Task.detached(priority: .utility) {
            Result { try service.inventory() }
        }.value
        switch result {
        case .success(let inventory): state = .loaded(inventory)
        case .failure(let error): state = .failed(error.localizedDescription)
        }
    }
}

private struct RecoveryCandidateRow: View {
    let candidate: RecoveryCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.displayName).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: candidate.hasValidModel ? "cube.transparent.fill" : "archivebox")
                    .foregroundStyle(candidate.hasValidModel ? StudioTheme.accent : StudioTheme.warning)
                    .accessibilityHidden(true)
            }
            Text("ID \(candidate.safeIdentifier) · \(ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file))")
                .font(.caption)
                .foregroundStyle(StudioTheme.secondaryText)
            if candidate.originalImageCount > 0 {
                Label("\(candidate.originalImageCount) verified source images", systemImage: "photo.stack")
                    .font(.caption2)
                    .foregroundStyle(StudioTheme.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens a read-only recovery assessment")
    }
}

private struct RecoveryCandidateDetailView: View {
    @EnvironmentObject private var library: ScanLibrary
    let candidate: RecoveryCandidate
    let recoveryService: ScanModelRecoveryService
    let onRestored: () -> Void
    @State private var proposedName: String
    @State private var showConfirmation = false
    @State private var isRestoring = false
    @State private var resultMessage: String?
    @State private var restoreSucceeded = false

    init(
        candidate: RecoveryCandidate,
        recoveryService: ScanModelRecoveryService,
        onRestored: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.recoveryService = recoveryService
        self.onRestored = onRestored
        _proposedName = State(initialValue: "Recovered Object \(candidate.safeIdentifier)")
    }

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard
                    factsCard
                    recoveryCard
                    if candidate.canRestoreToLibrary, !restoreSucceeded {
                        restoreControls
                    }
                    if let modelURL = candidate.validatedModelURL {
                        NavigationLink {
                            USDZViewerView(modelURL: modelURL, title: candidate.displayName)
                        } label: {
                            Label("Inspect USDZ in 3D", systemImage: "cube.transparent")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.accent)
                        .foregroundStyle(.black)
                    }
                    Label("No files or scan metadata will be changed.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(StudioTheme.secondaryText)
                        .studioCard()
                }
                .padding(18)
            }
        }
        .navigationTitle(candidate.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Restore to My Scans?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore") { restore() }
        } message: {
            Text("This adds one metadata record for \(proposedName). The original USDZ and capture files remain unchanged.")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(candidate.classification.title, systemImage: candidate.hasValidModel ? "checkmark.seal.fill" : "questionmark.folder")
                .font(.headline)
                .foregroundStyle(candidate.hasValidModel ? StudioTheme.accent : StudioTheme.warning)
            Text(candidate.reason)
                .font(.subheadline)
                .foregroundStyle(StudioTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var factsCard: some View {
        VStack(spacing: 12) {
            detailRow("Safe identifier", candidate.safeIdentifier)
            detailRow("Size", ByteCountFormatter.string(fromByteCount: candidate.sizeBytes, countStyle: .file))
            detailRow("Source images", "\(candidate.originalImageCount)")
            detailRow("Capture checkpoints", "\(candidate.captureCheckpointCount)")
            detailRow("Reconstruction files", "\(candidate.reconstructionIntermediateCount)")
            detailRow("Valid manifest", candidate.hasValidManifest ? "Yes" : "No")
            if let manifestStatus = candidate.manifestStatus {
                detailRow("Manifest status", manifestStatus.rawValue)
            }
            detailRow("Valid USDZ", candidate.hasValidModel ? "Yes" : "No")
            if let captureCreatedAt = candidate.captureCreatedAt {
                detailRow("Capture created", captureCreatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let modifiedAt = candidate.modifiedAt {
                detailRow("Last modified", modifiedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .studioCard()
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recovery assessment").font(.headline)
            Text(candidate.eligibility.title)
                .foregroundStyle(StudioTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if candidate.classification == .validUnindexedModel {
                Text("Restoration creates a local Object scan metadata record using the validated model reference. It does not copy, move, rename, or delete source files.")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.secondaryText)
            } else if candidate.classification == .captureDraftWithImages {
                Text("Original images remain untouched. No validated USDZ is currently available; reconstruction must be started separately and may still fail if required viewpoints or image quality are insufficient.")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
    }

    private var restoreControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore metadata").font(.headline)
            TextField("Scan name", text: $proposedName)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(StudioTheme.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Recovered scan name")
            Button {
                showConfirmation = true
            } label: {
                if isRestoring {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Label("Restore to Library", systemImage: "plus.rectangle.on.folder")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.accent)
            .foregroundStyle(.black)
            .disabled(isRestoring || proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let resultMessage {
                Label(resultMessage, systemImage: restoreSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(restoreSucceeded ? StudioTheme.accent : StudioTheme.warning)
            }
        }
        .studioCard()
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        resultMessage = nil
        Task {
            do {
                let scan = try await recoveryService.restore(candidateID: candidate.id, proposedName: proposedName)
                await MainActor.run {
                    restoreSucceeded = true
                    resultMessage = "\(scan.name) was restored to My Scans."
                    isRestoring = false
                    library.reload()
                    onRestored()
                }
            } catch {
                await MainActor.run {
                    restoreSucceeded = false
                    resultMessage = error.localizedDescription
                    isRestoring = false
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(StudioTheme.secondaryText)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
