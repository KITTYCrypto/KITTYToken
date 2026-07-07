import Foundation

typealias JSONObject = [String: Any]

enum MobileTab: String, CaseIterable, Identifiable {
    case command = "Command"
    case board = "Board"
    case signals = "Signals"
    case ops = "Ops"
    case live = "Live"

    var id: String { rawValue }
}

struct ChainScopeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> JSONObject {
        self[key] as? JSONObject ?? [:]
    }

    func array(_ key: String) -> [JSONObject] {
        if let value = self[key] as? [JSONObject] {
            return value
        }
        if let value = self[key] as? [Any] {
            return value.compactMap { $0 as? JSONObject }
        }
        return []
    }

    func string(_ key: String, _ fallback: String = "") -> String {
        let value = self[key]
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return fallback
    }

    func int(_ key: String, _ fallback: Int = 0) -> Int {
        let value = self[key]
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String, let parsed = Int(text) {
            return parsed
        }
        return fallback
    }

    func double(_ key: String, _ fallback: Double = 0) -> Double {
        let value = self[key]
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String, let parsed = Double(text) {
            return parsed
        }
        return fallback
    }

    func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        let value = self[key]
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let bool = value as? Bool {
            return bool
        }
        if let text = value as? String {
            return ["1", "true", "yes", "pass", "ready", "active", "armed"].contains(text.lowercased())
        }
        return fallback
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shortID(prefix: Int = 8, suffix: Int = 4) -> String {
        guard count > prefix + suffix + 3 else { return self }
        return "\(self[startIndex..<index(startIndex, offsetBy: prefix)])...\(self[index(endIndex, offsetBy: -suffix)..<endIndex])"
    }
}
