//
//  ContentView.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct File: Identifiable, Hashable {
    var id: URL { url }
    let name: String
    let url: URL
}

struct ContentView: View {

    @State private var audioFiles: [File] = []
    @State private var selectedAudioFileID: File.ID?
    @State private var selectedAudioFile: File?
    @State private var audioFilesDict: [File.ID: File] = [:]

    @State private var viewModel = AudioTagViewModel()

    var body: some View {
        NavigationSplitView {
            List(audioFiles, selection: $selectedAudioFileID) { file in
                Text(file.name)
            }
            .onChange(of: selectedAudioFileID) {
                if let selectedAudioFileID {
                    selectedAudioFile = audioFilesDict[selectedAudioFileID]
                    viewModel.fileURL = selectedAudioFile?.url
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
        } detail: {
            if let _ = selectedAudioFile {
                AudioTagView(viewModel: viewModel)
            } else {
                Text("Drop files in the sidebar to edit tags")
                    .padding()
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var success = false
        let providers = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        providers.forEach { provider in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                url.map(addAudioFile(url:))
                success = true
            }
        }
        return success
    }

    private func addAudioFile(url: URL) {
        guard audioFilesDict[url] == nil else { return }
        let newFile = File(name: url.lastPathComponent, url: url)
        DispatchQueue.main.async {
            audioFiles.append(newFile)
            audioFilesDict[newFile.id] = newFile
        }
    }
}
