//
//  FileItem.swift
//  AudioTag
//
//  Created by foyoodo on 25/10/2024.
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

struct FileItem: Identifiable, Comparable, Codable {
    var id: URL { url }
    let url: URL
    var isDirectory: Bool
    var children: [FileItem]?

    var name: String { url.lastPathComponent }

    private enum CodingKeys: CodingKey {
        case url
        case isDirectory
        case children
    }

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.url = try container.decode(URL.self, forKey: .url)
        self.isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        self.children = try container.decodeIfPresent([FileItem].self, forKey: .children)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.url, forKey: .url)
        try container.encode(self.isDirectory, forKey: .isDirectory)
        try container.encodeIfPresent(self.children, forKey: .children)
    }

    func allFiles() -> [FileItem] {
        guard isDirectory else { return [self] }
        guard let children else { return [] }
        return children.reduce([]) { partialResult, item in
            partialResult + item.allFiles()
        }
    }

    static func < (lhs: FileItem, rhs: FileItem) -> Bool {
        switch (lhs.isDirectory, rhs.isDirectory) {
        case (true, false): true
        case (false, true): false
        default: lhs.name < rhs.name
        }
    }
}

extension FileItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .fileItem)
    }
}

extension UTType {
    static var fileItem: UTType { UTType(exportedAs: "com.foyoodo.AudioTag-FileItem") }
}
