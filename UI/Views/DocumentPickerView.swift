import SwiftUI
import UniformTypeIdentifiers

/// Wraps `UIDocumentPickerViewController` to bypass the iOS 17+ TabView `.fileImporter`
/// callback bug.  Using `asCopy: true` so the returned file is an app-owned copy — no
/// security-scoped resource access needed.
///
/// ## Why this exists
///
/// SwiftUI's `.fileImporter` modifier is known to silently drop callbacks when placed
/// inside a `TabView` on iOS 17+.  The UIKit-level `UIDocumentPickerViewController` does
/// not have this bug.  Additionally, using `asCopy: true` avoids UTI-matching issues that
/// can make `.ipa` files appear but not be selectable with `.data`.
struct DocumentPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        container.view.isHidden = true
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented && !context.coordinator.isPresenting {
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.data],
                asCopy: true
            )
            picker.allowsMultipleSelection = false
            picker.delegate = context.coordinator
            context.coordinator.isPresenting = true
            uiViewController.present(picker, animated: true)
        } else if !isPresented && context.coordinator.isPresenting {
            context.coordinator.isPresenting = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Receives `UIDocumentPickerViewController` delegate callbacks and forwards the
    /// selected URL to the owning SwiftUI view.
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerView
        var isPresenting = false

        init(parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            defer { parent.isPresented = false }
            guard let url = urls.first else { return }
            parent.onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
