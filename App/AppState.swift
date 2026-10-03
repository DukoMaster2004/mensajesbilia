import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var searchText: String = ""
    @Published var preferredLanguage: String = "Español"
    @Published var isAIEnabled: Bool = true
    @Published var readingFontSize: Double = 18 {
        didSet { UserDefaults.standard.set(readingFontSize, forKey: Self.fontSizeKey) }
    }
    @Published var appearanceMode: String = "Automático"
    @Published var offlineMode: Bool = true

    private static let fontSizeKey = "readingFontSize"

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        if saved >= 12, saved <= 32 {
            readingFontSize = saved
        }
    }

    func setTab(_ tab: Int) {
        selectedTab = tab
    }
}
