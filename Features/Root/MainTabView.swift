import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var localization: LocalizationManager

    var body: some View {
        AIChatView()
            .preferredColorScheme(localization.isDarkMode ? .dark : .light)
    }
}
