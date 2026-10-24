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
        Release(version: "1.0.0", date: "2026.10.23", notes: [
            "はじめてのリリース",
            "Appleのカレンダーと同期する月表示カレンダー",
            "予定の追加・編集・移動・複製、くりかえし予定",
            "テンプレートを日付にドラッグして予定を追加",
            "タイトル・場所・メモで予定を検索",
            "今週の予定を表示するウィジェット",
            "Appleのリマインダーと同期するToDo（カテゴリ・サブタスク・ウィジェット）",
            "予定の移動・複製をカレンダー上で直接選択、削除の取り消し",
        ]),
    ]
}
