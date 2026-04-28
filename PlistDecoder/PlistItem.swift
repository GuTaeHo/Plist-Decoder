import Foundation

enum PlistValue {
    case string(String)
    case integer(Int)
    case real(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case array([PlistValue])
    case dictionary([String: PlistValue])

    var typeDescription: String {
        switch self {
        case .string: return "String"
        case .integer: return "Integer"
        case .real: return "Real"
        case .bool: return "Boolean"
        case .date: return "Date"
        case .data: return "Data"
        case .array: return "Array"
        case .dictionary: return "Dictionary"
        }
    }

    var valueDescription: String {
        switch self {
        case .string(let v): return v
        case .integer(let v): return "\(v)"
        case .real(let v): return String(format: "%g", v)
        case .bool(let v): return v ? "true" : "false"
        case .date(let v):
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .medium
            return f.string(from: v)
        case .data(let v): return "<\(v.count) bytes>"
        case .array(let v): return "(\(v.count) items)"
        case .dictionary(let v): return "{\(v.count) keys}"
        }
    }

    var isContainer: Bool {
        switch self {
        case .array, .dictionary: return true
        default: return false
        }
    }
}

struct PlistRow: Identifiable {
    let id = UUID()
    let keyPath: [String]
    let key: String
    let value: PlistValue
    var isExpanded: Bool = false

    var depth: Int { keyPath.count }
    var displayKey: String { key }
}

struct PlistFileCandidate: Identifiable, Equatable {
    let id: String
    let relativePath: String
    let data: Data
    let isRecommended: Bool
    let matchedBundleIdentifier: String?
    let recommendationReason: String?

    var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }

    var plistBaseName: String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    var isAppPreferencesPlist: Bool {
        let parts = relativePath.split(separator: "/").map(String.init)
        return parts.count >= 4
            && parts[0] == "AppData"
            && parts[1] == "Library"
            && parts[2] == "Preferences"
            && fileName.lowercased().hasSuffix(".plist")
    }
}

struct PlistLoadResult {
    let sourceName: String
    let rows: [PlistRow]
    let candidates: [PlistFileCandidate]
    let selectedCandidateID: PlistFileCandidate.ID?
    let initialErrorMessage: String?
}

enum PlistLoadError: LocalizedError {
    case noPlistFiles(URL)

    var errorDescription: String? {
        switch self {
        case .noPlistFiles(let url):
            return "\(url.lastPathComponent) 안에서 .plist 파일을 찾을 수 없습니다."
        }
    }
}

class PlistParser {
    static func parse(url: URL) throws -> [PlistRow] {
        let data = try Data(contentsOf: url)
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        var rows: [PlistRow] = []
        flatten(obj: obj, keyPath: [], key: "Root", into: &rows)
        return rows
    }

    static func parse(data: Data) throws -> [PlistRow] {
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        var rows: [PlistRow] = []
        flatten(obj: obj, keyPath: [], key: "Root", into: &rows)
        return rows
    }

    private static func flatten(obj: Any, keyPath: [String], key: String, into rows: inout [PlistRow]) {
        let value = toPlistValue(obj)
        let row = PlistRow(keyPath: keyPath, key: key, value: value)
        rows.append(row)
        switch value {
        case .dictionary(let dict):
            let sorted = dict.keys.sorted()
            for k in sorted {
                flatten(obj: (obj as! [String: Any])[k]!, keyPath: keyPath + [key], key: k, into: &rows)
            }
        case .array:
            let raw = obj as! [Any]
            for (i, item) in raw.enumerated() {
                flatten(obj: item, keyPath: keyPath + [key], key: "[\(i)]", into: &rows)
            }
        default:
            break
        }
    }

    private static func toPlistValue(_ obj: Any) -> PlistValue {
        switch obj {
        case let v as String: return .string(v)
        case let v as Int: return .integer(v)
        case let v as Double: return .real(v)
        case let v as Bool: return .bool(v)
        case let v as Date: return .date(v)
        case let v as Data: return .data(v)
        case let v as [Any]: return .array(v.map { toPlistValue($0) })
        case let v as [String: Any]: return .dictionary(v.mapValues { toPlistValue($0) })
        default: return .string(String(describing: obj))
        }
    }
}

enum PlistDocumentLoader {
    static func load(url: URL) throws -> PlistLoadResult {
        if try isDirectory(url) {
            return try loadContainer(url: url)
        }

        let data = try Data(contentsOf: url)
        let rows = try PlistParser.parse(data: data)
        return PlistLoadResult(
            sourceName: url.lastPathComponent,
            rows: rows,
            candidates: [],
            selectedCandidateID: nil,
            initialErrorMessage: nil
        )
    }

    static func parse(candidate: PlistFileCandidate) throws -> [PlistRow] {
        try PlistParser.parse(data: candidate.data)
    }

    private static func loadContainer(url: URL) throws -> PlistLoadResult {
        let rawCandidates = try collectPlistCandidates(in: url)
        guard !rawCandidates.isEmpty else {
            throw PlistLoadError.noPlistFiles(url)
        }

        let detectedBundleIdentifiers = bundleIdentifiers(in: rawCandidates)
        let candidates = markRecommendedCandidate(
            rawCandidates,
            detectedBundleIdentifiers: detectedBundleIdentifiers
        )
        let selectedCandidate = initialCandidate(from: candidates)

        var rows: [PlistRow] = []
        var initialErrorMessage: String?
        if let selectedCandidate {
            do {
                rows = try parse(candidate: selectedCandidate)
            } catch {
                initialErrorMessage = "\(selectedCandidate.relativePath)을 읽을 수 없습니다: \(error.localizedDescription)"
            }
        }

        return PlistLoadResult(
            sourceName: url.lastPathComponent,
            rows: rows,
            candidates: candidates,
            selectedCandidateID: selectedCandidate?.id,
            initialErrorMessage: initialErrorMessage
        )
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private static func collectPlistCandidates(in rootURL: URL) throws -> [PlistFileCandidate] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [PlistFileCandidate] = []
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            guard values.isRegularFile == true,
                  fileURL.pathExtension.lowercased() == "plist" else { continue }

            let data = try Data(contentsOf: fileURL)
            let relativePath = relativePath(from: rootURL, to: fileURL)
            candidates.append(
                PlistFileCandidate(
                    id: relativePath,
                    relativePath: relativePath,
                    data: data,
                    isRecommended: false,
                    matchedBundleIdentifier: nil,
                    recommendationReason: nil
                )
            )
        }

        return candidates.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func relativePath(from rootURL: URL, to fileURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return fileURL.lastPathComponent
    }

    private static func markRecommendedCandidate(
        _ candidates: [PlistFileCandidate],
        detectedBundleIdentifiers: Set<String>
    ) -> [PlistFileCandidate] {
        let preferencesCandidates = candidates.filter(\.isAppPreferencesPlist)
        let exactMatch = preferencesCandidates.first {
            detectedBundleIdentifiers.contains($0.plistBaseName)
        }

        let fallbackMatch: PlistFileCandidate?
        if exactMatch == nil {
            let appLikePreferences = preferencesCandidates.filter {
                !$0.plistBaseName.hasPrefix("com.apple.")
                    && !$0.plistBaseName.hasPrefix(".")
            }
            fallbackMatch = appLikePreferences.count == 1 ? appLikePreferences.first : nil
        } else {
            fallbackMatch = nil
        }

        let recommendedID = exactMatch?.id ?? fallbackMatch?.id
        return candidates.map { candidate in
            let isRecommended = candidate.id == recommendedID
            let matchedBundleIdentifier = exactMatch?.id == candidate.id ? candidate.plistBaseName : nil
            let reason = matchedBundleIdentifier != nil ? "Bundle ID 일치" : (isRecommended ? "Preferences 후보" : nil)
            return PlistFileCandidate(
                id: candidate.id,
                relativePath: candidate.relativePath,
                data: candidate.data,
                isRecommended: isRecommended,
                matchedBundleIdentifier: matchedBundleIdentifier,
                recommendationReason: reason
            )
        }
    }

    private static func initialCandidate(from candidates: [PlistFileCandidate]) -> PlistFileCandidate? {
        if let recommended = candidates.first(where: \.isRecommended) {
            return recommended
        }
        if let preferences = candidates.first(where: \.isAppPreferencesPlist) {
            return preferences
        }
        return candidates.first
    }

    private static func bundleIdentifiers(in candidates: [PlistFileCandidate]) -> Set<String> {
        var identifiers = Set<String>()
        for candidate in candidates {
            guard let obj = try? PropertyListSerialization.propertyList(from: candidate.data, format: nil) else {
                continue
            }
            identifiers.formUnion(bundleIdentifiers(in: obj))
        }
        return identifiers
    }

    private static func bundleIdentifiers(in obj: Any) -> Set<String> {
        var identifiers = Set<String>()

        if let dict = obj as? [String: Any] {
            for (key, value) in dict {
                if isBundleIdentifierKey(key),
                   let string = value as? String {
                    identifiers.formUnion(bundleIdentifierCandidates(from: string))
                }
                identifiers.formUnion(bundleIdentifiers(in: value))
            }
        } else if let array = obj as? [Any] {
            for value in array {
                identifiers.formUnion(bundleIdentifiers(in: value))
            }
        }

        return identifiers
    }

    private static func isBundleIdentifierKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized == "cfbundleidentifier"
            || normalized == "bundleidentifier"
            || normalized == "softwareversionbundleid"
            || normalized.hasSuffix("bundleidentifier")
            || (normalized.contains("bundle") && normalized.contains("id"))
    }

    private static func bundleIdentifierCandidates(from value: String) -> Set<String> {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = Set<String>()
        if isBundleIdentifierLike(trimmed) {
            candidates.insert(trimmed)
        }

        let parts = trimmed.split(separator: ".", maxSplits: 1).map(String.init)
        if parts.count == 2,
           parts[0].count == 10,
           parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }),
           isBundleIdentifierLike(parts[1]) {
            candidates.insert(parts[1])
        }

        return candidates
    }

    private static func isBundleIdentifierLike(_ value: String) -> Bool {
        guard value.contains("."),
              !value.contains("/"),
              !value.contains(":"),
              !value.contains("$") else {
            return false
        }

        return value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$"#,
            options: .regularExpression
        ) != nil
    }
}
