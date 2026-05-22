import SwiftUI

struct UpdateWindowView: View {
    @ObservedObject var updater: GitHubUpdater = .shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            content
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            actionBar
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 540, height: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            appIcon
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("A new version of \(AppInfo.displayName) is available!")
                    .font(.headline)
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var appIcon: some View {
        if let nsImage = NSApp.applicationIconImage {
            return AnyView(Image(nsImage: nsImage).resizable())
        }
        return AnyView(
            Image(systemName: "command")
                .resizable()
                .padding(10)
                .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        )
    }

    private var subtitleText: String {
        switch updater.state {
        case .available(let version, _):
            if updater.isNewerBuild {
                return "Build \(version) (\(updater.latestRelease?.macOSAsset?.buildNumber.map(String.init) ?? "?")) is available — you have \(updater.currentVersion) (\(AppInfo.appBuildNumber))."
            }
            return "\(AppInfo.displayName) \(version) is available — you have \(updater.currentVersion). Would you like to install it now?"
        case .downloading:
            return "Downloading update…"
        case .readyToInstall:
            return "The update is ready to install."
        case .installing(_, let step):
            return step
        case .error(let message):
            return message
        default:
            return ""
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .available(_, let notes):
            releaseNotesPane(notes: notes)
        case .downloading(let progress):
            progressPane(progress: progress, title: "Downloading…")
        case .readyToInstall:
            readyToInstallPane
        case .installing(let progress, let step):
            progressPane(progress: progress, title: step)
        case .error(let message):
            errorPane(message: message)
        default:
            EmptyView()
        }
    }

    private func releaseNotesPane(notes: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Release Notes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                if let notes, !notes.isEmpty {
                    Text(attributed(notes))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No release notes provided.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.2))
            )
        }
    }

    private func attributed(_ source: String) -> AttributedString {
        if let parsed = try? AttributedString(markdown: source, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )) {
            return parsed
        }
        return AttributedString(source)
    }

    private func progressPane(progress: Double, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline)
            ProgressView(value: max(0, min(progress, 1)))
                .progressViewStyle(.linear)
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var readyToInstallPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update is ready to install. \(AppInfo.displayName) will quit and relaunch.")
            Spacer()
        }
    }

    private func errorPane(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Update failed").font(.headline)
            }
            Text(message).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private var actionBar: some View {
        switch updater.state {
        case .available:
            HStack {
                Button("Skip This Version") {
                    updater.skipCurrentUpdate()
                    UpdateWindowPresenter.shared.hide()
                }
                Spacer()
                Button("Remind Me Later") {
                    updater.remindLater()
                }
                Button("Install Update") {
                    Task { await updater.downloadAndInstall() }
                }
                .keyboardShortcut(.defaultAction)
            }
        case .downloading:
            HStack {
                Spacer()
                Button("Cancel") { updater.cancelDownload() }
            }
        case .readyToInstall:
            HStack {
                Button("Later") {
                    UpdateWindowPresenter.shared.hide()
                    updater.resetToIdle()
                }
                Spacer()
                Button("Install & Restart") {
                    Task { await updater.installUpdate() }
                }
                .keyboardShortcut(.defaultAction)
            }
        case .installing:
            EmptyView()
        case .error:
            HStack {
                Button("Close") {
                    UpdateWindowPresenter.shared.hide()
                    updater.resetToIdle()
                }
                Spacer()
                Button("Try Again") {
                    Task { await updater.checkForUpdates(force: true) }
                }
                .keyboardShortcut(.defaultAction)
            }
        default:
            HStack {
                Spacer()
                Button("Close") {
                    UpdateWindowPresenter.shared.hide()
                }
            }
        }
    }
}
