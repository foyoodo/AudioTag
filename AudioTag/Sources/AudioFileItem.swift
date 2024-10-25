//
//  AudioFileItem.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import Foundation
import TagLib_Swift

struct AudioFileItem: Identifiable {

    var id: URL { fileURL }

    let fileURL: URL
    var name: String

    let audioFile: AudioFile

    var title: String {
        get { audioFile.title ?? "" }
        set { audioFile.title = newValue }
    }

    var artist: String {
        get { audioFile.artist ?? "" }
        set { audioFile.artist = newValue }
    }

    var album: String {
        get { audioFile.album ?? "" }
        set { audioFile.album = newValue }
    }

    var comment: String {
        get { audioFile.comment ?? "" }
        set { audioFile.comment = newValue }
    }

    var genre: String {
        get { audioFile.genre ?? "" }
        set { audioFile.genre = newValue }
    }

    var year: String {
        get { (audioFile.year).map { "\($0)" } ?? "" }
        set { audioFile.year = .init(newValue) }
    }

    var track: String {
        get { (audioFile.track).map { "\($0)" } ?? "" }
        set { audioFile.track = .init(newValue) }
    }

    init(url: URL) {
        fileURL = url
        name = fileURL.lastPathComponent
        audioFile = .init(url: url)
    }

    func save() {
        audioFile.apply()
    }
}
