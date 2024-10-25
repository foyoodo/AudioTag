//
//  FileTable.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct FileTable: View {
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
    }

    private func textField(
        for file: Binding<File>,
        keyPath: KeyPath<Binding<File>, Binding<String>>
    ) -> some View {
        TextField(text: file[keyPath: keyPath]) { }
            .onSubmit {
                file.wrappedValue.save()
            }
    }
}
