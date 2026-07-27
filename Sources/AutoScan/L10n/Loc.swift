import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, en
    var id: String { rawValue }
    var title: String { self == .ru ? "Русский" : "English" }
}

/// Локализация без .strings-файлов: текст задаётся парой прямо в месте использования.
/// Так ничего не теряется при рефакторинге и не бывает «пустых ключей» в UI.
enum Loc {
    /// Зеркало текущего языка для доступа из любого потока.
    nonisolated(unsafe) static var lang: AppLanguage = {
        if let saved = UserDefaults.standard.string(forKey: "autoscan_lang"),
           let l = AppLanguage(rawValue: saved) { return l }
        // при первом запуске — по системному языку
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("ru") ? .ru : .en
    }()

    static func t(_ ru: String, _ en: String) -> String {
        lang == .ru ? ru : en
    }
}

/// Обёртка для SwiftUI: смена языка перерисовывает интерфейс.
@MainActor
final class LocalizationStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            Loc.lang = language
            UserDefaults.standard.set(language.rawValue, forKey: "autoscan_lang")
        }
    }

    init() {
        self.language = Loc.lang
    }

    func toggle() {
        language = (language == .ru) ? .en : .ru
    }
}
