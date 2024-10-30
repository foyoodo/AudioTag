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

    func onFolderChange(_ folder: FileItem?) {
        selectedFiles.removeAll()
        filesDict.removeAll()
        files = folder?.allFiles().map {
            let audioFile = AudioFileItem(file: $0)
            filesDict[$0.url] = audioFile
            return audioFile
        } ?? []
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
