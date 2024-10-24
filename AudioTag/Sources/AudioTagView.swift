//
//  AudioTagView.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

struct AudioTagView: View {

    @State var viewModel: AudioTagViewModel

    var body: some View {
        ScrollView {
            VStack {
                Form {
                    audioTagRow("Title", text: $viewModel.title)
                    audioTagRow("Artist", text: $viewModel.artist)
                    audioTagRow("Album", text: $viewModel.album)
                    audioTagRow("Year", text: $viewModel.year)
                    audioTagRow("Track", text: $viewModel.track)
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.save()
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
