import AppKit
import SwiftUI

struct ClipboardAboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text(AppInfo.displayName)
                        .font(.title2.weight(.semibold))
                    Text("程序版本 \(AppInfo.versionLabel)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            Section("关于我们") {
                aboutRow(title: String(localized: "开发者"), value: AppInfo.developer)
                aboutLink(title: String(localized: "联系邮箱"), value: AppInfo.contactEmail, destination: AppInfo.mailtoURL)
                aboutLinks(title: String(localized: "项目仓库"), destinations: AppInfo.repositoryURLs)
            }
            Section {
                Text(AppInfo.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 320, maxHeight: .infinity)
    }

    private func aboutRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func aboutLink(title: String, value: String, destination: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(value, destination: destination)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityLabel("\(title) \(value)")
                .accessibilityHint("在默认应用中打开")
        }
    }

    private func aboutLinks(title: String, destinations: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(destinations, id: \.self) { destination in
                Link(destination.absoluteString, destination: destination)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .accessibilityLabel("\(title) \(destination.absoluteString)")
                    .accessibilityHint("在默认应用中打开")
            }
        }
    }
}
