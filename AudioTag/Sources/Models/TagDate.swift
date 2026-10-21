//
//  TagDate.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import Foundation

/// A date as tags record it: a year, a month of one, a day, or a time of day, written as
/// ISO 8601 has it, as `2021`, `2021-06`, `2021-06-01` or `2021-06-01T08:30`, which every
/// format's tags take, if not all of it.
struct TagDate: Comparable, Hashable {
  /// How much of a date there is.
  enum Precision: Int, Comparable {
    case year, month, day, time

    static func < (lhs: Precision, rhs: Precision) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  var year: Int
  var month: Int?
  var day: Int?
  var hour: Int?
  var minute: Int?
  var second: Int?
  /// As it was given, such as `Z` or `+08:00`, where a time was.
  var timeZone: String?

  var precision: Precision {
    if hour != nil {
      .time
    } else if day != nil {
      .day
    } else if month != nil {
      .month
    } else {
      .year
    }
  }

  /// Reads a date from text: ISO 8601's form, with dashes, slashes, dots or nothing between
  /// its parts, and a space or a `T` before a time; nil where it's no date.
  init?(_ text: String) {
    let text = text.trimmingCharacters(in: .whitespaces)
    let separated =
      /(\d{4})(?:[-\/.](\d{1,2})(?:[-\/.](\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:?\d{2})?)?)?)?/
    let compact = /(\d{4})(\d{2})(\d{2})?/
    if let match = text.wholeMatch(of: separated) {
      year = Int(match.1)!
      month = match.2.flatMap { Int($0) }
      day = match.3.flatMap { Int($0) }
      hour = match.4.flatMap { Int($0) }
      minute = match.5.flatMap { Int($0) }
      second = match.6.flatMap { Int($0) }
      timeZone = match.7.map(String.init)
    } else if let match = text.wholeMatch(of: compact) {
      year = Int(match.1)!
      month = Int(match.2)
      day = match.3.flatMap { Int($0) }
    } else {
      return nil
    }
    guard isValid else { return nil }
  }

  private var isValid: Bool {
    guard year > 0 else { return false }
    if let month, !(1...12).contains(month) { return false }
    if let day {
      guard let month,
        let date = Calendar(identifier: .gregorian).date(
          from: DateComponents(year: year, month: month)),
        let days = Calendar(identifier: .gregorian).range(of: .day, in: .month, for: date),
        days.contains(day)
      else { return false }
    }
    if let hour, !(0...23).contains(hour) { return false }
    if let minute, !(0...59).contains(minute) { return false }
    if let second, !(0...59).contains(second) { return false }
    return true
  }

  /// As ISO 8601 writes it.
  var text: String {
    var text = String(format: "%04d", year)
    guard let month else { return text }
    text += String(format: "-%02d", month)
    guard let day else { return text }
    text += String(format: "-%02d", day)
    guard let hour, let minute else { return text }
    text += String(format: "T%02d:%02d", hour, minute)
    if let second { text += String(format: ":%02d", second) }
    return text + (timeZone ?? "")
  }

  static func < (lhs: TagDate, rhs: TagDate) -> Bool {
    func parts(_ date: TagDate) -> [Int] {
      [
        date.year, date.month ?? 0, date.day ?? 0, date.hour ?? -1, date.minute ?? 0,
        date.second ?? 0,
      ]
    }
    return parts(lhs).lexicographicallyPrecedes(parts(rhs))
  }
}
