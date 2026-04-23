import SwiftUI

#if os(iOS)
private let typeColumnWidth: CGFloat = 72
#else
private let typeColumnWidth: CGFloat = 90
#endif

struct PlistFontSizeKey: EnvironmentKey {
    static let defaultValue: Double = 12
}

extension EnvironmentValues {
    var plistFontSize: Double {
        get { self[PlistFontSizeKey.self] }
        set { self[PlistFontSizeKey.self] = newValue }
    }
}

struct PlistTableView: View {
    let rows: [PlistRow]
    @State private var expandedPaths: Set<String> = ["Root"]
    @State private var searchText = ""
    @State private var includeChildren = false

    private func rowId(_ row: PlistRow) -> String {
        (row.keyPath + [row.key]).joined(separator: ".")
    }

    private var matchedIds: Set<String> {
        guard !searchText.isEmpty else { return [] }
        var ids = Set<String>()
        for row in rows {
            if row.key.localizedCaseInsensitiveContains(searchText) ||
               row.value.valueDescription.localizedCaseInsensitiveContains(searchText) ||
               row.value.typeDescription.localizedCaseInsensitiveContains(searchText) {
                ids.insert(rowId(row))
            }
        }
        return ids
    }

    private var visibleRows: [PlistRow] {
        if searchText.isEmpty {
            return filteredByExpansion(rows)
        }
        let matched = matchedIds
        if includeChildren {
            // 매칭된 행 + 그 하위 행 모두 포함
            return rows.filter { row in
                let id = rowId(row)
                if matched.contains(id) { return true }
                // 이 row의 상위 경로 중 매칭된 것이 있으면 포함
                var path: [String] = []
                for segment in row.keyPath {
                    path.append(segment)
                    if matched.contains(path.joined(separator: ".")) { return true }
                }
                return false
            }
        } else {
            return rows.filter { matched.contains(rowId($0)) }
        }
    }

    private func filteredByExpansion(_ rows: [PlistRow]) -> [PlistRow] {
        var result: [PlistRow] = []
        for row in rows {
            if row.depth == 0 {
                result.append(row)
            } else if isVisible(row) {
                result.append(row)
            }
        }
        return result
    }

    private func isVisible(_ row: PlistRow) -> Bool {
        var path: [String] = []
        for segment in row.keyPath {
            path.append(segment)
            if !expandedPaths.contains(path.joined(separator: ".")) {
                return false
            }
        }
        return true
    }

    private func toggleExpand(_ row: PlistRow) {
        let id = rowId(row)
        if expandedPaths.contains(id) {
            expandedPaths = expandedPaths.filter { !$0.hasPrefix(id) }
        } else {
            expandedPaths.insert(id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Key")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                Divider()
                Text("Type")
                    .font(.caption.bold())
                    .frame(width: typeColumnWidth, alignment: .leading)
                    .padding(.horizontal, 8)
                Divider()
                Text("Value")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
            .frame(height: 28)
            .background(Color.secondary.opacity(0.15))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleRows) { row in
                        PlistRowView(
                            row: row,
                            isExpanded: expandedPaths.contains(rowId(row)),
                            onToggle: { toggleExpand(row) }
                        )
                        Divider()
                            .opacity(0.3)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "키 또는 값 검색")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !searchText.isEmpty {
                    Button {
                        includeChildren.toggle()
                    } label: {
                        Label(
                            includeChildren ? "하위 항목 포함" : "하위 항목 제외",
                            systemImage: includeChildren ? "list.bullet.indent" : "list.bullet"
                        )
                        .foregroundColor(includeChildren ? .accentColor : .secondary)
                    }
                    .help(includeChildren ? "하위 항목 표시 끄기" : "일치 키의 하위 항목도 표시")
                }
            }
        }
    }
}

// MARK: - Data Inspector

struct DataInspectorView: View {
    let data: Data
    @State private var selectedTab = 0
    @Environment(\.plistFontSize) private var fontSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    #endif

    private var useCustomFont: Bool {
        #if os(macOS)
        return true
        #else
        return hSizeClass == .regular || vSizeClass == .compact
        #endif
    }

    private var monoFont: Font {
        useCustomFont
            ? .system(size: fontSize, design: .monospaced)
            : .system(.caption, design: .monospaced)
    }

    private var isBplist: Bool {
        data.count >= 8 && data.prefix(8) == Data("bplist00".utf8)
    }

    private var nestedPlistRows: [PlistRow]? {
        try? PlistParser.parse(data: data)
    }

    private var hexDump: String {
        let bytesPerRow = 16
        var lines: [String] = []
        for offset in stride(from: 0, to: data.count, by: bytesPerRow) {
            let rowData = data[offset..<min(offset + bytesPerRow, data.count)]
            let hex = rowData.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = rowData.map { byte -> Character in
                let c = Character(UnicodeScalar(byte))
                return c.isASCII && !c.isWhitespace && byte >= 0x20 && byte < 0x7F ? c : "."
            }
            let hexPadded = hex.padding(toLength: bytesPerRow * 3 - 1, withPad: " ", startingAt: 0)
            lines.append(String(format: "%08X  %@  %@", offset, hexPadded, String(ascii)))
        }
        return lines.joined(separator: "\n")
    }

    private var utf8String: String? {
        String(data: data, encoding: .utf8)
    }

    private var base64String: String {
        data.base64EncodedString(options: .lineLength64Characters)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(data.count) bytes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isBplist {
                    Text("bplist")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Picker("", selection: $selectedTab) {
                if nestedPlistRows != nil { Text("Plist").tag(0) }
                Text("Hex").tag(1)
                Text("Base64").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(8)
            .onAppear {
                if nestedPlistRows != nil { selectedTab = 0 } else { selectedTab = 1 }
            }

            Divider()

            Group {
                switch selectedTab {
                case 0:
                    if let rows = nestedPlistRows {
                        PlistTableView(rows: rows)
                    } else {
                        Text("Plist 파싱 실패")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case 1:
                    ScrollView([.horizontal, .vertical]) {
                        Text(hexDump)
                            .font(monoFont)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                default:
                    ScrollView(.vertical) {
                        Text(base64String)
                            .font(monoFont)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Spacer()
                if selectedTab != 0 {
                    Button("복사") {
                        let text: String
                        switch selectedTab {
                        case 1: text = hexDump
                        default: text = base64String
                        }
#if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
#else
                        UIPasteboard.general.string = text
#endif
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(8)
        }
#if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
#else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
    }
}

// MARK: - Row View

struct PlistRowView: View {
    let row: PlistRow
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isCopied = false
    @State private var showDataInspector = false
    @Environment(\.plistFontSize) private var fontSize
    @AppStorage("plistDarkMode") private var isDarkMode: Bool = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    #endif

    private var useCustomFont: Bool {
        #if os(macOS)
        return true
        #else
        return hSizeClass == .regular || vSizeClass == .compact
        #endif
    }

    private var monoFont: Font {
        useCustomFont
            ? .system(size: fontSize, design: .monospaced)
            : .system(.caption, design: .monospaced)
    }

    private var typeFont: Font {
        useCustomFont ? .system(size: fontSize) : .caption
    }

    private var chevronFont: Font {
        useCustomFont ? .system(size: max(8, fontSize - 2)) : .caption2
    }

    var body: some View {
        HStack(spacing: 0) {
            // Key column
            HStack(spacing: 4) {
                if row.depth > 0 {
                    Spacer().frame(width: CGFloat(row.depth) * 16)
                }
                if row.value.isContainer {
                    Button(action: onToggle) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(chevronFont)
                            .frame(width: 12, height: 12)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 14)
                }

                Text(row.key)
                    .font(monoFont)
                    .foregroundStyle(keyColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if row.value.isContainer { onToggle() } }

            Divider()

            // Type column
            Text(row.value.typeDescription)
                .font(typeFont)
                .foregroundStyle(typeColor)
                .frame(width: typeColumnWidth, alignment: .leading)
                .padding(.horizontal, 8)

            Divider()

            // Value column
            HStack {
                Text(row.value.valueDescription)
                    .font(monoFont)
                    .foregroundStyle(valueColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if case .data = row.value {
                    Button(action: { showDataInspector = true }) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("데이터 내용 보기")
#if os(macOS)
                    .popover(isPresented: $showDataInspector) {
                        if case .data(let d) = row.value {
                            DataInspectorView(data: d)
                        }
                    }
#else
                    .sheet(isPresented: $showDataInspector) {
                        if case .data(let d) = row.value {
                            NavigationView {
                                DataInspectorView(data: d)
                                    .navigationTitle("Data Inspector")
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                        ToolbarItem(placement: .navigationBarTrailing) {
                                            Button("닫기") { showDataInspector = false }
                                        }
                                    }
                            }
                            .preferredColorScheme(isDarkMode ? .dark : .light)
                        }
                    }
#endif
                } else if !row.value.isContainer {
                    Button(action: copyValue) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(isCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("값 복사")
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 28)
        .background(rowBackground)
    }

    private var rowBackground: Color {
        row.depth % 2 == 0 ? Color.clear : Color.secondary.opacity(0.04)
    }

    private var keyColor: Color {
        row.value.isContainer ? .accentColor : .primary
    }

    private var typeColor: Color {
        switch row.value {
        case .string: return .green
        case .integer, .real: return .blue
        case .bool: return .orange
        case .date: return .purple
        case .data: return .gray
        case .array, .dictionary: return .accentColor
        }
    }

    private var valueColor: Color {
        switch row.value {
        case .bool(let v): return v ? .green : .red
        default: return .secondary
        }
    }

    private func copyValue() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.value.valueDescription, forType: .string)
#else
        UIPasteboard.general.string = row.value.valueDescription
#endif
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { isCopied = false }
        }
    }
}
