import SwiftUI

struct ContentView: View {
    @State private var rows: [PlistRow] = []
    @State private var fileName: String = ""
    @State private var errorMessage: String? = nil
    @State private var isFilePickerPresented = false
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if !rows.isEmpty { Divider() }

            if isLoading {
                ProgressView("파일 분석 중...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else if rows.isEmpty {
                emptyState
            } else {
                PlistTableView(rows: rows)
            }
        }
#if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
#endif
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.propertyList],
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
        if !rows.isEmpty {
            HStack(spacing: 8) {
                Button(action: { isFilePickerPresented = true }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("다른 파일 열기")

                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(fileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

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

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Plist 파일을 열어주세요")
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
        isLoading = true
        errorMessage = nil
        fileName = url.lastPathComponent

        let scoped = url.startAccessingSecurityScopedResource()

        DispatchQueue.global(qos: .userInitiated).async {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let parsed = try PlistParser.parse(url: url)
                DispatchQueue.main.async {
                    rows = parsed
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func clearData() {
        rows = []
        fileName = ""
        errorMessage = nil
    }
}

#Preview {
    ContentView()
}
