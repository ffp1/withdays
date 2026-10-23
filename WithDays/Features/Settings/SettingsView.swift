import EventKit
import SwiftUI

struct SettingsView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(TemplateStore.self) private var templates
    @AppStorage(SettingsKey.theme) private var theme = AppTheme.system.rawValue
    @AppStorage(SettingsKey.weekStart) private var weekStart = 1

    var body: some View {
        List {
            Section("表示") {
                Picker("テーマ", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("週の始まり", selection: $weekStart) {
                    Text("日曜日").tag(1)
                    Text("月曜日").tag(2)
                }
            }

            Section {
                NavigationLink {
                    CalendarVisibilityView()
                } label: {
                    LabeledContent("表示するカレンダー", value: "\(store.visibleCalendars.count)/\(store.displayableCalendars.count)")
                }
                Picker("新しい予定のカレンダー", selection: defaultCalendarBinding) {
                    Text("システムの設定").tag("")
                    ForEach(store.writableCalendars, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(calendar.calendarIdentifier)
                    }
                }
                Picker("祝日カレンダー", selection: holidayCalendarBinding) {
                    Text("自動").tag("")
                    ForEach(store.calendars.filter { !$0.allowsContentModifications }, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(calendar.calendarIdentifier)
                    }
                }
            } header: {
                Text("カレンダー")
            } footer: {
                if let holiday = store.holidayCalendar {
                    Text("「\(holiday.title)」の日付を赤く表示します。祝日は予定としては表示しません。")
                } else {
                    Text("祝日カレンダーが見つかりません。iPhoneの「カレンダー」アプリのカレンダー一覧で「日本の祝日」を追加すると、祝日が赤く表示されます。")
                }
            }

            Section("テンプレート") {
                NavigationLink {
                    TemplateListView()
                } label: {
                    LabeledContent("テンプレート", value: "\(templates.templates.count)件")
                }
            }

            Section {
                LabeledContent("カレンダーへのアクセス", value: store.access == .granted ? "フルアクセス" : "なし")
                Button("iPhoneの設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                Text("同期")
            } footer: {
                Text("予定は Appleのカレンダーに直接保存され、iCloud を通じて他のデバイスと同期されます。")
            }

            Section("WithDays について") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppInfo.name)
                        .font(.system(size: 17, weight: .bold))
                    Text(AppInfo.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                LabeledContent("バージョン", value: "\(AppInfo.version) (\(AppInfo.build))")
                NavigationLink("更新履歴") { ChangelogView() }
                Link(destination: AppInfo.repositoryURL) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var defaultCalendarBinding: Binding<String> {
        Binding(get: { store.defaultCalendarID }, set: { store.defaultCalendarID = $0 })
    }

    private var holidayCalendarBinding: Binding<String> {
        Binding(get: { store.holidayCalendarID }, set: { store.holidayCalendarID = $0 })
    }
}

private struct CalendarVisibilityView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        List {
            ForEach(store.grouped(store.displayableCalendars)) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: binding(for: calendar.calendarIdentifier)) {
                            HStack(spacing: 10) {
                                CalendarDot(color: Color(cgColor: calendar.cgColor))
                                Text(calendar.title)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("表示するカレンダー")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !store.hiddenCalendarIDs.contains(id) },
            set: { visible in
                if visible { store.hiddenCalendarIDs.remove(id) } else { store.hiddenCalendarIDs.insert(id) }
            }
        )
    }
}

private struct TemplateListView: View {
    @Environment(TemplateStore.self) private var templates
    @State private var editing: EditorMode?

    var body: some View {
        List {
            ForEach(templates.templates) { template in
                Button { editing = .template(template) } label: {
                    Text(template.draft.title).foregroundStyle(.primary)
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { templates.templates[$0].id }
                for id in ids { templates.delete(id: id) }
            }
            .onMove { templates.move(from: $0, to: $1) }

            Button {
                editing = .template(nil)
            } label: {
                Label("テンプレートを登録", systemImage: "plus")
            }
        }
        .toolbar { EditButton() }
        .navigationTitle("テンプレート")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { mode in
            EventEditorView(mode: mode)
        }
    }
}

private struct ChangelogView: View {
    var body: some View {
        List(AppInfo.changelog) { release in
            Section {
                ForEach(release.notes, id: \.self) { Text($0).font(.system(size: 14)) }
            } header: {
                HStack {
                    Text(release.version)
                    Spacer()
                    Text(release.date)
                }
            }
        }
        .navigationTitle("更新履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}
