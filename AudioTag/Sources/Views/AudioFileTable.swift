//
//  AudioFileTable.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct AudioFileTable: View {
    @Environment(AudioTagViewModel.self) var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Table($viewModel.files, selection: $viewModel.selectedFiles) {
            TableColumn("Name") { textField(for: $0, keyPath: \.name) }
            TableColumn("Title") { textField(for: $0, keyPath: \.title) }
            TableColumn("Artist") { textField(for: $0, keyPath: \.artist) }
            TableColumn("Album") { textField(for: $0, keyPath: \.album) }
            TableColumn("Genre") { textField(for: $0, keyPath: \.genre) }
            TableColumn("Year") { textField(for: $0, keyPath: \.year) }
            TableColumn("Track") { textField(for: $0, keyPath: \.track) }
        }
        .dropDestination(for: FileItem.self) { items, location in
            for item in items {
                _ = item.allFiles().map(\.url).map(viewModel.handleDropped(url:))
            }
            return true
        }
    }

    private func textField(
        for file: Binding<AudioFileItem>,
        keyPath: KeyPath<Binding<AudioFileItem>, Binding<String>>
    ) -> some View {
        TextField(text: file[keyPath: keyPath]) { }
            .onSubmit {
                file.wrappedValue.save()
            }
    }
}
