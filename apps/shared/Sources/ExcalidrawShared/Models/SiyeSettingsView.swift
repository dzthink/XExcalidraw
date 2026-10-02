import SwiftUI

public enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
    public var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

public struct SiyeSettingsView: View {
    @AppStorage("siye.appearance") private var appearance = AppearancePreference.system.rawValue
    @State private var directory = EditorPreferences.attachmentDirectory()
    @State private var directoryError: String?
    @State private var saved = false
    @State private var selectedSection = SettingsSection.appearance

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case appearance, editor
        var id: String { rawValue }
        var title: String { self == .appearance ? "外观" : "编辑器" }
        var icon: String { self == .appearance ? "paintpalette" : "pencil" }
    }

    public init() {}

    private var appearanceForm: some View {
        Section("外观") {
            Picker("主题", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { preference in
                    Text(preference.title).tag(preference.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text("应用和编辑画布使用同一外观。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var editorForm: some View {
        Section("编辑器") {
            TextField("附件目录", text: $directory)
                .onSubmit(saveDirectory)
                .onChange(of: directory) { _ in saved = false; directoryError = nil }
            Text("相对于当前文档库，例如 attachments 或 assets/images。仅影响新插入的附件，已有附件保留原路径。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("恢复默认") { directory = EditorPreferences.defaultAttachmentDirectory; saveDirectory() }
                Spacer()
                if saved { Text("已保存").font(.caption).foregroundStyle(.secondary) }
                Button("应用", action: saveDirectory).buttonStyle(.borderedProminent)
            }
            if let directoryError { Text(directoryError).font(.caption).foregroundStyle(.red) }
        }
    }

    private func saveDirectory() {
        guard EditorPreferences.setAttachmentDirectory(directory) else {
            directoryError = "请输入文档库内的相对目录，不能包含 . 或 .. 路径段。"
            return
        }
        directory = EditorPreferences.attachmentDirectory()
        directoryError = nil
        saved = true
    }

    public var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Text("设置").font(.title2.bold()).padding(.horizontal, 12)
                VStack(spacing: 6) {
                    ForEach(SettingsSection.allCases) { section in
                        Button { selectedSection = section } label: {
                            Label(section.title, systemImage: section.icon)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(selectedSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                    }
                }
                Spacer()
            }
            .padding(16)
            .frame(width: 180)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(selectedSection.title).font(.largeTitle.bold())
                    VStack(alignment: .leading, spacing: 16) {
                        if selectedSection == .appearance {
                            appearanceForm
                        } else {
                            editorForm
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 740, height: 460)
        .preferredColorScheme((AppearancePreference(rawValue: appearance) ?? .system).colorScheme)
        #else
        Form { appearanceForm; editorForm }
            .navigationTitle("设置")
            .preferredColorScheme((AppearancePreference(rawValue: appearance) ?? .system).colorScheme)
        #endif
    }
}
