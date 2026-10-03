//
//  mensajedeVGRApp.swift
//  mensajedeVGR
//
//  Created by Moises rojas on 2/09/26.
//

import SwiftUI
import SwiftData
import Combine

@main
struct mensajedeVGRApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var localization = LocalizationManager.shared
    @State private var isSeeding = false
    @State private var seedDone = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SermonRecord.self,
            ParagraphRecord.self,
            FavoriteRecord.self,
            NoteRecord.self,
            ParagraphHighlightRecord.self,
            FreeNoteRecord.self,
            AIChatMessage.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("No se pudo crear ModelContainer: \(error)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("No se pudo crear el contenedor de datos: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if isSeeding {
                    SeedingView()
                        .environmentObject(localization)
                } else {
                    MainTabView()
                        .environmentObject(appState)
                        .environmentObject(localization)
                        .modelContainer(sharedModelContainer)
                }
            }
            .modelContainer(sharedModelContainer)
            .onAppear {
                let context = sharedModelContainer.mainContext
                let fetch = FetchDescriptor<SermonRecord>()
                let hasData = (try? context.fetch(fetch))?.isEmpty == false

                if hasData {
                    seedDone = true
                } else {
                    isSeeding = true
                    DemoLibraryService.shared.seedIfNeeded(
                        context: context,
                        onComplete: {
                            Task { @MainActor in
                                withAnimation {
                                    self.isSeeding = false
                                    self.seedDone = true
                                }
                            }
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Splash / Seeding View
private struct SeedingView: View {
    @EnvironmentObject private var localization: LocalizationManager
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "book.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            Text("Mensajes de William Branham")
                .font(.title2.bold())

            ProgressView()
                .scaleEffect(1.5)

            Text("Cargando sermones en español\(String(repeating: ".", count: dotCount))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .onReceive(timer) { _ in
                    dotCount = (dotCount + 1) % 4
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
