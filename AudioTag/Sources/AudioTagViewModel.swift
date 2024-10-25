//
//  AudioTagViewModel.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

@Observable
final class AudioTagViewModel {

    var filesDict = [AudioFileItem.ID: AudioFileItem]()

    var files: [AudioFileItem] = []

    var selectedFiles = Set<AudioFileItem.ID>()
    var selectedFile: AudioFileItem? {
        guard selectedFiles.count == 1 else { return nil }
        return filesDict[selectedFiles.first!]
    }

    func handleDropped(url: URL) {
        let file = AudioFileItem(url: url)
        filesDict[url] = file
        files.append(file)
    }
}
