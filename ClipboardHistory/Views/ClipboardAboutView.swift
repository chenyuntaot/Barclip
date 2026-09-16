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
                aboutRow(title: "开发者", value: AppInfo.developer)
                aboutLink(title: "联系邮箱", value: AppInfo.contactEmail, destination: AppInfo.mailtoURL)
                aboutLink(title: "项目仓库", value: AppInfo.repositoryURL.absoluteString, destination: AppInfo.repositoryURL)
            }
            Section {
                Text(AppInfo.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 320)
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
}
