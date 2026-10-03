import SwiftUI
import SwiftData

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AIChatMessage.timestamp, order: .forward) private var messages: [AIChatMessage]
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var appState: AppState
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDeleteConfirmation = false
    @State private var showSermonLibrary = false
    @State private var showSettings = false
    @StateObject private var voiceInput = VoiceInputManager()
    @StateObject private var speech = SpeechManager.shared
    @AppStorage("voiceRepliesEnabled") private var voiceRepliesEnabled = true
    private let transcriptSearch = TabernaculoZoeSearchService()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Chat Messages
                if messages.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        
                        Text(localization.getString("homeAskMessages"))
                            .font(.headline)
                        
                        Text("¿Qué quieres consultar?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(messages) { message in
                                    ChatBubble(message: message) {
                                        speech.speak(
                                            paragraphs: [message.text],
                                            language: localization.currentLanguage == "en" ? "English" : "Español"
                                        )
                                    }
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { oldCount, newCount in
                            if newCount > oldCount, let lastMessage = messages.last {
                                withAnimation {
                                    scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                // MARK: - Error Alert
                if let error = errorMessage {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                            Button(action: { errorMessage = nil }) {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding()
                    }
                }
                
                // MARK: - Input Area
                VStack(spacing: 0) {
                    Divider()

                    if voiceInput.isRecording {
                        Label("Escuchando", systemImage: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 10)
                    }
                    
                    HStack(spacing: 12) {
                        TextField("Escribe tu pregunta...", text: $inputText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .disabled(isLoading)

                        Button {
                            if voiceInput.isRecording {
                                voiceInput.stop()
                            } else {
                                Task { await startVoiceInput() }
                            }
                        } label: {
                            Image(systemName: voiceInput.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(voiceInput.isRecording ? .red : .primary)
                        }
                        .disabled(isLoading)
                        .accessibilityLabel(voiceInput.isRecording ? "Detener dictado" : "Dictar pregunta")
                        
                        Button(action: {
                            Task {
                                await sendMessage()
                            }
                        }) {
                            if isLoading {
                                ProgressView()
                                    .frame(width: 44, height: 44)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16))
                                    .frame(width: 44, height: 44)
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(Circle())
                            }
                        }
                        .disabled(inputText.isEmpty || isLoading)
                    }
                    .padding()
                }
            }
            .navigationTitle(localization.getString("tabAI"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        Button {
                            showSermonLibrary = true
                        } label: {
                            Image(systemName: "books.vertical")
                        }
                        .accessibilityLabel("Abrir biblioteca de mensajes")

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Abrir ajustes")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        voiceRepliesEnabled.toggle()
                        if !voiceRepliesEnabled { speech.stop() }
                    } label: {
                        Image(systemName: voiceRepliesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    .accessibilityLabel(voiceRepliesEnabled ? "Desactivar respuestas en voz" : "Activar respuestas en voz")

                    ShareLink(item: conversationText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(messages.isEmpty)
                    .accessibilityLabel("Compartir conversación")

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(messages.isEmpty || isLoading)
                    .accessibilityLabel("Eliminar conversación")
                }
            }
            .sheet(isPresented: $showSermonLibrary) {
                SermonLibraryView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(localization)
                    .environmentObject(appState)
            }
            .confirmationDialog("¿Eliminar conversación?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive, action: deleteConversation)
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("Se eliminarán todas las preguntas y respuestas guardadas.")
            }
            .onChange(of: voiceInput.transcript) { _, transcript in
                inputText = transcript
            }
            .onChange(of: voiceInput.errorMessage) { _, error in
                if let error { errorMessage = error }
            }
            .onDisappear {
                voiceInput.stop()
                speech.stop()
            }
        }
    }

    private var conversationText: String {
        messages.map { message in
            "\(message.role == "user" ? "Pregunta" : "Respuesta"):\n\(message.text)"
        }.joined(separator: "\n\n")
    }

    private func deleteConversation() {
        for message in messages {
            modelContext.delete(message)
        }
        try? modelContext.save()
        errorMessage = nil
    }
    
    private func sendMessage() async {
        let userInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userInput.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        voiceInput.stop()
        
        // Guardar mensaje del usuario
        let userMessage = AIChatMessage(
            role: "user",
            text: userInput,
            timestamp: .now,
            sourceSummary: ""
        )
        modelContext.insert(userMessage)
        inputText = ""
        
        do {
            let results = try await transcriptSearch.search(query: userInput)
            guard !results.isEmpty else {
                let answer = "La fuente no encontró coincidencias para esa búsqueda. Prueba con otras palabras o con el código del sermón."
                saveAssistantMessage(answer, sourceSummary: "")
                isLoading = false
                speakLatestReply(answer)
                return
            }

            let answer = results.map {
                "\($0.text)\n\n— \($0.title), \($0.code), párrafo \($0.paragraphNumber)"
            }.joined(separator: "\n\n")
            saveAssistantMessage(
                answer,
                sourceSummary: "Fragmentos literales consultados en vivo en Tabernáculo Zoe."
            )
            speakLatestReply(answer)
        } catch {
            let answer = "No pude consultar la fuente. No voy a completar la respuesta con información generada; comprueba la conexión e inténtalo de nuevo."
            saveAssistantMessage(answer, sourceSummary: "")
            speakLatestReply(answer)
        }
        
        isLoading = false
    }
    
    private func startVoiceInput() async {
        let locale = localization.currentLanguage == "en" ? "en-US" : "es-ES"
        do {
            try await voiceInput.start(localeIdentifier: locale)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAssistantMessage(_ text: String, sourceSummary: String) {
        modelContext.insert(AIChatMessage(
            role: "assistant",
            text: text,
            timestamp: .now,
            sourceSummary: sourceSummary
        ))
        try? modelContext.save()
    }

    private func speakLatestReply(_ text: String) {
        guard voiceRepliesEnabled else { return }
        speech.speak(
            paragraphs: [text],
            language: localization.currentLanguage == "en" ? "English" : "Español"
        )
    }
}

// MARK: - Chat Bubble Component
struct ChatBubble: View {
    let message: AIChatMessage
    let onSpeak: () -> Void
    
    var isUser: Bool {
        message.role == "user"
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if isUser {
                Spacer()
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .padding(12)
                    .background(isUser ? Color.blue : Color(.secondarySystemBackground))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if !message.sourceSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.sourceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link(destination: TabernaculoZoeSearchService.sourceURL) {
                            Label("Abrir texto en Tabernáculo Zoe", systemImage: "arrow.up.right.square")
                                .font(.caption)
                        }
                        Link(destination: TabernaculoZoeSearchService.officialCatalogURL) {
                            Label("Consultar índice de The Message", systemImage: "doc.text")
                                .font(.caption)
                        }
                    }
                }
                if !isUser {
                    Button(action: onSpeak) {
                        Image(systemName: "speaker.wave.2")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reproducir respuesta en voz")
                }
            }
            
            if !isUser {
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AIChatView()
        .environmentObject(LocalizationManager.shared)
}
