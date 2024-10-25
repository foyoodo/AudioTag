//
//  FileTreeView.swift
//  AudioTag
//
//  Created by foyoodo on 25/10/2024.
//

import SwiftUI

struct FileTreeView: View {
    @State var viewModel = FileTreeViewModel()
    @State var selectedFiles = Set<FileItem.ID>()

    var body: some View {
        List(selection: $selectedFiles) {
            if let fileTree = viewModel.fileTree {
                OutlineGroup(fileTree, children: \.children) { item in
                    HStack {
                        Image(systemName: item.isDirectory ? "folder.fill" : "text.justify.leading")

                        Text(item.name)
                    }
                    .draggable(item)
                }
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
    }
}
