import SwiftUI

struct SettingsView: View {
    @ObservedObject private var updater: GitHubUpdater = .shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            versionSection
            Divider()
            updatesSection
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var versionSection: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.displayName)
                    .font(.headline)
                Text("Version \(AppInfo.appVersion) (\(AppInfo.appBuildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Updates")
                .font(.subheadline.weight(.semibold))

            Toggle(isOn: $updater.includePreReleases) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include beta releases")
                    Text("Receive pre-release versions when checking for updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            HStack {
                Button(action: checkNow) {
                    if isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking…")
                        }
                    } else {
                        Text("Check for Updates")
                    }
                }
                .disabled(isChecking)

                Spacer()

                Text(lastCheckText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let status = statusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var isChecking: Bool {
        if case .checking = updater.state { return true }
        return false
    }

    private var lastCheckText: String {
        "Last check: \(updater.lastCheckDescription)"
    }

    private var statusText: String? {
        switch updater.state {
        case .upToDate:
            return "You're up to date."
        case .available(let v, _):
            return "Update available: \(v)"
        case .error(let m):
            return m
        case .readyToInstall:
            return "Update ready to install."
        case .downloading(let p):
            return "Downloading… \(Int(p * 100))%"
        case .installing(_, let step):
            return step
        default:
            return nil
        }
    }

    private var statusColor: Color {
        switch updater.state {
        case .error: return .orange
        case .available, .readyToInstall: return .accentColor
        default: return .secondary
        }
    }

    private func checkNow() {
        Task { @MainActor in
            await updater.checkForUpdates(force: true)
        }
    }
}
