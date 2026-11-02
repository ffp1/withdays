import SwiftUI

/// Mo (household budget): expenses and income, each with its own categories.
enum MoKind: String, Codable, CaseIterable {
    case expense, income

    var label: String { self == .expense ? "支出" : "収入" }
    /// Red for money going out, green for money coming in (as on the web app).
    var color: Color { self == .expense ? .moExpense : .moIncome }
}

struct MoCategory: Codable, Equatable, Hashable, Identifiable {
    var label: String
    /// An icon asset name under MoIcons.
    var icon: String

    var id: String { label }
}

struct MoRecord: Codable, Equatable, Identifiable {
    var id: String
    var amount: Int
    var kind: MoKind
    /// The category is copied in, so records keep their name and icon after it's renamed away or deleted.
    var category: String
    var icon: String
    var memo: String
    var date: Date
}

struct MoState: Codable, Equatable {
    var records: [MoRecord] = []
    var expenseCategories: [MoCategory] = MoState.defaultCategories(.expense)
    var incomeCategories: [MoCategory] = MoState.defaultCategories(.income)

    static func defaultCategories(_ kind: MoKind) -> [MoCategory] {
        switch kind {
        case .expense:
            [
                MoCategory(label: "食事", icon: "mo-meal"),
                MoCategory(label: "日用品", icon: "mo-daily"),
                MoCategory(label: "趣味", icon: "mo-hobby"),
                MoCategory(label: "その他", icon: "more"),
            ]
        case .income:
            [
                MoCategory(label: "給与", icon: "mo-salary"),
                MoCategory(label: "臨時収入", icon: "mo-bonus"),
                MoCategory(label: "その他", icon: "more"),
            ]
        }
    }
}

/// Saved as one JSON file in the App Group container (or the app's own documents without one).
enum MoData {
    private static var url: URL {
        let base = AppGroup.identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appending(path: "mo.json")
    }

    static func load() -> MoState {
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(MoState.self, from: data) else {
            return MoState()
        }
        return state
    }

    static func save(_ state: MoState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func newID() -> String {
        "record-\(UUID().uuidString)"
    }

    /// The category icons to choose from, by asset name (searchable in English).
    static let icons = [
        "airplane", "armchair", "atom", "baby", "ball", "bank", "bed", "beer", "book-open", "book", "bot", "cake",
        "camera", "candy", "car", "carrot", "cat", "coffee", "coin", "cookie", "credit-card", "diamond", "dices", "dog",
        "dome", "dumbbell", "earth", "education", "electronicity", "face", "fire", "fish", "flower", "footprints",
        "gamepad", "gasoline", "gift", "glasses", "group", "guitar", "hamburger", "hand-coins", "handbag", "headphones",
        "health", "heart", "hospital", "hotel", "house", "juice", "laptop", "library", "martini", "medical-bag", "mic",
        "microwave", "mirror", "money", "monitor", "more", "motorbike", "movie", "music", "pair", "parking", "pen",
        "phone", "piano", "piggy-bank", "pill", "present", "question", "raidio", "roller-coaster", "school", "scissors",
        "shirt", "shopping-bag", "shopping-cart", "sightseeing", "smartphone", "smoking", "soap", "star", "store",
        "ticket", "toilet", "toothbrush", "towel", "track", "train", "trash", "utensils", "video", "wallet",
        "washing-machine", "watch", "water", "wi-fi", "wine", "yen",
    ]
}

extension Color {
    static let moExpense = Color(uiColor: UIColor(light: 0xDC2626, dark: 0xF05252))
    static let moIncome = Color(uiColor: UIColor(light: 0x16A34A, dark: 0x31C463))
}

/// A category icon from the bundled set.
struct MoIcon: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Image("MoIcons/\(name)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

enum MoFormat {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()

    /// 12,345
    static func amount(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// The rounded font of the web app, for amounts and the keypad.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Baloo Bhai 2", size: size).weight(weight)
    }
}
