import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var source = ""
    @State private var sourceName: String?
    @State private var format: ImportFormatOverride = .automatic
    @State private var targetTrip: Trip?
    @State private var showingFileImporter = false
    @State private var draft: TripImportDraft?
    @State private var errorMessage: String?

    init(targetTrip: Trip? = nil) {
        _targetTrip = State(initialValue: targetTrip)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    TextEditor(text: $source).frame(minHeight: 220).font(.body.monospaced())
                    HStack {
                        Button("Paste", systemImage: "doc.on.clipboard") { source = UIPasteboard.general.string ?? ""; sourceName = "Clipboard" }
                        Spacer()
                        Button("Choose File", systemImage: "folder") { showingFileImporter = true }
                    }
                    Button("Load Sample Trip", systemImage: "sparkles") { loadSample() }
                }
                Section("Format") {
                    Picker("Interpret as", selection: $format) {
                        Text("Automatic").tag(ImportFormatOverride.automatic)
                        Text("Light Trip JSON").tag(ImportFormatOverride.json)
                        Text("Markdown").tag(ImportFormatOverride.markdown)
                    }
                }
                if !trips.isEmpty {
                    Section("Destination") {
                        Picker("Import action", selection: Binding(get: { targetTrip?.id }, set: { id in targetTrip = trips.first { $0.id == id } })) {
                            Text("Create new trip").tag(UUID?.none)
                            ForEach(trips) { Text("Update \($0.title)").tag(Optional($0.id)) }
                        }
                    }
                }
            }
            .navigationTitle("Import Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Review") { parse() }.disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.json, .plainText], allowsMultipleSelection: false) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    source = try String(contentsOf: url, encoding: .utf8); sourceName = url.lastPathComponent
                } catch { errorMessage = error.localizedDescription }
            }
            .fullScreenCover(item: $draft) { draft in
                ImportReviewView(draft: draft, targetTrip: targetTrip) { dismiss() }
            }
            .alert("Unable to import", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func parse() {
        do { draft = try TripImportService().parse(source, sourceName: sourceName, override: format) }
        catch { errorMessage = error.localizedDescription }
    }

    private func loadSample() {
        guard let url = Bundle.main.url(forResource: "sample-trip.lighttrip", withExtension: "json", subdirectory: "SampleTrips") ?? Bundle.main.url(forResource: "sample-trip.lighttrip", withExtension: "json"),
              let value = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "The bundled sample could not be loaded."
            return
        }
        source = value; sourceName = "sample-trip.lighttrip.json"; format = .json
    }
}
