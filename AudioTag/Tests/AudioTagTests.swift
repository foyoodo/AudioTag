//
//  AudioTagTests.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import Foundation
import TagLib
import Testing

@testable import AudioTag

@Suite("Tag fields")
struct TagFieldTests {
  @Test("Text fields show every value of their key, and set one")
  func text() {
    var tags: Tags = ["ARTIST": ["YOASOBI", "Ayase"]]
    #expect(TagField.artist.value(in: tags) == "YOASOBI; Ayase")
    TagField.artist.set("Ikura", in: &tags)
    #expect(tags["ARTIST"] == ["Ikura"])
    TagField.artist.set("", in: &tags)
    #expect(tags.values.isEmpty)
  }

  @Test("Numeric fields keep only positive numbers")
  func numbers() {
    var tags: Tags = ["TRACKNUMBER": ["3/12"]]
    #expect(TagField.trackNumber.value(in: tags) == "3")
    #expect(TagField.trackCount.value(in: tags) == "12")
    TagField.trackNumber.set(" 4 ", in: &tags)
    #expect(tags["TRACKNUMBER"] == ["4/12"])
    TagField.trackCount.set("none", in: &tags)
    #expect(tags["TRACKNUMBER"] == ["4"])
  }

  @Test("Positions are shown and edited as a number and a count")
  func positions() {
    var tags: Tags = ["DISCNUMBER": ["1"], "DISCTOTAL": ["2"]]
    #expect(Position.disc.value(in: tags) == "1/2")
    Position.disc.set("2", in: &tags)
    #expect(tags["DISCNUMBER"] == ["2"])
    #expect(tags["DISCTOTAL"] == ["2"])
    Position.disc.set("1/3", in: &tags)
    #expect(Position.disc.value(in: tags) == "1/3")
    Position.track.set("5/", in: &tags)
    #expect(tags["TRACKNUMBER"] == ["5"])
  }
}

@Suite("Editing in the track list")
struct CellNavigationTests {
  /// Columns 2, 3 and 5 can be edited; row 2 can't.
  let navigation = CellNavigation(editableColumns: [2, 3, 5], rowCount: 4, isEditable: { $0 != 2 })

  @Test("Return goes to the same field of the next row, Shift-Return of the one before")
  func rows() {
    #expect(navigation.cell(from: .init(row: 0, column: 3), rows: 1) == .init(row: 1, column: 3))
    #expect(navigation.cell(from: .init(row: 3, column: 3), rows: -1) == .init(row: 1, column: 3))
    #expect(navigation.cell(from: .init(row: 3, column: 3), rows: 1) == nil)
    #expect(navigation.cell(from: .init(row: 0, column: 3), rows: -1) == nil)
  }

  @Test("Rows that can't be edited are passed over")
  func passesOver() {
    #expect(navigation.cell(from: .init(row: 1, column: 5), rows: 1) == .init(row: 3, column: 5))
    #expect(navigation.cell(from: .init(row: 1, column: 5), fields: 1) == .init(row: 3, column: 2))
  }

  @Test("Tab goes through the fields shown, on into the next row and the one before")
  func fields() {
    #expect(navigation.cell(from: .init(row: 0, column: 2), fields: 1) == .init(row: 0, column: 3))
    #expect(navigation.cell(from: .init(row: 0, column: 3), fields: 1) == .init(row: 0, column: 5))
    #expect(navigation.cell(from: .init(row: 0, column: 5), fields: 1) == .init(row: 1, column: 2))
    #expect(navigation.cell(from: .init(row: 1, column: 2), fields: -1) == .init(row: 0, column: 5))
    #expect(navigation.cell(from: .init(row: 3, column: 5), fields: 1) == nil)
    #expect(navigation.cell(from: .init(row: 0, column: 2), fields: -1) == nil)
  }

  @Test("A column that can't be edited leads nowhere")
  func uneditableColumn() {
    #expect(navigation.cell(from: .init(row: 0, column: 4), rows: 1) == nil)
  }
}

@Suite("File operations")
@MainActor
struct FileOperationsTests {
  let folder: URL
  let library = Library()
  let operations: FileOperations
  let undoManager = UndoManager()

  init() throws {
    folder =
      FileManager.default.temporaryDirectory.appending(path: "FileOperationsTests/\(UUID())")
      .standardizedFileURL
    try FileManager.default.createDirectory(
      at: folder.appending(path: "Album"), withIntermediateDirectories: true)
    try Data().write(to: folder.appending(path: "Album/song.mp3"))
    operations = FileOperations(library: library)
    // Every operation its own undoable action, as each event's would be.
    undoManager.groupsByEvent = false
  }

  private func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: folder.appending(path: path).path)
  }

  private func undoably(_ operation: () throws -> Void) rethrows {
    undoManager.beginUndoGrouping()
    defer { undoManager.endUndoGrouping() }
    try operation()
  }

  @Test("Renaming follows the file with its track, edits and all, and is undone")
  func rename() throws {
    let track = library.track(for: folder.appending(path: "Album/song.mp3"))
    try undoably {
      try operations.rename(track.url, to: "renamed.mp3", undoManager: undoManager)
    }
    #expect(exists("Album/renamed.mp3") && !exists("Album/song.mp3"))
    #expect(track.url.lastPathComponent == "renamed.mp3")
    #expect(library.track(for: folder.appending(path: "Album/renamed.mp3")) === track)

    undoManager.undo()
    #expect(exists("Album/song.mp3") && !exists("Album/renamed.mp3"))
    #expect(track.url.lastPathComponent == "song.mp3")
    undoManager.redo()
    #expect(exists("Album/renamed.mp3"))
  }

  @Test("Names that can't be a file's aren't given")
  func invalidNames() {
    let url = folder.appending(path: "Album/song.mp3")
    for name in ["", "  ", "a/b", ".hidden"] {
      #expect(throws: CocoaError.self) { try operations.rename(url, to: name, undoManager: nil) }
    }
  }

  @Test("Moving a folder moves the tracks of the files in it")
  func move() throws {
    let track = library.track(for: folder.appending(path: "Album/song.mp3"))
    let made = try operations.makeFolder(in: folder, undoManager: nil)
    #expect(made.lastPathComponent == "untitled folder")
    #expect(
      try operations.makeFolder(in: folder, undoManager: nil).lastPathComponent
        == "untitled folder 2")

    try undoably {
      try operations.move([folder.appending(path: "Album")], into: made, undoManager: undoManager)
    }
    #expect(exists("untitled folder/Album/song.mp3"))
    #expect(track.url.path.hasSuffix("untitled folder/Album/song.mp3"))
    undoManager.undo()
    #expect(exists("Album/song.mp3"))
    #expect(track.url.path.hasSuffix("/Album/song.mp3") && !track.url.path.contains("untitled"))
  }

  @Test("Moving onto a file of the same name fails, and moves nothing")
  func moveConflict() throws {
    let other = try operations.makeFolder(in: folder, undoManager: nil)
    try Data().write(to: other.appending(path: "song.mp3"))
    try Data().write(to: folder.appending(path: "Album/other.mp3"))
    #expect(throws: (any Error).self) {
      try operations.move(
        [folder.appending(path: "Album/other.mp3"), folder.appending(path: "Album/song.mp3")],
        into: other, undoManager: nil)
    }
    #expect(exists("Album/other.mp3") && exists("Album/song.mp3"))
  }

  @Test("A folder made is removed again by undoing, while it's empty")
  func makeFolder() throws {
    try undoably { _ = try operations.makeFolder(in: folder, undoManager: undoManager) }
    #expect(exists("untitled folder"))
    undoManager.undo()
    #expect(!exists("untitled folder"))
    undoManager.redo()
    #expect(exists("untitled folder"))
  }

  @Test("Trashing lets go of the tracks, and undoing brings the files back")
  func trash() throws {
    let url = folder.appending(path: "Album/song.mp3")
    let track = library.track(for: url)
    try undoably { try operations.trash([url], undoManager: undoManager) }
    #expect(!exists("Album/song.mp3"))
    #expect(library.track(for: url) !== track)
    undoManager.undo()
    #expect(exists("Album/song.mp3"))
  }
}

@Suite("Dates")
struct TagDateTests {
  @Test(
    "Dates are read in the forms they're typed in, and written as ISO 8601 has them",
    arguments: [
      ("2021", "2021"), ("2021-6", "2021-06"), ("2021/6/1", "2021-06-01"),
      ("2021.06.01", "2021-06-01"), ("20210601", "2021-06-01"), ("202106", "2021-06"),
      (" 2021-06-01 8:30 ", "2021-06-01T08:30"), ("2021-06-01T08:30:15Z", "2021-06-01T08:30:15Z"),
      ("2024-02-29", "2024-02-29"),
    ])
  func forms(_ typed: String, written: String) {
    #expect(TagDate(typed)?.text == written)
  }

  @Test(
    "What's no date isn't one",
    arguments: ["", "s", "21", "2021-13", "2023-02-29", "2021-06-01 24:00", "June 2021"])
  func invalid(_ text: String) {
    #expect(TagDate(text) == nil)
  }

  @Test("Dates are ordered by when they are, a year before its months")
  func order() {
    let dates = ["2021-06-01", "2021", "2020-12-31", "2021-06"].compactMap(TagDate.init)
    #expect(dates.sorted().map(\.text) == ["2020-12-31", "2021", "2021-06", "2021-06-01"])
  }

  @Test("Date fields write dates as ISO 8601 has them, show them so, and refuse what isn't one")
  func fields() {
    #expect(TagField.date.normalized("2021/6/1") == "2021-06-01")
    #expect(TagField.date.normalized("") == "")
    #expect(TagField.date.normalized("soon") == nil)
    #expect(TagField.title.normalized("soon") == "soon")
    let tags: Tags = ["DATE": ["2021-06-01 08:30:15"]]
    #expect(TagField.date.value(in: tags) == "2021-06-01T08:30:15")
  }
}
