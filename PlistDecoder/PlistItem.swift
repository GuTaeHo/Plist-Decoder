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
        case .array(let arr):
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
