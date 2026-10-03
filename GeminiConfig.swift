import Foundation

/// Configuración de Gemini que lee desde Secrets.swift
struct GeminiConfig {
    /// API Key de Google Gemini (desde Secrets.swift)
    static let apiKey: String = Secrets.geminiAPIKey
    
    /// Modelo de Gemini a usar (desde Secrets.swift)
    static let model: String = Secrets.geminiModel
    
    /// URL base de la API de Gemini
    static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
}
