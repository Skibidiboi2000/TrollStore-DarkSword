import SwiftUI

/// A simple file browser using VFS (kernel r/w filesystem access).
/// Visible after the exploit has been run and VFS initialized.
struct FileBrowserView: View {
    @EnvironmentObject private var coordinator: ContentCoordinator
    @State private var currentPath = "/"
    @State private var entries: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilePath: String?
    @State private var previewContent: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Path bar
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundColor(AppTheme.accentColor)
                    Text(currentPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(action: goUp) {
                        Image(systemName: "arrow.up")
                            .font(.caption)
                    }
                    .disabled(currentPath == "/")
                    .opacity(currentPath == "/" ? 0.3 : 1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.cardBackground)

                // Content
                if isLoading {
                    Spacer()
                    ProgressView("Loading...")
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(AppTheme.warningColor)
                        Text(error)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else if entries.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.title2)
                            .foregroundColor(AppTheme.labelTertiary)
                        Text("Empty directory")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    List(entries, id: \.self) { entry in
                        Button(action: { navigate(entry) }) {
                            HStack(spacing: 12) {
                                Image(systemName: isDirectory(entry) ? "folder.fill" : "doc.fill")
                                    .foregroundColor(isDirectory(entry) ? AppTheme.accentColor : AppTheme.labelTertiary)
                                    .frame(width: 24)
                                Text(entry)
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer()
                                if !isDirectory(entry) {
                                    Text(sizeString(entry))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { loadEntries() }
    }

    private func loadEntries() {
        isLoading = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let list = VirtualFileSystem.listDirectory(at: currentPath)
            let sorted = list.sorted { a, b in
                let aDir = isDirectory(a)
                let bDir = isDirectory(b)
                if aDir != bDir { return aDir }
                return a < b
            }
            DispatchQueue.main.async {
                entries = sorted
                isLoading = false
                if list.isEmpty {
                    // VFS might not be ready
                    errorMessage = "VFS not initialized — run exploit first"
                }
            }
        }
    }

    private func navigate(_ entry: String) {
        if isDirectory(entry) {
            if currentPath == "/" {
                currentPath = "/\(entry)"
            } else {
                currentPath = "\(currentPath)/\(entry)"
            }
            loadEntries()
        } else {
            selectedFilePath = currentPath == "/" ? "/\(entry)" : "\(currentPath)/\(entry)"
        }
    }

    private func goUp() {
        guard currentPath != "/" else { return }
        let components = currentPath.split(separator: "/").dropLast()
        currentPath = components.isEmpty ? "/" : "/" + components.joined(separator: "/")
        loadEntries()
    }

    private func isDirectory(_ entry: String) -> Bool {
        // Simple heuristic: entries without a '.' extension are dirs (most Unix filesystems)
        // VFS entries from vfs_listdir don't include type info in the basic API
        !entry.contains(".")
    }

    private func sizeString(_ entry: String) -> String {
        let path = currentPath == "/" ? "/\(entry)" : "\(currentPath)/\(entry)"
        let size = VirtualFileSystem.fileSize(at: path)
        guard size >= 0 else { return "" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(size / 1024) KB" }
        return "\(size / (1024 * 1024)) MB"
    }
}
