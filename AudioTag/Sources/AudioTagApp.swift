//
//  AudioTagApp.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI

@main
struct AudioTagApp: App {
    @State private var viewModel = AudioTagViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
        }
    }
}
