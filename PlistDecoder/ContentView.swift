import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    static var xcodeAppData: UTType {
        UTType(importedAs: "com.apple.dt.xcode.xcappdata", conformingTo: .package)
    }
}

struct ContentView: View {
    @State private var rows: [PlistRow] = []
    @State private var fileName: String = ""
    @State private var plistCandidates: [PlistFileCandidate] = []
    @State private var selectedCandidateID: PlistFileCandidate.ID? = nil
    @State private var errorMessage: String? = nil
    @State private var isFilePickerPresented = false
    @State private var isLoading = false
    @State private var isSidebarVisible = true
    @State private var loadRequestID = UUID()
    @AppStorage("plistDarkMode") private var isDarkMode: Bool = false
    @AppStorage("plistFontSize") private var fontSize: Double = 12
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    #endif

    private var showFontControls: Bool {
        #if os(macOS)
        return true
        #else
        return hSizeClass == .regular || vSizeClass == .compact
        #endif
    }

    private var hasLoadedContent: Bool {
        !rows.isEmpty || !plistCandidates.isEmpty
    }

    private var selectedCandidate: PlistFileCandidate? {
        guard let selectedCandidateID else { return nil }
        return plistCandidates.first { $0.id == selectedCandidateID }
    }

    private var toolbarFileName: String {
        guard let selectedCandidate else { return fileName }
        return "\(fileName) · \(selectedCandidate.fileName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if hasLoadedContent { Divider() }

            if hasLoadedContent {
                loadedContent
            } else if isLoading {
                ProgressView("파일 분석 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                emptyState
            }
        }
#if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
#endif
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.propertyList, .xcodeAppData, .folder, .package],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
#if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
#endif
    }

    @ViewBuilder
    private var toolbar: some View {
        if hasLoadedContent {
            HStack(spacing: 8) {
                Button(action: { isFilePickerPresented = true }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("다른 파일 열기")

                if !plistCandidates.isEmpty {
                    Button(action: toggleSidebar) {
                        Image(systemName: isSidebarVisible ? "sidebar.leading" : "sidebar.left")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isSidebarVisible ? "사이드바 숨기기" : "사이드바 보이기")
                }

                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(toolbarFileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if showFontControls {
                    Divider().frame(height: 16)
                    HStack(spacing: 0) {
                        Button(action: { fontSize = max(8, fontSize - 1) }) {
                            Image(systemName: "minus")
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(fontSize <= 8)
                        Image(systemName: "textformat.size")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        Button(action: { fontSize = min(20, fontSize + 1) }) {
                            Image(systemName: "plus")
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(fontSize >= 20)
                    }
                }

                Spacer()

                Button(action: { isDarkMode.toggle() }) {
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isDarkMode ? "라이트 모드로 전환" : "다크 모드로 전환")

                #if os(macOS)
                Divider().frame(height: 16)
                #endif

                Text("\(rows.count)개 항목")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: clearData) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("초기화")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var loadedContent: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if !plistCandidates.isEmpty && isSidebarVisible {
                    PlistSidebarView(
                        candidates: plistCandidates,
                        selectedCandidateID: selectedCandidateID,
                        onSelect: selectPlist
                    )
                    .frame(width: sidebarWidth(totalWidth: proxy.size.width))

                    Divider()
                }

                plistContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var plistContent: some View {
        Group {
            if isLoading {
                ProgressView("파일 분석 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else if rows.isEmpty {
                Text("선택한 plist에 표시할 항목이 없습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PlistTableView(rows: rows)
                    .environment(\.plistFontSize, fontSize)
            }
        }
    }

    private func sidebarWidth(totalWidth: CGFloat) -> CGFloat {
        #if os(iOS)
        if hSizeClass == .compact {
            return min(260, max(180, totalWidth - 64))
        }
        #endif

        return min(300, max(240, totalWidth * 0.32))
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: { isDarkMode.toggle() }) {
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isDarkMode ? "라이트 모드로 전환" : "다크 모드로 전환")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(spacing: 20) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 64))
                    .foregroundStyle(.secondary)
                Text("Plist 또는 xcappdata를 열어주세요")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("파일을 드래그 앤 드롭하거나 아래 버튼으로 선택하세요")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("파일 선택") {
                    isFilePickerPresented = true
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("파일을 읽을 수 없습니다")
                .font(.title3.bold())
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("다시 시도") {
                errorMessage = nil
                isFilePickerPresented = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadFile(url: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

#if os(macOS)
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                loadFile(url: url)
            }
        }
        return true
    }
#endif

    private func loadFile(url: URL) {
        let requestID = UUID()
        loadRequestID = requestID
        isLoading = true
        errorMessage = nil
        fileName = url.lastPathComponent
        rows = []
        plistCandidates = []
        selectedCandidateID = nil

        let scoped = url.startAccessingSecurityScopedResource()

        DispatchQueue.global(qos: .userInitiated).async {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let result = try PlistDocumentLoader.load(url: url)
                DispatchQueue.main.async {
                    guard loadRequestID == requestID else { return }
                    fileName = result.sourceName
                    rows = result.rows
                    plistCandidates = result.candidates
                    selectedCandidateID = result.selectedCandidateID
                    isSidebarVisible = !result.candidates.isEmpty
                    errorMessage = result.initialErrorMessage
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard loadRequestID == requestID else { return }
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func selectPlist(_ candidate: PlistFileCandidate) {
        guard selectedCandidateID != candidate.id else { return }

        let requestID = UUID()
        loadRequestID = requestID
        selectedCandidateID = candidate.id
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let parsed = try PlistDocumentLoader.parse(candidate: candidate)
                DispatchQueue.main.async {
                    guard loadRequestID == requestID else { return }
                    rows = parsed
                    errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    guard loadRequestID == requestID else { return }
                    rows = []
                    errorMessage = "\(candidate.relativePath)을 읽을 수 없습니다: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearData() {
        rows = []
        fileName = ""
        plistCandidates = []
        selectedCandidateID = nil
        errorMessage = nil
        isLoading = false
        isSidebarVisible = true
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSidebarVisible.toggle()
        }
    }
}

private struct PlistSidebarView: View {
    let candidates: [PlistFileCandidate]
    let selectedCandidateID: PlistFileCandidate.ID?
    let onSelect: (PlistFileCandidate) -> Void

    private var recommendedCandidate: PlistFileCandidate? {
        candidates.first { $0.isRecommended }
    }

    private var otherCandidates: [PlistFileCandidate] {
        candidates.filter { !$0.isRecommended }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("plist 목록")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(candidates.count)개")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let recommendedCandidate {
                        sectionTitle("추천")
                        candidateButton(recommendedCandidate, isHighlighted: true)
                    }

                    if !otherCandidates.isEmpty {
                        sectionTitle("다른 plist")
                        ForEach(otherCandidates) { candidate in
                            candidateButton(candidate, isHighlighted: false)
                        }
                    }
                }
                .padding(.trailing, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.secondary.opacity(0.06))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func candidateButton(_ candidate: PlistFileCandidate, isHighlighted: Bool) -> some View {
        let isSelected = selectedCandidateID == candidate.id

        return Button {
            onSelect(candidate)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : (isHighlighted ? "star.fill" : "doc.text"))
                        .foregroundStyle(isSelected || isHighlighted ? Color.accentColor : Color.secondary)
                        .frame(width: 18)

                    HStack(spacing: 6) {
                        Text(candidate.fileName)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if isHighlighted {
                            Text(candidate.recommendationReason ?? "추천")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.18))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(candidate.relativePath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(candidate.sizeDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor(isSelected: isSelected, isHighlighted: isHighlighted))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor(isSelected: isSelected, isHighlighted: isHighlighted), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(candidate.relativePath)
    }

    private func backgroundColor(isSelected: Bool, isHighlighted: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHighlighted {
            return Color.accentColor.opacity(0.08)
        }
        return Color.primary.opacity(0.035)
    }

    private func borderColor(isSelected: Bool, isHighlighted: Bool) -> Color {
        if isSelected || isHighlighted {
            return Color.accentColor.opacity(isSelected ? 0.6 : 0.35)
        }
        return Color.secondary.opacity(0.18)
    }
}

#Preview {
    ContentView()
}
