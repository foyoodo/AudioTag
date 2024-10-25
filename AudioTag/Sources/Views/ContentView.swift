//
//  ContentView.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct ContentView: View {
    @Environment(AudioTagViewModel.self) var viewModel

    var body: some View {
        NavigationSplitView {
            FileTreeView()
        } content: {
            AudioFileTable()
        } detail: {
            Group {
                if let selectedFile = viewModel.selectedFile {
                    TagEditorView(file: selectedFile)
                } else {
                    Text("Select a single file to edit")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 300, max: 400)
        }
    }
}
