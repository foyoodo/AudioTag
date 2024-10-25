//
//  AudioTagViewModel.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

@Observable
final class AudioTagViewModel {

    var filesDict = [File.ID: File]()

    var files: [File] = []

    var selectedFiles = Set<File.ID>()
    var selectedFile: File? {
        guard selectedFiles.count == 1 else { return nil }
        return filesDict[selectedFiles.first!]
    }

    func handleDropped(url: URL) {
        let file = File(url: url)
        filesDict[url] = file
        files.append(file)
    }
}
