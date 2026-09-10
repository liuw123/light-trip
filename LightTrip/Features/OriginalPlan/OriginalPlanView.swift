import SwiftUI
import UniformTypeIdentifiers

struct OriginalPlanView: View {
    let trip: Trip
    @State private var sourceMode = false
    @State private var query = ""
    @State private var exportDocument: TripTextDocument?
    @State private var showingExporter = false

    private var source: SourceDocument? { trip.sourceDocument }
    private var visibleSource: String {
        guard let raw = source?.rawContent else { return "" }
        guard !query.isEmpty else { return raw }
        return raw.components(separatedBy: "\n").filter { $0.localizedCaseInsensitiveContains(query) }.joined(separator: "\n")
    }

    var body: some View {
        Group {
            if let source {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(source.sourceFormat.label, systemImage: "doc.text")
                            Spacer()
                            Text(version(source)).foregroundStyle(.secondary)
                        }.font(.caption)
                        Text(rendered(visibleSource, source: source))
                            .font(sourceMode ? .system(.body, design: .monospaced) : .body)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding()
                }
                .searchable(text: $query, prompt: "Search original plan")
            } else {
                EmptyStateView(symbol: "doc.text", title: "No original plan", message: "Trips created manually do not have an imported source.")
            }
        }
        .navigationTitle("Original Plan")
        .toolbar {
            if let source {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(sourceMode ? "Reader" : "Source", systemImage: sourceMode ? "doc.richtext" : "chevron.left.forwardslash.chevron.right") { sourceMode.toggle() }
                    Button("Export", systemImage: "square.and.arrow.up") { exportDocument = TripTextDocument(text: source.rawContent); showingExporter = true }
                }
            }
        }
        .fileExporter(isPresented: $showingExporter, document: exportDocument,
                      contentType: exportType, defaultFilename: exportName) { _ in exportDocument = nil }
    }

    private func rendered(_ value: String, source: SourceDocument) -> AttributedString {
        if !sourceMode, source.sourceFormat == .markdown,
           let attributed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .full)) { return attributed }
        if !sourceMode, source.sourceFormat == .lightTripJSON,
           let data = value.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let string = String(data: formatted, encoding: .utf8) { return AttributedString(string) }
        return AttributedString(value)
    }

    private func version(_ source: SourceDocument) -> String {
        if let version = source.contractVersion { return "Schema v\(version)" }
        if let version = source.parserVersion { return "Parser v\(version)" }
        return "Imported"
    }

    private var exportType: UTType {
        switch source?.sourceFormat {
        case .lightTripJSON: .json
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        default: .plainText
        }
    }

    private var exportName: String {
        source?.sourceName ?? (source?.sourceFormat == .lightTripJSON ? "trip.lighttrip" : "trip-plan")
    }
}
