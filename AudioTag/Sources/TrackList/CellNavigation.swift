//
//  CellNavigation.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

/// Where editing in the track list goes next, as a spreadsheet's does: by rows, which keeps the
/// column, or by fields, through the columns that can be edited, in the order they're shown,
/// on into the next row and the one before.
struct CellNavigation {
  /// A row and a column, as the table numbers them.
  struct Cell: Equatable {
    var row: Int
    var column: Int
  }

  /// The columns that can be edited, in the order they're shown.
  var editableColumns: [Int]
  var rowCount: Int
  /// Whether a row's track can be edited, which those that can't are passed over for.
  var isEditable: (Int) -> Bool

  /// The cell `rows` rows, or `fields` fields, from `cell`; nil where there's none.
  func cell(from cell: Cell, rows: Int = 0, fields: Int = 0) -> Cell? {
    guard !editableColumns.isEmpty, var field = editableColumns.firstIndex(of: cell.column) else {
      return nil
    }
    var row = cell.row
    repeat {
      if rows != 0 {
        row += rows
      } else {
        field += fields
        if field >= editableColumns.count {
          (row, field) = (row + 1, 0)
        } else if field < 0 {
          (row, field) = (row - 1, editableColumns.count - 1)
        }
      }
      guard (0..<rowCount).contains(row) else { return nil }
    } while !isEditable(row)
    return Cell(row: row, column: editableColumns[field])
  }
}
