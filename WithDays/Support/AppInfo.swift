import Foundation

enum AppInfo {
    static let name = "WithDays"
    static let summary = "WithDays は、Appleのカレンダーの予定をそのまま読み書きする月表示のカレンダーです。iPhone や Mac のカレンダーと自動で同期されます。"
    static let repositoryURL = URL(string: "https://github.com/ffp1/withdays")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    struct Release: Identifiable {
        let version: String
        let date: String
        let notes: [String]

        var id: String { version }
    }

    /// Newest first. Add an entry here with each release.
    static let changelog: [Release] = [
        Release(version: "1.2.2", date: "2026.10.27", notes: [
            "過去の予定を薄く表示する設定",
            "移動・複製・ToDo削除の取り消し",
        ]),
        Release(version: "1.2.1", date: "2026.10.25", notes: [
            "日付・ToDoカテゴリを横スワイプで切り替え",
            "新しいアイコン",
        ]),
        Release(version: "1.2.0", date: "2026.10.24", notes: [
            "ToDo（Appleのリマインダーと同期）とToDoウィジェット",
            "カレンダー上で予定を移動・複製",
            "削除の取り消し",
        ]),
        Release(version: "1.1.0", date: "2026.10.24", notes: [
            "今週の予定ウィジェット",
        ]),
        Release(version: "1.0.0", date: "2026.10.23", notes: [
            "はじめてのリリース",
        ]),
    ]
}
