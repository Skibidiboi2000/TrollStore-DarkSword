import SwiftUI

struct AboutView: View {
    private let device = DeviceInfo.current

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: AppTheme.largeCornerRadius)
                        .fill(LinearGradient(
                            colors: [
                                Color(red: 10/255, green: 77/255, blue: 153/255),
                                Color(red: 91/255, green: 26/255, blue: 153/255)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: "lock.open.display")
                                .font(.system(size: 34))
                                .foregroundColor(.white)
                        )

                    Text("TrollStore DarkSword")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("v1.0")
                        .font(.body)
                        .foregroundColor(AppTheme.labelSecondary)
                }
                .padding(.top, 20)

                // Info
                AppTheme.sectionHeader("Info")
                    .frame(maxWidth: .infinity, alignment: .leading)

                infoSection
                    .padding(.horizontal, 20)

                // Credits
                AppTheme.sectionHeader("Credits")
                    .frame(maxWidth: .infinity, alignment: .leading)

                creditsSection
                    .padding(.horizontal, 20)

                Color.clear.frame(height: 20)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var infoSection: some View {
        VStack(spacing: 0) {
            infoRow(label: "Version", value: "1.0")
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "Device", value: device.modelIdentifier)
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "iOS", value: device.systemVersion)
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "Chip", value: device.cpuFamilyName)
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "PAC", value: device.isPACSupported ? "Yes" : "No", valueColor: device.isPACSupported ? AppTheme.successColor : nil)
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            infoRow(label: "Exploit", value: "DarkSword")
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private func infoRow(label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(minWidth: 60, alignment: .leading)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(valueColor ?? .primary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private var creditsSection: some View {
        VStack(spacing: 0) {
            creditRow(name: "DarkSword", author: "rooootdev")
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            creditRow(name: "ChOma", author: "khanhduytran0")
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            creditRow(name: "XPF (Fugu14)", author: "Linus Henze")
            AppTheme.thinSeparatorColor.frame(height: 0.5).padding(.leading, 16)
            creditRow(name: "RemoteCall", author: "LARA")
        }
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private func creditRow(name: String, author: String) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.body)
            Spacer()
            Text(author)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }
}
