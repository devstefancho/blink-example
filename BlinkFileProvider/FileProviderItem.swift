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


import BlinkFiles
import FileProvider
import UniformTypeIdentifiers

class FileProviderItem: NSObject, NSFileProviderItem {
  let blinkIdentifier: BlinkFileItemIdentifier
  private let attributes: BlinkFiles.FileAttributes

  init(blinkIdentifier: BlinkFileItemIdentifier, attributes: BlinkFiles.FileAttributes) {
    self.blinkIdentifier = blinkIdentifier

    let fileType = attributes[.type] as? FileAttributeType
    if fileType == .typeSymbolicLink,
       let targetAttributes = attributes[.symbolicLinkTargetInfo] as? BlinkFiles.FileAttributes {
      // For purposes of the Provider, the attributes the attributes are those of the target, except the symlink name.
      var attrs = targetAttributes
      attrs[.name] = attributes[.name] as! String
      self.attributes = attrs
    } else {
      self.attributes = attributes
    }
  }

  var itemIdentifier: NSFileProviderItemIdentifier {
    return blinkIdentifier.itemIdentifier
  }

  var parentItemIdentifier: NSFileProviderItemIdentifier {
    return blinkIdentifier.parentIdentifier
  }

  var parentPath: String {
    return blinkIdentifier.parentPath
  }

  var itemVersion: NSFileProviderItemVersion {
    let ts = (attributes[.modificationDate] as? NSDate)?.timeIntervalSince1970 ?? 0
    return NSFileProviderItemVersion(contentVersion: "\(ts)".data(using: .utf8)!,
                                     metadataVersion: "\(ts)".data(using: .utf8)!)
  }

  var filename: String {
    if blinkIdentifier.itemIdentifier == .rootContainer {
      return "/"
    }
    return attributes[.name] as! String
  }

  var contentType: UTType {
    guard let type = self.attributes[.type] as? FileAttributeType else {
      return UTType.data
    }

    if type == .typeDirectory {
      return UTType.directory
    }

    let pathExtension = (filename as NSString).pathExtension
    if let type = UTType(filenameExtension: pathExtension) {
      return type
    } else {
      return UTType.item
    }
  }

  var documentSize: NSNumber? { attributes[.size] as? NSNumber }
  var creationDate: Date? { attributes[.creationDate] as? Date }
  var contentModificationDate: Date? { attributes[.modificationDate] as? Date }

  var permissions: PosixPermissions? {
    guard let perm = attributes[.posixPermissions] as? NSNumber else {
      return nil
    }
    return PosixPermissions(rawValue: perm.int16Value)
  }

  var capabilities: NSFileProviderItemCapabilities {
    guard let permissions = self.permissions else {
      return []
    }

    var c = NSFileProviderItemCapabilities()
    if contentType == .directory || contentType == .folder {
      c.formUnion(.allowsAddingSubItems)
      if permissions.contains(.ux) {
        c.formUnion([.allowsContentEnumerating, .allowsReading])
      }
      if permissions.contains(.uw) {
        c.formUnion([.allowsRenaming, .allowsDeleting])
      }
    } else {
      if permissions.contains(.ur) {
        c.formUnion(.allowsReading)
      }
      if permissions.contains(.uw) {
        c.formUnion([.allowsWriting, .allowsDeleting, .allowsRenaming, .allowsReparenting])
      }
    }

    return c
  }
}

extension FileProviderItem {
  func isContentMoreRecent(than otherVersion: NSFileProviderItemVersion) -> Bool {
    guard let currentTimestamp = Double(String(data: itemVersion.contentVersion, encoding: .utf8) ?? ""),
          let otherTimestamp = Double(String(data: otherVersion.contentVersion, encoding: .utf8) ?? "") else {
      return false
    }
    return currentTimestamp > otherTimestamp
  }
}

class BlinkFileItemIdentifier {
  // Idea is to exchange the NSFileProviderItemIdentifier for a proper BlinkItemIdentifier, which
  // covers this previous functionality.
  let itemIdentifier: NSFileProviderItemIdentifier
  let parentIdentifier: NSFileProviderItemIdentifier
  let path: String
  let name: String
  let parentPath: String
  var rawValue: String { itemIdentifier.rawValue }
  var description: String { path.isEmpty ? "root" : path}

  static let rootContainer = BlinkFileItemIdentifier(with: .rootContainer, name: "", parentIdentifier: .rootContainer, parentPath: "")

  init(with rawIdentifier: NSFileProviderItemIdentifier, name: String, parentIdentifier: NSFileProviderItemIdentifier, parentPath: String) {
    self.itemIdentifier = rawIdentifier
    self.name = name
    self.parentIdentifier = parentIdentifier
    self.parentPath = parentPath
    self.path = (parentPath as NSString).appendingPathComponent(name)
  }

  convenience init(with rawIdentifier: NSFileProviderItemIdentifier, name: String, parent: BlinkFileItemIdentifier) {
    self.init(with: rawIdentifier, name: name, parentIdentifier: parent.itemIdentifier, parentPath: parent.path)
  }

  func isRoot() -> Bool { itemIdentifier == .rootContainer }

  func renamedItem() -> BlinkFileItemIdentifier {
    let pattern = #"^(.*?)(?: (\d+))?$"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(name.startIndex..., in: name)

    if let match = regex.firstMatch(in: name, range: range) {
      let base = (match.range(at: 1).location != NSNotFound) ? String(name[Range(match.range(at: 1), in: name)!]).trimmingCharacters(in: .whitespaces) : name
      let number = (match.range(at: 2).location != NSNotFound) ? (Int(name[Range(match.range(at: 2), in: name)!]) ?? 1) + 1 : 2
      return BlinkFileItemIdentifier(with: self.itemIdentifier,
                                     name: "\(base) \(number)",
                                     parentIdentifier: self.parentIdentifier,
                                     parentPath: self.parentPath)
    }
    return BlinkFileItemIdentifier(with: self.itemIdentifier,
                                   name: "\(name) 2",
                                   parentIdentifier: self.parentIdentifier,
                                   parentPath: self.parentPath)
  }

  static func generate(name: String, parent: BlinkFileItemIdentifier, isSymbolicLink: Bool = false) -> BlinkFileItemIdentifier {
    var identifier = NSFileProviderItemIdentifier.shortUUID()
    if isSymbolicLink {
      identifier = NSFileProviderItemIdentifier(rawValue: "@" + identifier.rawValue.dropFirst())
    }
    return BlinkFileItemIdentifier(with: identifier, name: name, parent: parent)
  }
}

extension NSFileProviderItemIdentifier {
  static func shortUUID() -> Self {
    NSFileProviderItemIdentifier(rawValue: String(UUID().uuidString.prefix(13)))
  }

  func isSymbolicLink() -> Bool { self.rawValue.starts(with: "@") }
}

struct PosixPermissions: OptionSet {
  let rawValue: Int16 // It is really a CShort

  // rwx
  // u[ser]
  static let ur = PosixPermissions(rawValue: 1 << 8)
  static let uw = PosixPermissions(rawValue: 1 << 7)
  static let ux = PosixPermissions(rawValue: 1 << 6)

  // g[roup]
  static let gr = PosixPermissions(rawValue: 1 << 5)
  static let gw = PosixPermissions(rawValue: 1 << 4)
  static let gx = PosixPermissions(rawValue: 1 << 3)

  // o[ther]
  static let or = PosixPermissions(rawValue: 1 << 2)
  static let ow = PosixPermissions(rawValue: 1 << 1)
  static let ox = PosixPermissions(rawValue: 1 << 0)
}
