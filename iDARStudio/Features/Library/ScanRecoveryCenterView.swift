import SwiftUI

struct ScanRecoveryCenterView: View {
    private enum LoadState {
        case loading
        case loaded(RecoveryInventory)
        case failed(String)
    }

    @State private var state: LoadState = .loading
    private let service: ScanRecoveryInventoryService

    init(service: ScanRecoveryInventoryService = ScanRecoveryInventoryService()) {
        self.service = service
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
                                RecoveryCandidateDetailView(candidate: candidate)
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
    let candidate: RecoveryCandidate

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusCard
                    factsCard
                    recoveryCard
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
            detailRow("Valid USDZ", candidate.hasValidModel ? "Yes" : "No")
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
                Text("A future recovery action would need a user-selected name and scan type before creating a new metadata record. This preview does not perform that action.")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.secondaryText)
            } else if candidate.classification == .captureDraftWithImages {
                Text("Original images remain untouched. Reconstruction is not started automatically and may still fail if the capture is incomplete.")
                    .font(.caption)
                    .foregroundStyle(StudioTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard()
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
