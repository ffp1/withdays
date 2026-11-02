import Foundation

enum AppInfo {
    static let name = "WithDays"
    static let summary = "WithDays は、Appleのカレンダーの予定をそのまま読み書きする月表示のカレンダーです。iPhone や Mac のカレンダーと自動で同期されます。"
    static let repositoryURL = URL(string: "https://github.com/ffuime/withdays")!

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
        Release(version: "1.3.2", date: "2026.11.02", notes: [
            "カレンダーの編集（右スワイプ）",
            "Go：長押しでプリセット、上下スワイプで画面の明るさ",
        ]),
        Release(version: "1.3.1", date: "2026.11.01", notes: [
            "Go：＋ボタン長押しで、駅までの経路から乗る電車の発車時刻をプリセットに",
        ]),
        Release(version: "1.3.0", date: "2026.11.01", notes: [
            "Go：次の目標時刻までのカウントダウン（＋ボタン長押しで開く）",
            "Goのロック画面ウィジェット（タップでGoを開く）",
            "Go表示中は自動ロックしない",
        ]),
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
