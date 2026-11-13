import SwiftUI

/// A file ready to share, so `.sheet(item:)` can open the share sheet with it.
struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet, for saving a file to Files, AirDropping it or mailing it.
/// SwiftUI's `ShareLink` needs the item before the tap, and the export is built after it, so this wraps UIKit's.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
