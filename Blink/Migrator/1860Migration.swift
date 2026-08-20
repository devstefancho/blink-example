////////////////////////////////////////////////////////////////////////////////
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

import Foundation

class MigrationStyleFromDefaults: MigrationStep {
  var version: Int { 1860 }

  func execute() throws {
    BLKDefaults.loadDefaults()

    let legacy = BLKDefaults.legacyInstance()!
    let store = TerminalStyleStore.shared
    let builtIn = TerminalStyle.makeBuiltInDefault()

    // Read from the raw defaults instance (bypasses TerminalStyleStore bridge)
    let custom = TerminalStyle(
      id: UUID(),
      name: "Custom",
      themeName: legacy.themeName ?? builtIn.themeName,
      fontName: legacy.fontName ?? builtIn.fontName,
      fontSize: CGFloat(legacy.fontSize?.intValue ?? Int(builtIn.fontSize)),
      cursorBlink: legacy.cursorBlink,
      boldMode: TerminalStyle.BoldMode(rawValue: Int(legacy.enableBold)) ?? .auto,
      boldAsBright: legacy.boldAsBright
    )
    store.addStyle(custom)
    store.setSelected(custom.id)

    // Clear style properties on the raw instance so they don't linger.
    // Store is now the source of truth for these values.
    legacy.themeName = nil
    legacy.fontName = nil
    legacy.fontSize = nil
    legacy.cursorBlink = false
    legacy.enableBold = 0
    legacy.boldAsBright = false
    BLKDefaults.save()
  }
}
