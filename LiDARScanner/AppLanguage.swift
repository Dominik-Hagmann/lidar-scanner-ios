import Combine
import Foundation
import ObjectiveC.runtime
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case german = "de"
    case english = "en"

    var id: String { rawValue }
}

struct L10nPhrase: Equatable {
    let key: String
    let args: [String]

    init(_ key: String, _ args: [String] = []) {
        self.key = key
        self.args = args
    }

    var localized: String {
        if args.isEmpty {
            return LanguageManager.string(key)
        }
        return LanguageManager.format(key, args: args)
    }
}

private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = LanguageManager.overrideBundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    private static let storageKey = "appLanguage"
    private static let lock = NSLock()
    private static var _activeSelection: AppLanguage = {
        let saved = UserDefaults.standard.string(forKey: storageKey)
        return saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }()
    private static let installLanguageBundle: Void = {
        object_setClass(Bundle.main, LanguageBundle.self)
    }()

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            Self.lock.withLock {
                Self._activeSelection = selection
            }
            UserDefaults.standard.set(selection.rawValue, forKey: Self.storageKey)
            if selection == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([selection.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    private init() {
        _ = Self.installLanguageBundle
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        let initial = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
        Self.lock.withLock {
            Self._activeSelection = initial
        }
        self.selection = initial
    }

    private static var activeSelection: AppLanguage {
        lock.withLock { _activeSelection }
    }

    var locale: Locale {
        switch selection {
        case .system:
            return .autoupdatingCurrent
        case .german:
            return Locale(identifier: "de")
        case .english:
            return Locale(identifier: "en")
        }
    }

    static var currentLocale: Locale {
        switch activeSelection {
        case .system:
            return .autoupdatingCurrent
        case .german:
            return Locale(identifier: "de")
        case .english:
            return Locale(identifier: "en")
        }
    }

    static var isGerman: Bool {
        switch activeSelection {
        case .german:
            return true
        case .english:
            return false
        case .system:
            return Bundle.main.preferredLocalizations.first?.hasPrefix("de") == true
        }
    }

    static var overrideBundle: Bundle? {
        let code: String
        switch activeSelection {
        case .system:
            return nil
        case .german:
            code = "de"
        case .english:
            code = "en"
        }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    static var currentBundle: Bundle {
        overrideBundle ?? .main
    }

    static func string(_ key: String) -> String {
        currentBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, args: arguments)
    }

    static func format(_ key: String, args: [CVarArg]) -> String {
        let template = string(key)
        return String(format: template, locale: currentLocale, arguments: args)
    }
}

func L(_ key: String) -> String {
    LanguageManager.string(key)
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    LanguageManager.format(key, args: arguments)
}
