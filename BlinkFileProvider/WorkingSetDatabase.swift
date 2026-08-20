//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2024 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

import FileProvider
import Foundation
import SQLite
import struct SQLite.Expression


private let stateTable = Table("State")
private let itemKey          = Expression<String>("Item")
private let containerKey     = Expression<String>("Container")
private let versionKey       = Expression<Data>("Version")
private let isContainerKey   = Expression<Bool>("isContainer")
private let anchorKey        = Expression<Int>("Anchor")
private let nameKey          = Expression<String>("Name")
private let containerPathKey = Expression<String>("ContainerPath")

fileprivate extension Connection {
  var userVersion: Int {
    get { return Int(try! scalar("PRAGMA user_version") as! Int64) }
    set { try! run("PRAGMA user_version = \(newValue)") }
  }
}

public class WorkingSetDatabase {
  private let db: Connection
  static let dbVersion = 10
  private let log: BlinkLogger

  private let stateTable = Table("State")
  private let reparentedTable = Table("Reparented")

  var anchorVersion: String {
    get {
      return try! db.scalar("SELECT value FROM metadata WHERE key = 'anchor_version'") as? String ?? ""
    }
    set {
      try! db.run("INSERT OR REPLACE INTO metadata (key, value) VALUES ('anchor_version', ?)", newValue)
    }
  }

  public init(path: String, reset: Bool = false) throws {
    self.log = BlinkLogger("DB")
    let pathURL = URL(filePath: path)
    let dbChanged = try Self.hasDatabaseVersionChanged(at: path)

    if reset || dbChanged {
      log.info("Versions changed.")

      try? FileManager().removeItem(at: pathURL)
      self.db = try Connection(path)

      try db.run(stateTable.create {
        $0.column(itemKey, primaryKey: true)
        $0.column(containerKey)
        $0.column(versionKey)
        $0.column(isContainerKey)
        $0.column(anchorKey)
        $0.column(nameKey)
        $0.column(containerPathKey)
      })

      try! db.run("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT)")

      db.userVersion = Self.dbVersion
      self.renewAnchorVersion()
    } else {
      self.db = try Connection(path)
    }

    try FileManager().createDirectory(at: pathURL.deletingLastPathComponent(),
                                      withIntermediateDirectories: true,
                                      attributes: nil)

  }

  func renewAnchorVersion() {
    let newValue = String((0..<4).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement()! })
    self.anchorVersion = newValue
  }

  func item(_ itemIdentifier: NSFileProviderItemIdentifier) throws -> ItemRow? {
    let query = stateTable.filter(itemKey == itemIdentifier.rawValue)

    if let row = try db.pluck(query) {
      return ItemRow(row)
    } else {
      return nil
    }
  }

  func item(from name: String, containerIdentifier: NSFileProviderItemIdentifier) throws -> ItemRow? {
    let query = stateTable.filter(nameKey == name && containerKey == containerIdentifier.rawValue)

    if let row = try db.pluck(query) {
      return ItemRow(row)
    } else {
      return nil
    }
  }

  func items(in containerIdentifier: NSFileProviderItemIdentifier) throws -> [ItemRow] {
    let query = stateTable.filter(containerKey == containerIdentifier.rawValue)

    return try db.prepare(query).map { ItemRow($0) }
  }

  func isItemInSet(_ itemIdentifier: NSFileProviderItemIdentifier) throws -> Bool {
    try db.scalar(stateTable.filter(itemKey == itemIdentifier.rawValue).exists)
  }

  func isContentInSet(_ containerIdentifier: NSFileProviderItemIdentifier) throws -> Bool {
    try db.scalar(stateTable.filter(containerKey == containerIdentifier.rawValue).exists)
  }

  func containersInSet() throws -> [NSFileProviderItemIdentifier] {
    try db.prepare(stateTable.select(distinct: containerKey)).map {
      ItemRow($0).item
    }
  }

  func updateItem(_ row: ItemRow) throws -> [ItemRow] {
    log.debug("updateItem \(row.containerPath) \(row.name)")

    var deletedItems: [ItemRow] = []

    try transaction("updateItem") {
      // Check if an item with the same name and container already exists
      let itemInContainerQuery = stateTable.filter(nameKey == row.name && containerKey == row.container.rawValue)

      if let existingRow = try db.pluck(itemInContainerQuery) {
        let existingItem = ItemRow(existingRow)

        // If replacing a different item, delete the old one and its sub-items if it's a container
        if existingItem.item != row.item {
          if existingItem.isContainer {
            log.debug("Item is replacing container \(existingItem.item.rawValue)")
            let subItems = try deleteOldRowsNotInNewSet(within: existingItem.blinkIdentifier(), newSet: [])
            deletedItems.append(contentsOf: subItems)
          }
          deletedItems.append(existingItem)
          try db.run(itemInContainerQuery.delete())
        }
      }

      // Handle rename if the item is a container and its path or name has changed
      if let existingItem = try item(row.item), existingItem.isContainer {
        let isPathOrNameChanged = existingItem.containerPath != row.containerPath || existingItem.name != row.name
        if isPathOrNameChanged {
          let previousPath = (existingItem.containerPath as NSString).appendingPathComponent(existingItem.name)
          let newPath = (row.containerPath as NSString).appendingPathComponent(row.name)
          log.debug("Item is renaming \(previousPath) -> \(newPath)")
          try moveOldRows(within: previousPath, to: newPath)
        }
      }

      // Insert or replace the item
      let upsert = stateTable.insert(or: .replace,
                                     itemKey <- row.item.rawValue,
                                     nameKey <- row.name,
                                     containerKey <- row.container.rawValue,
                                     containerPathKey <- row.containerPath,
                                     versionKey <- row.version.contentVersion,
                                     anchorKey <- row.anchor,
                                     isContainerKey <- row.isContainer)
      try db.run(upsert)
    }

    return deletedItems
  }

  func updateItemsInContainer(_ blinkIdentifier: BlinkFileItemIdentifier, items: [ItemRow]) throws -> [ItemRow] {
    var deletedRows: [ItemRow] = []
    try transaction("updateItems") {
      log.debug("updateItems \(items.count) InContainer \(blinkIdentifier.path)")

      let newSet = items.map { $0.name }
      deletedRows = try deleteOldRowsNotInNewSet(within: blinkIdentifier, newSet: newSet)

      for row in items {
        let upsert = stateTable.insert(or: .replace,
                                       itemKey <- row.item.rawValue,
                                       nameKey <- row.name,
                                       containerKey <- row.container.rawValue,
                                       containerPathKey <- row.containerPath,
                                       versionKey <- row.version.contentVersion,
                                       anchorKey <- row.anchor,
                                       isContainerKey <- row.isContainer)
        try db.run(upsert)
      }
    }
    return deletedRows
  }

  func updateChangedItems(createRows: [ItemRow] = [],
                          updateRows: [ItemRow] = [],
                          deleteRows: [ItemRow] = []) throws -> [ItemRow] {
    var deletedRows = deleteRows
    try transaction("updateChangedItems") {
      log.debug("updateChangedItems create \(createRows.count) update: \(updateRows.count) delete: \(deleteRows.count)")

      // Weird case. A container transforms into a regular file. The contents should be marked for deletion.
      // This should be handled by the update algorithm. The change is a delete of the previous file type (dir) and then an update of a file type (regfile).
      for row in deleteRows {
        if row.isContainer {
          let container = row.blinkIdentifier()
          let deleted = try deleteOldRowsNotInNewSet(within: container, newSet: [])
          deletedRows.append(contentsOf: deleted)
        }
        try db.run(stateTable.filter(itemKey == row.item.rawValue).delete())
      }

      for row in createRows {
        let insert = stateTable.insert(
          itemKey <- row.item.rawValue,
          nameKey <- row.name,
          containerKey <- row.container.rawValue,
          containerPathKey <- row.containerPath,
          versionKey <- row.version.contentVersion,
          anchorKey <- row.anchor,
          isContainerKey <- row.isContainer
        )
        try db.run(insert)
      }

      for row in updateRows {
        let update = stateTable.filter(itemKey == row.item.rawValue)
          .update(
          nameKey <- row.name,
          containerKey <- row.container.rawValue,
          containerPathKey <- row.containerPath,
          versionKey <- row.version.contentVersion,
          anchorKey <- row.anchor,
          isContainerKey <- row.isContainer
        )
        try db.run(update)
      }
    }
    return deletedRows
  }

  func newestAnchor() throws -> Int {
    do {
      return try db.scalar(stateTable.select(anchorKey.max)) ?? 0
    } catch {
      log.error("Could not get anchor: \(error)")
      throw error
    }
  }

  private func deleteOldRowsNotInNewSet(within container: BlinkFileItemIdentifier, newSet: [String]) throws -> [ItemRow] {
    // Fetch rows under the given path level.
    var deletedRows: [ItemRow] = []

    let containerItemsQuery = stateTable.filter(containerPathKey == container.path)

    log.debug("deleteOldRowsNotInNewSet for \(container.path)")

    for row in try db.prepare(containerItemsQuery) {
      let itemName = row[nameKey]
      if !newSet.contains(itemName) {
        log.debug("\(itemName) - deleted")
        if row[isContainerKey] == true {
          let subPath = (row[containerPathKey] as NSString).appendingPathComponent(itemName)
          let subPathQuery = stateTable.filter(containerPathKey.like("\(subPath)%"))
          let subPathRows = try db.prepareRowIterator(subPathQuery).map { subRow in
            let itemRow = ItemRow(subRow)
            log.debug("\(itemRow.containerPath) \(itemRow.name) - deleted")
            return itemRow
          }

          if !subPathRows.isEmpty {
            try db.run(subPathQuery.delete())
            deletedRows.append(contentsOf: subPathRows)
          }
        }

        try db.run(stateTable.filter(itemKey == row[itemKey]).delete())
        deletedRows.append(ItemRow(row))
      } else {
        log.debug("\(itemName) - in new set")
      }
    }

    return deletedRows
  }

  func moveOldRows(within containerPath: String, to newPath: String) throws {
    // Find all rows under the specified containerPath
    let subItemsQuery = stateTable.filter(containerPathKey.like("\(containerPath)%"))

    for row in try db.prepare(subItemsQuery) {
      let currentPath = row[containerPathKey]

      // Replace the portion of the path from previousPath with newPath
      let updatedPath = currentPath.replacingOccurrences(of: containerPath, with: newPath, options: .anchored)
      log.debug("moveOldRow - \(currentPath) -> \(updatedPath)")
      let updateQuery = stateTable.filter(itemKey == row[itemKey]).update(containerPathKey <- updatedPath)
      try db.run(updateQuery)
    }
  }


  private static func hasDatabaseVersionChanged(at path: String) throws -> Bool {
    let tmpDB = try Connection(path)
    return tmpDB.userVersion != dbVersion
  }

  private func transaction(_ name: String, block: () throws -> Void) throws {
    do {
      try db.transaction {
        try block()
      }
    } catch {
      log.error("\(name) - \(error)")
      throw error
    }
  }
}

public struct ItemRow {
  let item: NSFileProviderItemIdentifier
  let name: String
  let container: NSFileProviderItemIdentifier
  let containerPath: String
  let version: NSFileProviderItemVersion
  let anchor: Int
  let isContainer: Bool

  init(item: NSFileProviderItemIdentifier,
       name: String,
       container: NSFileProviderItemIdentifier,
       containerPath: String,
       version: NSFileProviderItemVersion,
       isContainer: Bool,
       anchor: Int) {
    self.item = item
    self.name = name
    self.container = container
    self.containerPath = containerPath
    self.version = version
    self.isContainer = isContainer
    self.anchor = anchor
  }

  init(_ row: Row) {
    self.item = NSFileProviderItemIdentifier(row[itemKey])
    self.name = row[nameKey]
    self.container = NSFileProviderItemIdentifier(row[containerKey])
    self.containerPath = row[containerPathKey]
    self.version = NSFileProviderItemVersion(contentVersion: row[versionKey], metadataVersion: row[versionKey])
    self.isContainer = row[isContainerKey]
    self.anchor = row[anchorKey]
  }

}

extension ItemRow {
  static func from(_ fileItem: FileProviderItem, at anchorIteration: Int) -> Self {
    ItemRow(item: fileItem.itemIdentifier,
            name: fileItem.filename,
            container: fileItem.parentItemIdentifier,
            containerPath: fileItem.parentPath,
            version: fileItem.itemVersion,
            isContainer: fileItem.contentType == .directory,
            anchor: anchorIteration)
  }
  func blinkIdentifier() -> BlinkFileItemIdentifier {
    BlinkFileItemIdentifier(with: self.item, name: self.name, parentIdentifier: self.container, parentPath: self.containerPath)
  }
}
