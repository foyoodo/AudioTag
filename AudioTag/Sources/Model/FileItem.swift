//
//  FileItem.swift
//  AudioTag
//
//  Created by foyoodo on 28/10/2024.
//

import SwiftUI
import UniformTypeIdentifiers

private let allowedExtension = [
    "mp3", "m4a",
    "wav", "flac",
]

@Observable
final class FileItem: Codable, ExpandedObservable {
    var id: URL { url }

    private(set) var url: URL

    var name: String

    var isExpanded: Bool = false

    var children: [FileItem]?

    @ObservationIgnored
    var parent: FileItem?

    @ObservationIgnored
    var isDirectory: Bool { children != nil }

    var isExist: Bool { FileManager.default.fileExists(atPath: url.path()) }

    private enum CodingKeys: CodingKey {
        case url
        case children
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let url = try container.decode(URL.self, forKey: .url)

        self.url = url
        self.name = url.lastPathComponent
        self.children = try container.decodeIfPresent([FileItem].self, forKey: .children)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.url, forKey: .url)
        try container.encodeIfPresent(self.children, forKey: .children)
    }

    init(url: URL, isExpanded: Bool = false) {
        self.url = url
        self.isExpanded = isExpanded
        self.name = url.lastPathComponent
    }

    func allFiles() -> [FileItem] {
        guard isDirectory else { return allowedExtension.contains(url.pathExtension) ? [self] : [] }
        guard let children else { return [] }
        return children.reduce([]) { partialResult, item in
            partialResult + item.allFiles()
        }
    }
}

extension FileItem: Hashable, Identifiable, Comparable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }

    static func < (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.name < rhs.name
    }
}

extension FileItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .fileItem)
        ProxyRepresentation(exporting: \.url) { FileItem(url: $0) }
    }
}

extension UTType {
    fileprivate static var fileItem: UTType { UTType(exportedAs: "com.foyoodo.AudioTag-FileItem") }
}
