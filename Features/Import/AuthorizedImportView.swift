import SwiftUI
import SwiftData

struct AuthorizedImportView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var localization: LocalizationManager
    @State private var showingFilePicker = false
    @State private var importStatus: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
                // MARK: - Encabezado
                VStack(alignment: .leading, spacing: 8) {
                    Text(localization.getString("homeTitle"))
                        .font(.headline)
                    Text(localization.getString("homeAuthorizationNote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                // MARK: - Botones de Importación
                VStack(spacing: 12) {
                    Button(action: { showingFilePicker = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localization.getString("importPDF"))
                                    .font(.subheadline)
                                Text(localization.getString("importPDFSubtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.primary)
                    
                    Button(action: {}) {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localization.getString("importAudio"))
                                    .font(.subheadline)
                                Text(localization.getString("importAudioSubtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.primary)
                    
                    Button(action: importarSermonesEspanol) {
                        HStack(spacing: 12) {
                            Image(systemName: "text.book.closed")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localization.getString("importSpanishSermons"))
                                    .font(.subheadline)
                                Text(localization.getString("importSpanishSermonsSubtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.primary)
                }
                .padding()
                
                // MARK: - Información de Fuentes
                VStack(alignment: .leading, spacing: 12) {
                    Text(localization.getString("homeAuthorizedSources"))
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localization.getString("homeReferenceSource"))
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(localization.getString("homeUnauthorizedWarning"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                
                // MARK: - Estado de Importación
                if !importStatus.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localization.getString("importStatusTitle"))
                            .font(.headline)
                        Text(importStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle(localization.getString("tabImport"))
            .navigationBarTitleDisplayMode(.inline)
    }
    
    private func importarSermonesEspanol() {
        guard let url = Bundle.main.url(forResource: "bro_branham_sermons_es", withExtension: "json") else {
            importStatus = "❌ No se encontró bro_branham_sermons_es.json en el bundle."
            return
        }
        importStatus = localization.getString("importStatusLoading")

        Task {
            do {
                // Leer y decodificar el JSON fuera del hilo principal
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: url)
                }.value
                let envelope = try JSONDecoder().decode(BroSermonCatalogEnvelope.self, from: data)
                let total = envelope.sermons.count

                importStatus = localization.getString("importStatusParsed")
                    .replacingOccurrences(of: "{n}", with: "\(total)")

                // Procesar en lotes de 50 para no congelar la UI
                let batchSize = 50
                var insertados = 0
                var actualizados = 0

                for batchStart in stride(from: 0, to: envelope.sermons.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, envelope.sermons.count)
                    let batch = Array(envelope.sermons[batchStart..<batchEnd])

                    let (ins, act) = DemoLibraryService.shared.upsert(catalog: batch, context: modelContext)
                    insertados += ins
                    actualizados += act

                    importStatus = localization.getString("importStatusProgress")
                        .replacingOccurrences(of: "{done}", with: "\(batchEnd)")
                        .replacingOccurrences(of: "{total}", with: "\(total)")
                }

                importStatus = "✅ \(insertados) nuevo(s), \(actualizados) actualizado(s) en español."
            } catch {
                importStatus = "❌ Error al importar: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        AuthorizedImportView()
    }
        .environmentObject(LocalizationManager.shared)
}
