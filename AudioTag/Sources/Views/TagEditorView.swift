//
//  TagEditorView.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct TagEditorView: View {
    @Bindable var file: AudioFileItem

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
                        TextField("Title", text: $file.title)
                        TextField("Artist", text: $file.artist)
                        TextField("Album", text: $file.album)
                        TextField("Comment", text: $file.comment)
                        TextField("Genre", text: $file.genre)
                        TextField("Year", text: $file.year)
                        TextField("Track", text: $file.track)
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
