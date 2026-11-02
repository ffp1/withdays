import SwiftUI

/// Mo's records and categories, saved through `MoData` after every change.
@MainActor
@Observable
final class MoStore {
    private(set) var state = MoData.load()

    var records: [MoRecord] { state.records }

    func categories(_ kind: MoKind) -> [MoCategory] {
        kind == .expense ? state.expenseCategories : state.incomeCategories
    }

    // MARK: Records

    @discardableResult
    func add(amount: Int, kind: MoKind, category: MoCategory, memo: String, date: Date = .now) -> MoRecord {
        let record = MoRecord(id: MoData.newID(), amount: amount, kind: kind, category: category.label, icon: category.icon, memo: memo, date: date)
        state.records.append(record)
        persist()
        return record
    }

    func update(_ record: MoRecord) {
        guard let index = state.records.firstIndex(where: { $0.id == record.id }) else { return }
        state.records[index] = record
        persist()
    }

    /// Removes a record; returns what undo needs to put it back.
    func delete(_ id: String) -> (record: MoRecord, index: Int)? {
        guard let index = state.records.firstIndex(where: { $0.id == id }) else { return nil }
        let record = state.records.remove(at: index)
        persist()
        return (record, index)
    }

    func restore(_ record: MoRecord, at index: Int) {
        state.records.insert(record, at: min(index, state.records.count))
        persist()
    }

    /// Newest first.
    func records(on day: Date) -> [MoRecord] {
        state.records.filter { CalendarMath.isSameDay($0.date, day) }.sorted { $0.date > $1.date }
    }

    func records(from start: Date, to end: Date) -> [MoRecord] {
        state.records.filter { $0.date >= start && $0.date < end }
    }

    /// Expense and income totals per day for [start, end).
    func dailyTotals(from start: Date, to end: Date) -> [Date: (expense: Int, income: Int)] {
        var totals: [Date: (expense: Int, income: Int)] = [:]
        for record in state.records where record.date >= start && record.date < end {
            let day = CalendarMath.startOfDay(record.date)
            var total = totals[day] ?? (0, 0)
            if record.kind == .expense { total.expense += record.amount } else { total.income += record.amount }
            totals[day] = total
        }
        return totals
    }

    // MARK: Categories

    /// New categories go before その他 when it's last, as on the web app.
    func addCategory(_ category: MoCategory, to kind: MoKind) {
        mutateCategories(kind) { list in
            let other = list.firstIndex { $0.label == "その他" }
            let index = other == list.count - 1 ? other! : list.count
            list.insert(category, at: index)
        }
    }

    /// Renaming or changing the icon follows into past records, so the totals don't split.
    func updateCategory(_ old: MoCategory, to new: MoCategory, kind: MoKind) {
        mutateCategories(kind) { list in
            guard let index = list.firstIndex(of: old) else { return }
            list[index] = new
        }
        guard old != new else { return }
        for index in state.records.indices where state.records[index].kind == kind && state.records[index].category == old.label {
            state.records[index].category = new.label
            state.records[index].icon = new.icon
        }
        persist()
    }

    func moveCategories(_ kind: MoKind, from offsets: IndexSet, to destination: Int) {
        mutateCategories(kind) { list in list.move(fromOffsets: offsets, toOffset: destination) }
    }

    /// Records in them stay as they are.
    func deleteCategories(_ kind: MoKind, at offsets: IndexSet) {
        mutateCategories(kind) { list in list.remove(atOffsets: offsets) }
    }

    private func mutateCategories(_ kind: MoKind, _ change: (inout [MoCategory]) -> Void) {
        if kind == .expense { change(&state.expenseCategories) } else { change(&state.incomeCategories) }
        persist()
    }

    private func persist() {
        MoData.save(state)
    }
}
