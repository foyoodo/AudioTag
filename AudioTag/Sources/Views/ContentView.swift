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

        } content: {
            FileTable()
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let providers = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        providers.forEach { provider in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                url.map(addAudioFile(url:))
            }
        }
        return !providers.isEmpty
    }

    private func addAudioFile(url: URL) {
        viewModel.handleDropped(url: url)
    }
}
