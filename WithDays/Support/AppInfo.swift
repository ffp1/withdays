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
        Release(version: "1.0.5", date: "2026.10.25", notes: [
            "リストのスワイプ操作（削除・編集など）を修正",
            "日付を離れて移動してもリストがスクロール",
        ]),
        Release(version: "1.0.4", date: "2026.10.24", notes: [
            "新しいアイコン",
            "予定やToDoの行のスワイプがページ送りと衝突しないように",
        ]),
        Release(version: "1.0.3", date: "2026.10.24", notes: [
            "日付・ToDoカテゴリを横スワイプでページ送り",
            "移動・複製時にカレンダーを拡大",
            "動きと見た目の細かな調整",
        ]),
        Release(version: "1.0.2", date: "2026.10.24", notes: [
            "ToDo（Appleのリマインダーと同期）",
            "ToDoウィジェット",
            "カレンダー上で予定を移動・複製",
            "削除の取り消し",
        ]),
        Release(version: "1.0.1", date: "2026.10.24", notes: [
            "今週の予定ウィジェット",
            "表示の調整",
        ]),
        Release(version: "1.0.0", date: "2026.10.23", notes: [
            "はじめてのリリース",
        ]),
    ]
}
