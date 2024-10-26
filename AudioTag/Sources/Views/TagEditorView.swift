//
//  TagEditorView.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct TagEditorView: View {
    @Environment(AudioTagViewModel.self) var viewModel

    var file: AudioFileItem

    var fileIndex: Int {
        viewModel.files.firstIndex(where: { $0.id == file.id })!
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack {
                Form {
                    Group {
                        if let image = viewModel.files[fileIndex].picture {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.gray.opacity(0.5), style: .init(lineWidth: 1))
                                .overlay{
                                    Text("Drop or paste an image")
                                }
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .focusable(interactions: .edit)
                    .onCopyCommand {
                        guard let image = file.picture else { return [] }
                        return [ .init(object: image) ]
                    }
                    .onDeleteCommand {
                        viewModel.files[fileIndex].picture = nil
                    }
                    .onPasteCommand(of: [.image]){ providers in
                        guard let provider = providers.first else { return }
                        _ = provider.loadTransferable(type: NSImage.self) { result in
                            switch result {
                            case .success(let image):
                                Task { @MainActor in
                                    viewModel.files[fileIndex].picture = image
                                }
                            case .failure(let failure):
                                ()
                            }
                        }
                    }

                    Section {
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
