import SwiftUI

struct AppIntentModelDestinationView: View {
    @EnvironmentObject private var library: ScanLibrary
    let scanID: UUID

    var body: some View {
        Group {
            if let scan = library.scans.first(where: { $0.id == scanID }),
               let modelURL = library.modelURL(for: scan) {
                USDZViewerView(modelURL: modelURL, title: scan.name)
            } else {
                ContentUnavailableView(
                    "Model Unavailable",
                    systemImage: "questionmark.folder",
                    description: Text("The selected scan no longer has a valid local USDZ model.")
                )
            }
        }
        .task { library.reload() }
    }
}
