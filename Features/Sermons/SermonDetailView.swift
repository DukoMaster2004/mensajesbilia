import SwiftUI
import SwiftData
import WebKit

struct SermonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var appState: AppState
    @StateObject private var speech = SpeechManager.shared
    @State private var isFavorited = false
    @State private var note: String = ""
    @State private var showAudioPlayer = false
    @State private var showQnA = false

    let sermon: SermonRecord

    /// Párrafos separados del body para el lector TTS y numeración
    private var paragraphs: [String] {
        sermon.body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// URL base del audio en branham.org — siempre válida
    private var branhamAudioURL: URL {
        let lang = sermon.language.lowercased().contains("español") ? "SPN" : "ENG"
        let code = sermon.code.trimmingCharacters(in: .whitespaces)
        return URL(string: "https://branham.org/es/messageaudio/\(lang)/\(code)")
            ?? URL(string: "https://branham.org/es/messageaudio")!
    }

    /// Audio oficial (m4a del CDN de branham.org) resuelto por código.
    private var officialAudio: BranhamAudioEntry? {
        BranhamAudioCatalog.shared.entry(for: sermon.code)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sermon.code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(sermon.title)
                                    .font(.title3.bold())
                                Text(sermon.location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(action: toggleFavorite) {
                                Image(systemName: isFavorited ? "star.fill" : "star")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isFavorited ? .yellow : .gray)
                            }
                        }

                        HStack(spacing: 16) {
                            Label {
                                Text("\(sermon.durationMinutes) min")
                                    .font(.caption)
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .foregroundStyle(.secondary)

                            Divider().frame(height: 16)

                            Label {
                                Text(sermon.language)
                                    .font(.caption)
                            } icon: {
                                Image(systemName: "globe")
                            }
                            .foregroundStyle(.secondary)

                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    // MARK: - Audio oficial (branham.org)
                    VStack(spacing: 8) {
                        if let officialAudio {
                            // Reproductor nativo que transmite el .m4a oficial
                            OfficialAudioPlayerView(entry: officialAudio)

                            if let stream = officialAudio.streamURL {
                                Link(destination: stream) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.right.square")
                                        Text("Abrir en branham.org")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                }
                                .padding(.horizontal, 4)
                            }
                        } else {
                            // Sin entrada oficial: enlace + WebView embebido
                            Link(destination: branhamAudioURL) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "headphones")
                                            .font(.system(size: 22))
                                            .foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(localization.getString("sermonAudioPlayback"))
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text("Abrir en branham.org →")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 18))
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Button(action: { withAnimation { showAudioPlayer.toggle() } }) {
                                HStack {
                                    Image(systemName: showAudioPlayer ? "chevron.up.circle" : "chevron.down.circle")
                                        .foregroundStyle(.secondary)
                                    Text(showAudioPlayer ? "Cerrar reproductor" : "Abrir reproductor aquí")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                            }
                            .buttonStyle(.plain)

                            if showAudioPlayer {
                                WebPlayerView(url: branhamAudioURL)
                                    .frame(height: 480)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.horizontal)

                    // MARK: - TTS Player
                    if !paragraphs.isEmpty {
                        TTSPlayerView(
                            paragraphs: paragraphs,
                            sermonLanguage: sermon.language,
                            speech: speech,
                            localization: localization
                        )
                        .padding(.horizontal)
                    }

                    // MARK: - Contenido numerado
                    if !paragraphs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localization.getString("sermonContent"))
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, text in
                                NumberedParagraphView(
                                    number: index + 1,
                                    text: text,
                                    fontSize: appState.readingFontSize,
                                    isActive: speech.currentParagraphIndex == index,
                                    onTap: {
                                        speech.speak(
                                            paragraphs: paragraphs,
                                            language: sermon.language,
                                            startingAt: index
                                        )
                                    }
                                )
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    // MARK: - Notas
                    VStack(alignment: .leading, spacing: 12) {
                        Text(localization.getString("sermonMyNotes"))
                            .font(.headline)

                        TextEditor(text: $note)
                            .frame(height: 120)
                            .border(Color(.secondarySystemBackground), width: 1)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button(action: saveNote) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text(localization.getString("sermonSaveNote"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                }
                .padding(.bottom, 30)
            }
            .navigationTitle(sermon.code)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showQnA = true }) {
                        Image(systemName: "questionmark.bubble")
                    }
                    .accessibilityLabel(localization.getString("sermonQATitle"))
                }
            }
            .sheet(isPresented: $showQnA) {
                SermonQnAView(sermon: sermon)
                    .environmentObject(localization)
            }
            .onAppear { checkIfFavorited() }
            .onDisappear { speech.stop() }
        }
    }

    private func toggleFavorite() {
        withAnimation {
            isFavorited.toggle()
            if isFavorited {
                modelContext.insert(FavoriteRecord(type: "sermon", sermonID: sermon.id, createdAt: .now))
            } else {
                if let fav = findFavorite() { modelContext.delete(fav) }
            }
        }
    }

    private func findFavorite() -> FavoriteRecord? {
        let sermonID = sermon.id
        let predicate = #Predicate<FavoriteRecord> { $0.sermonID == sermonID && $0.type == "sermon" }
        return try? modelContext.fetch(FetchDescriptor<FavoriteRecord>(predicate: predicate)).first
    }

    private func checkIfFavorited() { isFavorited = findFavorite() != nil }
    private func saveNote() { print("Nota guardada: \(note)") }
}

// MARK: - WebView para audio oficial de branham.org

struct WebPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - TTS Player

private struct TTSPlayerView: View {
    let paragraphs: [String]
    let sermonLanguage: String
    @ObservedObject var speech: SpeechManager
    let localization: LocalizationManager

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                Button(action: { speech.skipToPrevious() }) {
                    Image(systemName: "backward.fill").font(.system(size: 20))
                }
                .disabled(!speech.isPlaying && !speech.isPaused)

                Button(action: togglePlayback) {
                    Image(systemName: playIcon)
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                }

                Button(action: { speech.skipToNext() }) {
                    Image(systemName: "forward.fill").font(.system(size: 20))
                }
                .disabled(!speech.isPlaying && !speech.isPaused)

                if speech.isPlaying || speech.isPaused {
                    Button(action: { speech.stop() }) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Menu {
                    ForEach([0.4, 0.5, 0.6, 0.75, 1.0], id: \.self) { s in
                        Button(action: { speech.rate = Float(s) }) {
                            Label(s == 1.0 ? "1× Normal" : "\(s)×",
                                  systemImage: speech.rate == Float(s) ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                        Text(localization.getString("ttsSpeed")).font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if speech.isPlaying || speech.isPaused {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundStyle(.blue)
                        .symbolEffect(.variableColor, isActive: speech.isPlaying)
                    Text("\(localization.getString("ttsListening")) \(speech.currentParagraphIndex + 1) / \(paragraphs.count)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var playIcon: String {
        speech.isPaused ? "play.fill" : (speech.isPlaying ? "pause.fill" : "play.fill")
    }

    private func togglePlayback() {
        if speech.isPaused { speech.resume() }
        else if speech.isPlaying { speech.pause() }
        else { speech.speak(paragraphs: paragraphs, language: sermonLanguage) }
    }
}

// MARK: - Párrafo numerado

private struct NumberedParagraphView: View {
    let number: Int
    let text: String
    var fontSize: Double = 17
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Número del párrafo
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isActive ? .blue : Color(.tertiaryLabel))
                .frame(minWidth: 28, alignment: .trailing)
                .padding(.top, 3)

            // Texto
            Text(text)
                .font(.system(size: fontSize))
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(isActive ? Color.blue.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            isActive ? RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.35), lineWidth: 1) : nil
        )
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

#Preview {
    let sermon = SermonRecord(
        code: "58-0312",
        title: "Jesucristo Es El Mismo Ayer, Hoy, y Por Los Siglos",
        location: "Harrisonburg, Virginia",
        language: "Español", body: "Gracias, hermano. Pueden tomar asiento.\n\nEste es un gran privilegio que esperaba desde hace algún tiempo.\n\nAhora, no queremos tomar mucho tiempo, porque el Sr. Vayle y los demás hablarán.\n\nCreemos que primero el hombre debe de nacer de nuevo."
    )
    SermonDetailView(sermon: sermon)
        .environmentObject(LocalizationManager.shared)
        .environmentObject(AppState())
}
