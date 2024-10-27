//
//  TagEditorView.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct TagEditorView: View {
    @Environment(AudioTagViewModel.self) var viewModel

    @Bindable var file: AudioFileItem

    var fileIndex: Int {
        viewModel.files.firstIndex(where: { $0.id == file.id })!
    }

    var body: some View {
        ScrollView {
            VStack {
                Form {
                    VStack {
                        imageEditor()

                        if let picture = file.picture {
                            Text("\(Int(picture.size.width)) x \(Int(picture.size.height))")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }

                    Section {
                        audioTagRow("Title", text: $file.title)
                        audioTagRow("Artist", text: $file.artist)
                        audioTagRow("Album", text: $file.album)
                        audioTagRow("Comment", text: $file.comment)
                        audioTagRow("Genre", text: $file.genre)
                        audioTagRow("Year", text: $file.year)
                        audioTagRow("Track", text: $file.track)
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        file.save()
                    }
                }

                Button {
                    file.save()
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

    @ViewBuilder
    private func imageEditor() -> some View {
        Group {
            if let image = file.picture {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.gray.opacity(0.5), style: .init(lineWidth: 1))
                    .overlay {
                        Text("Drop or paste an image")
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .focusable(interactions: .edit)
        .onCopyCommand {
            guard let image = file.picture else { return [] }
            return [ .init(object: image) ]
        }
        .onDeleteCommand {
            file.picture = nil
        }
        .onPasteCommand(of: [.image]){ providers in
            guard let provider = providers.first else { return }
            _ = provider.loadTransferable(type: NSImage.self) { result in
                switch result {
                case .success(let image):
                    Task { @MainActor in
                        file.picture = image
                    }
                case .failure(let failure):
                    ()
                }
            }
        }
    }
}
