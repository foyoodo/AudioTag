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
final class FileItem: ExpandedObservable {
    var id: URL { url }

    private(set) var url: URL

    var isExpanded: Bool

    var children: [FileItem]?

    @ObservationIgnored
    var parent: FileItem?

    @ObservationIgnored
    var isDirectory: Bool { children != nil }

    var name: String

    var isExist: Bool { FileManager.default.fileExists(atPath: url.path()) }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
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

extension FileItem: Codable, Hashable, Identifiable, Comparable {
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
