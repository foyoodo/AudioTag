//
//  AudioFileTable.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct AudioFileTable: View {
    enum Field: Hashable {
        case name(AudioFileItem)
        case title(AudioFileItem)
        case artist(AudioFileItem)
        case album(AudioFileItem)
        case genre(AudioFileItem)
        case year(AudioFileItem)
        case track(AudioFileItem)

        var file: AudioFileItem {
            switch self {
            case let .name(file), let .title(file), let .artist(file), let .album(file),
                 let .genre(file), let .year(file), let .track(file):
                return file
            }
        }
    }

    @Environment(AudioTagViewModel.self) var viewModel

    @FocusState private var focusedField: Field?

    var body: some View {
        @Bindable var viewModel = viewModel

        Table(viewModel.files, selection: $viewModel.selectedFiles) {
            TableColumn("Artwork") { file in
                @Bindable var file = file
                if let image = file.picture {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            }
            TableColumn("Name") { textField(for: $0, keyPath: \.file.name, field: .name($0)) }
            TableColumn("Title") { textField(for: $0, keyPath: \.title, field: .title($0)) }
            TableColumn("Artist") { textField(for: $0, keyPath: \.artist, field: .artist($0)) }
            TableColumn("Album") { textField(for: $0, keyPath: \.album, field: .album($0)) }
            TableColumn("Genre") { textField(for: $0, keyPath: \.genre, field: .genre($0)) }
            TableColumn("Year") { textField(for: $0, keyPath: \.year, field: .year($0)) }
            TableColumn("Track") { textField(for: $0, keyPath: \.track, field: .track($0)) }
        }
        .dropDestination(for: FileItem.self) { items, location in
            _ = try? items.map(viewModel.handleDropped(file:))
            return true
        }
//        .onChange(of: focusedField) { oldValue, _ in
//            oldValue?.file.save()
//        }
    }

    @ViewBuilder
    private func textField(
        for file: AudioFileItem,
        keyPath: KeyPath<Bindable<AudioFileItem>, Binding<String>>,
        field: Field
    ) -> some View {
        @Bindable var file = file
        TextField("", text: $file[keyPath: keyPath])
            .focused($focusedField, equals: field)
            .onSubmit {
                file.save()
            }
    }
}
