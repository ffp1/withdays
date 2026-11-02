import SwiftUI

/// Add a category or edit one: a name and an icon (searchable by its English name).
struct MoCategorySheet: View {
    enum Target: Identifiable {
        case new
        case edit(MoCategory)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let category): category.label
            }
        }
    }

    let target: Target
    let kind: MoKind

    @Environment(MoStore.self) private var mo
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var query = ""
    @FocusState private var nameFocused: Bool

    init(target: Target, kind: MoKind) {
        self.target = target
        self.kind = kind
        switch target {
        case .new:
            _name = State(initialValue: "")
            _icon = State(initialValue: MoData.icons[0])
        case .edit(let category):
            _name = State(initialValue: category.label)
            _icon = State(initialValue: category.icon)
        }
    }

    private var original: MoCategory? {
        if case .edit(let category) = target { return category }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("カテゴリ名")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        TextField("ex; 交通費", text: $name)
                            .font(.system(size: 24, weight: .bold))
                            .focused($nameFocused)
                        Rectangle()
                            .fill(kind.color)
                            .frame(height: 2)
                        if isDuplicate {
                            Text("同じ名前のカテゴリがあります")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("アイコンを選択")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("アイコン名を検索", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemFill)))

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(icons, id: \.self) { item in
                                Button { icon = item } label: {
                                    MoIcon(name: item, size: 24)
                                        .foregroundStyle(icon == item ? Color.white : Color.primary)
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(1, contentMode: .fit)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(icon == item ? kind.color : Color(.secondarySystemFill))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(original == nil ? "カテゴリを追加" : "カテゴリを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .tint(kind.color)
                        .disabled(trimmed.isEmpty || isDuplicate)
                }
            }
        }
        .task {
            guard original == nil else { return }
            try? await Task.sleep(for: .milliseconds(350))
            nameFocused = true
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isDuplicate: Bool {
        mo.categories(kind).contains { $0.label == trimmed && $0.label != original?.label }
    }

    /// The current icon stays first while editing, so it's in view.
    private var icons: [String] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = text.isEmpty ? MoData.icons : MoData.icons.filter { $0.contains(text) }
        if text.isEmpty, !list.contains(icon) { list.insert(icon, at: 0) }
        return list
    }

    private func save() {
        let category = MoCategory(label: trimmed, icon: icon)
        if let original {
            mo.updateCategory(original, to: category, kind: kind)
        } else {
            mo.addCategory(category, to: kind)
        }
        dismiss()
    }
}

/// Change a record's amount, category, date or memo. The time of day stays as recorded.
struct MoRecordEditor: View {
    @Environment(MoStore.self) private var mo
    @Environment(\.dismiss) private var dismiss
    @State private var record: MoRecord
    @State private var amount: String

    init(record: MoRecord) {
        _record = State(initialValue: record)
        _amount = State(initialValue: String(record.amount))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("金額") {
                    TextField("0", text: $amount)
                        .keyboardType(.numberPad)
                        .font(MoFormat.number(30))
                        .foregroundStyle(record.kind.color)
                        .onChange(of: amount) { _, new in
                            let filtered = String(new.filter(\.isNumber).prefix(9))
                            if filtered != new { amount = filtered }
                        }
                }
                Section("カテゴリ") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                        ForEach(categories) { category in
                            Button {
                                record.category = category.label
                                record.icon = category.icon
                            } label: {
                                let selected = record.category == category.label
                                VStack(spacing: 4) {
                                    MoIcon(name: category.icon, size: 22)
                                        .foregroundStyle(selected ? Color.white : record.kind.color)
                                        .frame(width: 48, height: 48)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(selected ? record.kind.color : record.kind.color.opacity(0.1))
                                        )
                                    Text(category.label)
                                        .font(.system(size: 11, weight: .bold))
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    DatePicker("日付", selection: dateBinding, displayedComponents: .date)
                    TextField("メモ", text: $record.memo)
                }
            }
            .navigationTitle("記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .tint(record.kind.color)
                        .disabled((Int(amount) ?? 0) <= 0)
                }
            }
        }
    }

    /// A category deleted since stays choosable for its records.
    private var categories: [MoCategory] {
        var list = mo.categories(record.kind)
        if !list.contains(where: { $0.label == record.category }) {
            list.insert(MoCategory(label: record.category, icon: record.icon), at: 0)
        }
        return list
    }

    /// Changing the day keeps the time.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { record.date },
            set: { day in
                let calendar = CalendarMath.calendar
                let time = calendar.dateComponents([.hour, .minute, .second], from: record.date)
                record.date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
            }
        )
    }

    private func save() {
        record.amount = Int(amount) ?? record.amount
        record.memo = record.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        mo.update(record)
        dismiss()
    }
}
