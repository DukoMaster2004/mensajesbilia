import Foundation
import Combine
import SwiftUI

// MARK: - Localization Manager
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @Published var currentLanguage: String = UserDefaults.standard.string(forKey: "appLanguage") ?? "es" {
        didSet {
            if oldValue != currentLanguage {
                UserDefaults.standard.set(currentLanguage, forKey: "appLanguage")
                UserDefaults.standard.synchronize()
                // Notificar a todos los observadores del cambio
                objectWillChange.send()
            }
        }
    }
    
    @Published var isDarkMode: Bool = UserDefaults.standard.bool(forKey: "isDarkMode") {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
            UserDefaults.standard.synchronize()
        }
    }
    
    func getString(_ key: String) -> String {
        return Strings.get(key, language: currentLanguage)
    }
}

// MARK: - All Strings
struct Strings {
    // MARK: - Tab Labels
    static let tabHome = [
        "es": "Inicio",
        "en": "Home"
    ]
    static let tabMessages = [
        "es": "Mensajes",
        "en": "Messages"
    ]
    static let tabFavorites = [
        "es": "Favoritos",
        "en": "Favorites"
    ]
    static let tabImport = [
        "es": "Importar",
        "en": "Import"
    ]
    static let tabAI = [
        "es": "IA",
        "en": "AI"
    ]
    static let tabSettings = [
        "es": "Ajustes",
        "en": "Settings"
    ]
    
    // MARK: - Home View
    static let homeTitle = [
        "es": "Mensajes de William Branham",
        "en": "Messages by William Branham"
    ]
    static let homeSubtitle = [
        "es": "Busca, estudia y escucha los mensajes.",
        "en": "Search, study and listen to messages."
    ]
    static let homeSearch = [
        "es": "Buscar mensajes, referencias o temas",
        "en": "Search messages, references or topics"
    ]
    static let homeContinueReading = [
        "es": "Continuar leyendo",
        "en": "Continue Reading"
    ]
    static let homeRecentMessages = [
        "es": "Mensajes recientes",
        "en": "Recent Messages"
    ]
    static let homeAuthorizedSources = [
        "es": "Fuentes autorizadas",
        "en": "Authorized Sources"
    ]
    static let homeAuthorizationNote = [
        "es": "La biblioteca solo debe incluir audios, PDFs y transcripciones que el usuario tenga autorización para usar.",
        "en": "The library should only include audio, PDFs and transcriptions that the user is authorized to use."
    ]
    static let homeReferenceSource = [
        "es": "Fuente referencial: branham.org/es/messageaudio",
        "en": "Reference source: branham.org/en/messageaudio"
    ]
    static let homeUnauthorizedWarning = [
        "es": "Importar contenido protegido sin autorización no está permitido.",
        "en": "Importing protected content without authorization is not allowed."
    ]
    static let homeAskMessages = [
        "es": "Pregúntale a los Mensajes",
        "en": "Ask the Messages"
    ]
    
    // MARK: - Settings View
    static let settingsTitle = [
        "es": "Ajustes",
        "en": "Settings"
    ]
    static let settingsAppearance = [
        "es": "Apariencia",
        "en": "Appearance"
    ]
    static let settingsDarkMode = [
        "es": "Modo Oscuro",
        "en": "Dark Mode"
    ]
    static let settingsLanguage = [
        "es": "Idioma",
        "en": "Language"
    ]
    static let settingsSpanish = [
        "es": "Español",
        "en": "Spanish"
    ]
    static let settingsEnglish = [
        "es": "Inglés",
        "en": "English"
    ]
    static let settingsTextSize = [
        "es": "Tamaño de Texto",
        "en": "Text Size"
    ]
    static let settingsAbout = [
        "es": "Acerca de",
        "en": "About"
    ]
    static let settingsAboutText = [
        "es": "Versión 1.0\n\nAplicación de estudio de los mensajes de William Branham.",
        "en": "Version 1.0\n\nApplication to study the messages of William Branham."
    ]
    static let settingsData = [
        "es": "Datos",
        "en": "Data"
    ]
    static let settingsExport = [
        "es": "Exportar biblioteca",
        "en": "Export library"
    ]
    static let settingsExportSubtitle = [
        "es": "Guardar o compartir tus mensajes, notas y favoritos en un archivo",
        "en": "Save or share your messages, notes and favorites as a file"
    ]
    static let settingsExportEmpty = [
        "es": "No hay mensajes para exportar todavía.",
        "en": "There are no messages to export yet."
    ]
    static let settingsExportDone = [
        "es": "✅ {n} mensajes exportados.",
        "en": "✅ {n} messages exported."
    ]
    
    // MARK: - Common
    static let ok = [
        "es": "OK",
        "en": "OK"
    ]
    static let cancel = [
        "es": "Cancelar",
        "en": "Cancel"
    ]
    static let save = [
        "es": "Guardar",
        "en": "Save"
    ]
    static let close = [
        "es": "Cerrar",
        "en": "Close"
    ]
    static let search = [
        "es": "Buscar",
        "en": "Search"
    ]

    // MARK: - Sermon Detail View
    static let sermonAudioPlayback = [
        "es": "Reproducción de audio",
        "en": "Audio Playback"
    ]
    static let sermonContent = [
        "es": "Contenido",
        "en": "Content"
    ]
    static let sermonMyNotes = [
        "es": "Mis Notas",
        "en": "My Notes"
    ]
    static let sermonSaveNote = [
        "es": "Guardar Nota",
        "en": "Save Note"
    ]
    static let sermonQATitle = [
        "es": "Preguntar al mensaje",
        "en": "Ask the message"
    ]
    static let sermonQAPlaceholder = [
        "es": "Escribe tu pregunta sobre este mensaje…",
        "en": "Ask a question about this message…"
    ]
    static let sermonQAAsk = [
        "es": "Preguntar",
        "en": "Ask"
    ]
    static let sermonQAThinking = [
        "es": "Buscando citas en el mensaje…",
        "en": "Searching quotes in the message…"
    ]
    static let sermonQAQuotes = [
        "es": "Citas textuales del mensaje",
        "en": "Verbatim quotes from the message"
    ]
    static let sermonQAParagraph = [
        "es": "Párrafo",
        "en": "Paragraph"
    ]
    static let sermonQAEmpty = [
        "es": "Haz una pregunta y la app mostrará el texto exacto del mensaje, con su número de párrafo.",
        "en": "Ask a question and the app will show the exact text of the message, with its paragraph number."
    ]

    // MARK: - Favorites View
    static let favoritesEmpty = [
        "es": "Sin favoritos",
        "en": "No favorites"
    ]
    static let favoritesEmptyHint = [
        "es": "Agrega mensajes a favoritos para verlos aquí",
        "en": "Add messages to favorites to see them here"
    ]
    static let favoritesParagraph = [
        "es": "Párrafo",
        "en": "Paragraph"
    ]

    // MARK: - AI Chat View
    static let aiChatHint = [
        "es": "Haz preguntas sobre los mensajes de William Branham",
        "en": "Ask questions about William Branham's messages"
    ]
    static let aiChatPlaceholder = [
        "es": "Pregunta...",
        "en": "Ask..."
    ]
    static let aiChatProcessing = [
        "es": "Procesando tu pregunta...",
        "en": "Processing your question..."
    ]
    static let aiChatClear = [
        "es": "Borrar conversación",
        "en": "Clear conversation"
    ]
    static let aiChatClearConfirm = [
        "es": "¿Eliminar todos los mensajes de este chat?",
        "en": "Delete all messages in this chat?"
    ]
    static let aiChatYou = [
        "es": "Tú",
        "en": "You"
    ]
    static let aiChatAI = [
        "es": "IA",
        "en": "AI"
    ]

    // MARK: - Import View
    static let importPDF = [
        "es": "Importar PDF",
        "en": "Import PDF"
    ]
    static let importPDFSubtitle = [
        "es": "Documentos autorizados",
        "en": "Authorized documents"
    ]
    static let importAudio = [
        "es": "Importar Audio",
        "en": "Import Audio"
    ]
    static let importAudioSubtitle = [
        "es": "Archivos MP3/M4A",
        "en": "MP3/M4A files"
    ]
    static let importSpanishSermons = [
        "es": "Importar sermones en español",
        "en": "Import Spanish sermons"
    ]
    static let importSpanishSermonsSubtitle = [
        "es": "Desde bro_branham_sermons_es.json",
        "en": "From bro_branham_sermons_es.json"
    ]
    static let importStatusTitle = [
        "es": "Estado de Importación",
        "en": "Import Status"
    ]
    static let importStatusLoading = [
        "es": "⏳ Leyendo archivo...",
        "en": "⏳ Reading file..."
    ]
    static let importStatusParsed = [
        "es": "⏳ Importando {n} sermones...",
        "en": "⏳ Importing {n} sermons..."
    ]
    static let importStatusProgress = [
        "es": "⏳ {done} / {total} sermones...",
        "en": "⏳ {done} / {total} sermons..."
    ]

    // MARK: - TTS Player
    static let ttsPlay = [
        "es": "Leer en voz alta",
        "en": "Read Aloud"
    ]
    static let ttsPause = [
        "es": "Pausar",
        "en": "Pause"
    ]
    static let ttsResume = [
        "es": "Continuar",
        "en": "Resume"
    ]
    static let ttsStop = [
        "es": "Detener",
        "en": "Stop"
    ]
    static let ttsSpeed = [
        "es": "Velocidad",
        "en": "Speed"
    ]
    static let ttsListening = [
        "es": "Leyendo párrafo",
        "en": "Reading paragraph"
    ]

    // MARK: - Home Example Questions
    static let homeQuestion1 = [
        "es": "¿Qué enseñó Branham sobre la mujer y el hombre?",
        "en": "What did Branham teach about women and men?"
    ]
    static let homeQuestion2 = [
        "es": "¿Qué dijo sobre la serpiente?",
        "en": "What did he say about the serpent?"
    ]
    static let homeQuestion3 = [
        "es": "¿Dónde habló sobre Daniel?",
        "en": "Where did he speak about Daniel?"
    ]
    static let homeQuestion4 = [
        "es": "Busca todos los mensajes donde menciona Génesis 3.",
        "en": "Find all messages where he mentions Genesis 3."
    ]

    // MARK: - Getter
    static func get(_ key: String, language: String) -> String {
        let dict = stringDictionary[key] ?? [:]
        return dict[language] ?? dict["es"] ?? key
    }
    
    private static let stringDictionary: [String: [String: String]] = [
        "tabHome": tabHome,
        "tabMessages": tabMessages,
        "tabFavorites": tabFavorites,
        "tabImport": tabImport,
        "tabAI": tabAI,
        "tabSettings": tabSettings,
        "homeTitle": homeTitle,
        "homeSubtitle": homeSubtitle,
        "homeSearch": homeSearch,
        "homeContinueReading": homeContinueReading,
        "homeRecentMessages": homeRecentMessages,
        "homeAuthorizedSources": homeAuthorizedSources,
        "homeAuthorizationNote": homeAuthorizationNote,
        "homeReferenceSource": homeReferenceSource,
        "homeUnauthorizedWarning": homeUnauthorizedWarning,
        "homeAskMessages": homeAskMessages,
        "homeQuestion1": homeQuestion1,
        "homeQuestion2": homeQuestion2,
        "homeQuestion3": homeQuestion3,
        "homeQuestion4": homeQuestion4,
        "settingsTitle": settingsTitle,
        "settingsAppearance": settingsAppearance,
        "settingsDarkMode": settingsDarkMode,
        "settingsLanguage": settingsLanguage,
        "settingsSpanish": settingsSpanish,
        "settingsEnglish": settingsEnglish,
        "settingsTextSize": settingsTextSize,
        "settingsAbout": settingsAbout,
        "settingsAboutText": settingsAboutText,
        "settingsData": settingsData,
        "settingsExport": settingsExport,
        "settingsExportSubtitle": settingsExportSubtitle,
        "settingsExportEmpty": settingsExportEmpty,
        "settingsExportDone": settingsExportDone,
        "ok": ok,
        "cancel": cancel,
        "save": save,
        "close": close,
        "search": search,
        "sermonAudioPlayback": sermonAudioPlayback,
        "sermonContent": sermonContent,
        "sermonMyNotes": sermonMyNotes,
        "sermonSaveNote": sermonSaveNote,
        "sermonQATitle": sermonQATitle,
        "sermonQAPlaceholder": sermonQAPlaceholder,
        "sermonQAAsk": sermonQAAsk,
        "sermonQAThinking": sermonQAThinking,
        "sermonQAQuotes": sermonQAQuotes,
        "sermonQAParagraph": sermonQAParagraph,
        "sermonQAEmpty": sermonQAEmpty,
        "favoritesEmpty": favoritesEmpty,
        "favoritesEmptyHint": favoritesEmptyHint,
        "favoritesParagraph": favoritesParagraph,
        "aiChatHint": aiChatHint,
        "aiChatPlaceholder": aiChatPlaceholder,
        "aiChatProcessing": aiChatProcessing,
        "aiChatClear": aiChatClear,
        "aiChatClearConfirm": aiChatClearConfirm,
        "aiChatYou": aiChatYou,
        "aiChatAI": aiChatAI,
        "importPDF": importPDF,
        "importPDFSubtitle": importPDFSubtitle,
        "importAudio": importAudio,
        "importAudioSubtitle": importAudioSubtitle,
        "importSpanishSermons": importSpanishSermons,
        "importSpanishSermonsSubtitle": importSpanishSermonsSubtitle,
        "importStatusTitle": importStatusTitle,
        "importStatusLoading": importStatusLoading,
        "importStatusParsed": importStatusParsed,
        "importStatusProgress": importStatusProgress,
        "ttsPlay": ttsPlay,
        "ttsPause": ttsPause,
        "ttsResume": ttsResume,
        "ttsStop": ttsStop,
        "ttsSpeed": ttsSpeed,
        "ttsListening": ttsListening
    ]
}

// MARK: - Extension para acceso rápido
extension String {
    static func localized(_ key: String, language: String? = nil) -> String {
        let lang = language ?? LocalizationManager.shared.currentLanguage
        return Strings.get(key, language: lang)
    }
}
