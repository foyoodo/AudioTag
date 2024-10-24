//
//  AudioTagViewModel.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import SwiftUI
import TagLib_Swift

@Observable
final class AudioTagViewModel {

    var fileURL: URL? {
        get { audioFile?.url }
        set { audioFile = newValue.map(AudioFile.init(url:)) }
    }

    private var audioFile: AudioFile?

    var title: String {
        get { audioFile?.title ?? "" }
        set { audioFile?.title = newValue }
    }

    var artist: String {
        get { audioFile?.artist ?? "" }
        set { audioFile?.artist = newValue }
    }

    var album: String {
        get { audioFile?.album ?? "" }
        set { audioFile?.album = newValue }
    }

    var year: String {
        get { (audioFile?.year).map { "\($0)" } ?? "" }
        set { audioFile?.year = .init(newValue) }
    }

    var track: String {
        get { (audioFile?.track).map { "\($0)" } ?? "" }
        set { audioFile?.track = .init(newValue) }
    }

    func save() {
        audioFile?.apply()
    }
}
