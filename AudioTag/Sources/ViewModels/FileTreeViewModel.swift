//
//  FileTreeViewModel.swift
//  AudioTag
//
//  Created by foyoodo on 25/10/2024.
//

import SwiftUI

@Observable
final class FileTreeViewModel {
    let allowedExtension = [
        "mp3", "m4a",
        "wav", "flac",
    ]

    var rootFolder = FileItem(url: FileManager.default.homeDirectoryForCurrentUser.appending(component: "Music"), isExpanded: true)

    var selectedFolders = Set<FileItem.ID>()
    var selectedFolder: FileItem? {
        guard selectedFolders.count == 1 else { return nil }
        return folderDict[selectedFolders.first!]
    }
    var folderDict = [FileItem.ID: FileItem]()

    func onAppear() {
        try? buildFileTree(for: rootFolder)
    }

    func buildFileTree(for root: FileItem) throws {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            root.children = nil
            return
        }
        root.children = try contents.map { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            let newFile = FileItem(url: url)
            newFile.parent = root
            folderDict[url] = newFile
            if values.isDirectory == true {
                try buildFileTree(for: newFile)
            }
            return newFile
        }
    }
}
