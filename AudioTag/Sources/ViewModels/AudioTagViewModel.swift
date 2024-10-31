//
//  AudioTagViewModel.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

@Observable
final class AudioTagViewModel {
    var files: [AudioFileItem] = []

    private var filesDict = [AudioFileItem.ID: AudioFileItem]()

    var selectedFiles = Set<AudioFileItem.ID>()
    var selectedFile: AudioFileItem? {
        guard selectedFiles.count == 1 else { return nil }
        return filesDict[selectedFiles.first!]
    }

    func onFolderChange(old oldFolder: FileItem?, new newFolder: FileItem?) {
        onExpandedFolderChange(old: oldFolder, new: newFolder)

        selectedFiles.removeAll()
        filesDict.removeAll()
        files = newFolder?.allFiles().map {
            let audioFile = AudioFileItem(file: $0)
            filesDict[$0.url] = audioFile
            return audioFile
        } ?? []
    }

    func onExpandedFolderChange(old oldFolder: FileItem?, new newFolder: FileItem?) {
        guard let newFolder else { return }

        let newTree = sequence(first: newFolder, next: { $0.parent }).reversed()

        if let oldFolder {
            let oldTree = sequence(first: oldFolder, next: { $0.parent }).reversed()
            var idx: Int?
            for (index, (oldNode, newNode)) in zip(oldTree, newTree).enumerated() {
                if oldNode != newNode {
                    idx = index
                    break
                }
            }
            if let idx {
                for folder in oldTree[idx..<oldTree.count] {
                    folder.isExpanded = false
                }
            }
        }

        for folder in newTree {
            folder.isExpanded = true
        }
    }

    func handleDropped(file: FileItem) throws {
        try FileTreeViewModel().buildFileTree(for: file)
        file.allFiles().forEach { file in
            let audioFile = AudioFileItem(file: file)
            filesDict[file.url] = audioFile
            files.append(audioFile)
        }
    }
}
