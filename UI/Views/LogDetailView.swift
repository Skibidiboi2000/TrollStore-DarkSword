import SwiftUI

struct LogDetailView: View {
    let log: [String]

    var body: some View {
        ScrollView {
            if log.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundColor(AppTheme.labelTertiary)
                    Text("No Log Entries")
                        .font(.headline)
                        .foregroundColor(AppTheme.labelSecondary)
                    Text("Run the exploit to generate log entries.")
                        .font(.body)
                        .foregroundColor(AppTheme.labelTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(log.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundColor(logColor(for: entry))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.mediumCornerRadius))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .navigationTitle("Exploit Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !log.isEmpty {
                ShareLink(item: log.joined(separator: "\n")) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private func logColor(for line: String) -> Color {
        if line.contains("✓") || line.contains("granted") || line.contains("SUCCEEDED") {
            return AppTheme.successColor
        }
        if line.contains("FAILED") || line.contains("failed") || line.contains("error") {
            return AppTheme.failureColor
        }
        if line.contains("Racing") || line.contains("warning") {
            return AppTheme.orangeAccent
        }
        if line.contains("initialized") || line.contains("resolved") || line.contains("ready") {
            return AppTheme.tealAccent
        }
        return AppTheme.labelSecondary
    }
}
