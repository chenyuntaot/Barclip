import Foundation

enum AppInfo: Sendable {
    static let developer = "陈云涛"
    static let contactEmail = "chenyuntao0123@icloud.com"
    static let repositoryURL = URL(string: "https://github.com/chenyuntaot/Barclip")!
    static let giteeURL = URL(string: "https://gitee.com/chenyuntao-0123/barclip")!
    static let repositoryURLs = [repositoryURL, giteeURL]

    static var displayName: String {
        string(for: "CFBundleDisplayName") ?? "Barclip"
    }

    static var shortVersion: String {
        string(for: "CFBundleShortVersionString") ?? "1.0"
    }

    static var buildNumber: String {
        string(for: "CFBundleVersion") ?? "1"
    }

    static var versionLabel: String {
        "\(shortVersion) (\(buildNumber))"
    }

    static var copyright: String {
        string(for: "NSHumanReadableCopyright") ?? "© 2026 Yuntao Chen"
    }

    static var mailtoURL: URL {
        URL(string: "mailto:\(contactEmail)")!
    }

    private static func string(for key: String) -> String? {
        let value = bundle.object(forInfoDictionaryKey: key) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private static var bundle: Bundle {
        Bundle(for: AppInfoBundleToken.self)
    }
}

private final class AppInfoBundleToken: NSObject {}
