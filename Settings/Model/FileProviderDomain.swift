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
import FileProvider

#if targetEnvironment(macCatalyst)

struct _NSFileProviderDomainIdentifier {
  let rawValue: String
  init(rawValue: String) {
    self.rawValue = rawValue
  }
}


class _NSFileProviderDomain {
  let identifier: _NSFileProviderDomainIdentifier
  let displayName: String
  let pathRelativeToDocumentStorage: String

  init(identifier: _NSFileProviderDomainIdentifier, displayName: String) {
    self.identifier = identifier
    self.displayName = displayName
    //self.pathRelativeToDocumentStorage = pathRelativeToDocumentStorage
  }
}

@objc class _NSFileProviderManager: NSObject {
  static func add(_ domain: _NSFileProviderDomain, callback: @escaping (NSError?) -> ()) {
    callback(nil)
  }

  static func remove(_ domain: _NSFileProviderDomain, callback: @escaping (NSError?) -> ()) {
    callback(nil)
  }

  static func getDomainsWithCompletionHandler(_ callback: @escaping ([_NSFileProviderDomain], NSError?) -> ()) {
    callback([], nil)
  }
}

#else

public typealias _NSFileProviderDomain = NSFileProviderDomain
@objc class _NSFileProviderManager: NSFileProviderManager {

}
public typealias _NSFileProviderDomainIdentifier = NSFileProviderDomainIdentifier

#endif


class FileProviderDomain: Identifiable, Codable, Equatable {
  static func == (lhs: FileProviderDomain, rhs: FileProviderDomain) -> Bool {
    lhs.id == rhs.id &&
      lhs.displayName == rhs.displayName &&
      lhs.remotePath == rhs.remotePath &&
      lhs.proto == rhs.proto
  }

  var id: UUID
  var displayName: String
  var remotePath: String
  var proto: String
  // ReplicatedExtension is the only available extension since 18.1.0, but we leave the other in case
  // the Migrator fails and the provider falls behind, the user can still change it.
  var useReplicatedExtension: Bool = true
  // Alias is not part of the domain as we don't want to serialize it under the host itself.
  
  init(id: UUID, displayName: String, remotePath: String, proto: String, useReplicatedExtension: Bool) {
    self.id = id
    self.displayName = displayName
    self.remotePath = remotePath
    self.proto = proto
    self.useReplicatedExtension = useReplicatedExtension
  }

  func nsFileProviderDomain(alias: String) -> _NSFileProviderDomain? {
    if useReplicatedExtension {
      guard let identifier = _replicatedExtensionIdentifierFor(alias: alias) else {
        return nil
      }
      return _NSFileProviderDomain(
        identifier: identifier,
        displayName: displayName
      )
    } else {
      // Since 18.1.0, this is just a fallthrough. Do not return the old FPE extension.
      return nil
    }
  }

  func connectionPathFor(alias: String) -> String {
    "\(proto):\(alias):\(remotePath)"
  }

  func encodedPathFor(alias: String) -> String? {
    "\(connectionPathFor(alias: alias))".data(using: .utf8)?.base64EncodedString() ?? ""
  }

  func _replicatedExtensionIdentifierFor(alias: String) -> _NSFileProviderDomainIdentifier? {
    let id = self.id.uuidString.prefix(8)
    guard let encodedPath = "\(proto):\(alias):\(remotePath)".data(using: .utf8)?.base64EncodedString() else {
      return nil
    }
    return _NSFileProviderDomainIdentifier(rawValue: "\(id)-\(encodedPath)")
  }

  static func listFrom(jsonString: String?) -> [FileProviderDomain] {
    guard
      let str = jsonString,
      !str.isEmpty,
      let data = str.data(using: .utf8),
      let arr = try? JSONDecoder().decode([FileProviderDomain].self, from: data)
    else {
      return []
    }

    return arr
  }

  static func toJson(list: [FileProviderDomain]) -> String {
    guard !list.isEmpty else {
      return ""
    }

    let data = try? JSONEncoder().encode(list)
    guard
      let data = data,
      let str = String(data: data, encoding: .utf8)
    else {
      return ""
    }

    return str
  }

  static func _syncDomainsForAllHosts(installedDomains: [_NSFileProviderDomain]) {
    var domainsMap = [String : (alias: String, domain: FileProviderDomain)]()
    var hostsMap = [String : BKHosts]()
    var keysMap = [String : BKPubKey]()

    for host in BKHosts.allHosts() {
      guard let json = host.fpDomainsJSON, !json.isEmpty
      else {
        continue
      }

      let domains = FileProviderDomain.listFrom(jsonString: json)
      for domain in domains {
        // Use prefix so we can map both replicated and regular domains.
        let subId = String(domain.id.uuidString.prefix(8))
        domainsMap[subId] = (alias: host.host, domain: domain)
      }

      if hostsMap[host.host] == nil {
        hostsMap[host.host] = host
        if let key = host.key, !key.isEmpty, key != "None", let sshKey = BKPubKey.withID(key) {
          keysMap[key] = sshKey
        }
      }
    }

    var domainsToRemove: [_NSFileProviderDomain] = []
    for d in installedDomains {
      let subId = String(d.identifier.rawValue.prefix(8))
      if let blinkDomain = domainsMap.removeValue(forKey: subId) {
        if !d.isReplicated || // Transition from old to new FPE
            blinkDomain.domain.displayName != d.displayName ||
            blinkDomain.domain._replicatedExtensionIdentifierFor(alias: blinkDomain.alias)?.rawValue != d.identifier.rawValue {
          domainsToRemove.append(d)
          domainsMap[subId] = blinkDomain
        }
      }
      else {
        domainsToRemove.append(d)
      }
    }

    for nsDomain in domainsToRemove {
      _NSFileProviderManager.remove(nsDomain) { err in
        if let err = err {
          print("failed to remove domain", err)
        } else if nsDomain.isReplicated {
          let reference = String(nsDomain.identifier.rawValue.prefix(8))
          _NSFileProviderManager.clearFileProviderReplicatedWorkingSet(for: reference)
        }
      }
    }

    for (_, value) in domainsMap {
      if let domain = value.domain.nsFileProviderDomain(alias: value.alias) {
        _NSFileProviderManager.add(domain) { err in
          if let err = err {
            print("failed to add domain", err)
            return
          }
        }
      }
    }
  }
}

extension _NSFileProviderManager {
  @objc static func syncWithBKHosts() {
    getDomainsWithCompletionHandler { nsDomains, err in
      guard err == nil else {
        print("get domains error", err!)
        return
      }
      FileProviderDomain._syncDomainsForAllHosts(installedDomains: nsDomains)
    }
  }

  static func clearFileProviderReplicatedWorkingSet(for reference: String) {
    let path = BlinkPaths.fileProviderReplicatedURL().appendingPathComponent("\(reference).db")
    try? FileManager.default.removeItem(at: path)
  }
}
