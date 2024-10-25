//
//  FileTreeViewModel.swift
//  AudioTag
//
//  Created by foyoodo on 25/10/2024.
//

import SwiftUI

@Observable
final class FileTreeViewModel {

    var fileTree: FileItem?

    let allowedExtension = [
        "mp3", "m4a",
        "wav", "flac",
    ]

    func onAppear() {
        if let desktopTree = buildFileTree(at: URL(fileURLWithPath: NSHomeDirectory() + "/Music")) {
            fileTree = desktopTree
        }
    }

    func buildFileTree(at url: URL) -> FileItem? {
        var isDirectory: ObjCBool = false
        let fileExists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        guard fileExists else { return nil }

        var fileItem = FileItem(url: url, isDirectory: isDirectory.boolValue)

        if isDirectory.boolValue {
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                fileItem.children = contents.compactMap { buildFileTree(at: $0) }.sorted()
            }
        }

        guard fileItem.children?.isEmpty == false || allowedExtension.contains(url.pathExtension) else {
            return nil
        }

        return fileItem
    }
}
