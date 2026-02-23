//
//  AudioFileItem.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import Foundation
import AppKit
import TagLib_Swift

@Observable
final class AudioFileItem: Identifiable, Hashable {
    private static let yearPattern = /^(19|20)\d{2}$/

    var id: URL { file.url }

    var file: FileItem

    let audioFile: AudioFile

    static func == (lhs: AudioFileItem, rhs: AudioFileItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var title: String {
        didSet { audioFile.title = title }
    }

    var artist: String {
        didSet { audioFile.artist = artist }
    }

    var album: String {
        didSet { audioFile.album = album }
    }

    var comment: String {
        didSet { audioFile.comment = comment }
    }

    var genre: String {
        didSet { audioFile.genre = genre }
    }

    var year: String {
        didSet {
            let year = year.trimmingCharacters(in: .whitespacesAndNewlines)
            if year.wholeMatch(of: Self.yearPattern) != nil {
                audioFile.year = UInt(year)
            }
        }
    }

    var track: String {
        didSet { audioFile.track = .init(track) }
    }

    var picture: NSImage? {
        didSet { audioFile.pictures = picture.map { [$0] } }
    }

    init(file: FileItem) {
        self.file = file
        self.audioFile = .init(url: file.url)

        title = audioFile.title ?? ""
        artist = audioFile.artist ?? ""
        album = audioFile.album ?? ""
        comment = audioFile.comment ?? ""
        genre = audioFile.genre ?? ""
        year = audioFile.year.map { "\($0)" } ?? ""
        track = audioFile.track.map { "\($0)" } ?? ""
        picture = audioFile.pictures?.first
    }

    func save() {
        audioFile.apply()
    }
}
