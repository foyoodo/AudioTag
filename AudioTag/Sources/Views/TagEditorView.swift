//
//  TagEditorView.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct TagEditorView: View {
    @Environment(AudioTagViewModel.self) var viewModel

    var file: File

    var fileIndex: Int {
        viewModel.files.firstIndex(where: { $0.id == file.id })!
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack {
                Form {
                    audioTagRow("Title", text: $viewModel.files[fileIndex].title)
                    audioTagRow("Artist", text: $viewModel.files[fileIndex].artist)
                    audioTagRow("Album", text: $viewModel.files[fileIndex].album)
                    audioTagRow("Comment", text: $viewModel.files[fileIndex].comment)
                    audioTagRow("Genre", text: $viewModel.files[fileIndex].genre)
                    audioTagRow("Year", text: $viewModel.files[fileIndex].year)
                    audioTagRow("Track", text: $viewModel.files[fileIndex].track)
                }
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.files[fileIndex].save()
                }

                Button {
                    viewModel.files[fileIndex].save()
                } label: {
                    Text("Save")
                }
            }
            .padding()
        }
    }

    private func audioTagRow(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        TextField(titleKey, text: text)
    }
}
