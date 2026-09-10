import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TripTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText, UTType(filenameExtension: "md") ?? .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
