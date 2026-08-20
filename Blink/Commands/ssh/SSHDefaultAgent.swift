//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
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
import SSH


final class SSHDefaultAgent {
  public static var instance: SSHAgent? {
    if let agent = Self._instance {
      return agent
    } else {
      return Self.load()
    }
  }
  private static var _instance: SSHAgent? = nil
  private init() {}
  // The pool is responsible for the location of Agents.
  private static let defaultAgentFile: URL = BlinkPaths.blinkAgentSettingsURL().appendingPathComponent("default")

  enum Error: Swift.Error, LocalizedError {
    case KeyIsMissing

    var localizedDescription: String {
      switch self {
      case .KeyIsMissing:
        "Key is missing"
      }
    }
  }

  // Load the (default) agent in the pool. If the Agent cannot be loaded, it will be unavailable (nil).
  // If the agent doesn't exist, it will be initialized (default only).
  private static func load() -> SSHAgent? {
    do {
      if let settings = try getSettings() {
        try setAgentInstance(with: settings)
      } else {
        try setSettings(BKAgentSettings())
      }
    } catch {
      return nil
    }

    return Self._instance
  }

  // Create the settings for the agent and load it in the pool.
  // NOTE: For non-default agents, this would be the main initialization method.
  static func setSettings(_ settings: BKAgentSettings) throws {
    try BKAgentSettings.save(settings: settings, to: defaultAgentFile)
    try setAgentInstance(with: settings)
  }

  private static func setAgentInstance(with settings: BKAgentSettings) throws {
    let bkConfig = try BKConfig()

    let agent: SSHAgent
    if let _instance = Self._instance {
      agent = _instance
      agent.clear()
    } else {
      agent = SSHAgent()
      Self._instance = agent
    }

    settings.keys.forEach { key in
      if let (signer, name) = bkConfig.signer(forIdentity: key) {
        if let constraints = settings.constraints() {
          agent.loadKey(signer, aka: name, constraints: constraints)
        }
      }
    }
  }

  static func getSettings() throws -> BKAgentSettings? {
    try BKAgentSettings.read(from: defaultAgentFile)
  }

  // Applying settings clears the agent first. Adding a key doesn't modify or reset previous constraints.
  static func addKey(named keyName: String) throws {
    guard let agent = Self.instance,
          let settings = try getSettings() else {
      return
    }

    if settings.keys.contains(keyName) {
      return
    }

    let bkConfig = try BKConfig()

    if let (signer, name) = bkConfig.signer(forIdentity: keyName) {
      var keys = settings.keys
      keys.append(keyName)
      let newSettings = BKAgentSettings(prompt: settings.prompt, keys: keys)

      do {
        try BKAgentSettings.save(settings: newSettings, to: defaultAgentFile)
      } catch {
      }

      if let constraints = settings.constraints() {
        agent.loadKey(signer, aka: keyName, constraints: constraints)
      }
    } else {
      throw Error.KeyIsMissing
    }
  }

  static func removeKey(named keyName: String) throws -> Signer? {
    // Remove from settings and apply
    guard let agent = Self.instance,
          let settings = try getSettings(),
          settings.keys.contains(keyName) else {
      return nil
    }

    var keys = settings.keys
    keys.removeAll(where: { $0 == keyName })
    try BKAgentSettings.save(settings: BKAgentSettings(prompt: settings.prompt, keys: keys), to: defaultAgentFile)

    return agent.removeKey(keyName)
  }
}

// NOTE Another way to represent the Agent would be to just share the current state by reading the file,
// instead of having the state stored in a variable. This would be best for concurrency too, but that shouldn't
// be a problem now.

enum BKAgentSettingsPrompt: String, Codable {
  case Deny = "Deny"
  case Confirm = "Confirm"
  case Allow = "Allow"
}

struct BKAgentSettings: Codable, Equatable {
  let prompt: BKAgentSettingsPrompt
  let keys: [String]

  init(prompt: BKAgentSettingsPrompt, keys: [String]) {
    self.prompt = prompt
    self.keys = keys
  }

  init() { self = Self(prompt: .Confirm, keys: []) }

  static func save(settings: BKAgentSettings, to file: URL) throws {
    let data = try JSONEncoder().encode(settings)
    try data.write(to: file)
  }

  fileprivate static func read(from file: URL) throws -> BKAgentSettings? {
    guard FileManager.default.fileExists(atPath: file.path) else {
      return nil
    }
    let data = try Data(contentsOf: file)
    return try JSONDecoder().decode(BKAgentSettings.self, from: data)
  }

  func constraints() -> [SSHAgentConstraint]? {
    return switch prompt {
    case .Confirm:
      [SSHAgentUserPrompt()]
    case .Allow:
      []
    default:
      nil
    }
  }
}
