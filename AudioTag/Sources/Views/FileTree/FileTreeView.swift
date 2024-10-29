//
//  FileTreeView.swift
//  AudioTag
//
//  Created by foyoodo on 25/10/2024.
//

import SwiftUI

struct FileTreeView: View {
    @Environment(AudioTagViewModel.self) var viewModel

    @State var theViewModel = FileTreeViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollViewReader { proxy in
            List(selection: $theViewModel.selectedFolders) {
                ExpandedOutlineGroup(theViewModel.rootFolder, children: \.children) { item in
                    @Bindable var item = item
                    Label {
                        TextField("", text: $item.name)
                    } icon: {
                        Image(systemName: item.isExpanded ? "folder" : "folder.fill")
                    }
                    .listItemTint(.monochrome)
                    .id(item.id)
                }
            }
            .onAppear {
                theViewModel.onAppear()
            }
            .onChange(of: theViewModel.selectedFolder) { _, newValue in
                viewModel.onFolderChange(newValue)
            }
            .onChange(of: viewModel.selectedFile) { _, newValue in
                for file in sequence(first: newValue?.file.parent, next: { $0?.parent }) {
                    file?.isExpanded = true
                }
                if let folder = newValue?.file.parent {
                    Task { @MainActor in
                        try await Task.sleep(nanoseconds: 1_000_000)
                        withAnimation {
                            proxy.scrollTo(folder.id)
                        }
                    }
                }
            }
        }
    }
}
