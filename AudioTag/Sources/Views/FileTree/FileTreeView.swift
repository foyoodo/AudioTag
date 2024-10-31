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

    @AppStorage("shouldCollapseOthers") var shouldCollapseOthers: Bool = true

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollViewReader { proxy in
            List(selection: $theViewModel.selectedFolders) {
                ExpandedOutlineGroup(theViewModel.rootFolder, children: \.children) { item in
                    @Bindable var item = item
                    Label {
                        TextField("", text: $item.name)
                    } icon: {
                        if item.isDirectory {
                            Image(systemName: item.isExpanded ? "folder" : "folder.fill")
                        } else {
                            Image(systemName: "music.quarternote.3")
                        }
                    }
                    .background {
                        if item.isHighlighted {
                            Color.brightYellow
                                .clipShape(
                                    .rect(cornerRadius: 4)
                                )
                                .padding(-3)
                        }
                    }
                    .listItemTint(.monochrome)
                    .id(item.id)
                    .draggable(item)
                }
            }
            .onAppear {
                theViewModel.onAppear()
            }
            .onChange(of: theViewModel.selectedFolder) { oldValue, newValue in
                viewModel.onFolderChange(old: oldValue, new: newValue)
            }
            .onChange(of: viewModel.selectedFile) { oldValue, newValue in
                guard let file = newValue?.file else { return }

                viewModel.onExpandedFolderChange(
                    old: oldValue?.file.parent,
                    new: newValue?.file.parent
                )

                Task { @MainActor in
                    try await Task.sleep(nanoseconds: 1_000_000)
                    withAnimation {
                        proxy.scrollTo(file.id, anchor: .center)
                    } completion: {
                        withAnimation {
                            file.isHighlighted = true
                        } completion: {
                            withAnimation(.default.delay(0.5)) {
                                file.isHighlighted = false
                            }
                        }
                    }
                }
            }
        }
    }
}
