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
import Combine
import FileProvider

extension FileProviderReplicatedExtension {
  func _statItem(_ blinkIdentifier: BlinkFileItemIdentifier,
                 log: BlinkLogger,
                 completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
    let progress = Progress(totalUnitCount: 1)

    var itemCancellable: AnyCancellable? = self._itemTranslator(for: blinkIdentifier)
      .flatMap { $0.stat() }
      .tryMap {
        let item = FileProviderItem(blinkIdentifier: blinkIdentifier, attributes: $0)
        try self.workingSet.commitItemInSet(item)
        return item
      }
      .sink(receiveCompletion: { completion in
        if case let .failure(error) = completion {
          log.info("Failed - \(error)")
          completionHandler(nil, error)
        }
      }, receiveValue: { (item: FileProviderItem) in
        progress.completedUnitCount = 1
        log.info("Found \(item.parentPath) \(item.filename)")
        completionHandler(item, nil)
      })

    progress.cancellationHandler = {
      itemCancellable?.cancel()
      itemCancellable = nil
      completionHandler(nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
    return progress
  }

  func _downloadItem(fileItem: FileProviderItem, log: BlinkLogger, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
    log.info("Downloading file \(fileItem.filename)...")
    let progress = Progress(totalUnitCount: fileItem.documentSize?.int64Value ?? -1)

    let srcTranslator = self._itemTranslator(for: fileItem.blinkIdentifier)
    let destinationURL = self._makeTemporaryFile()
    let destTranslator = Local().cloneWalkTo(destinationURL.path)

    var totalWritten: Int64 = 0
    var copyCancellable: AnyCancellable? = srcTranslator
      .flatMap { fileTranslator in
        destTranslator.flatMap { $0.copy(from: [fileTranslator],
                                         args: self.copyArguments) }
      }
      .sink(
        receiveCompletion: { completion in
          switch completion {
          case .finished:
            log.info("Download Completed")
            progress.completedUnitCount = progress.totalUnitCount
            completionHandler(destinationURL, fileItem, nil)
          case .failure(let error):
            log.error("Download file error: \(error)")
            completionHandler(nil, nil, error)
          }
        },
        receiveValue: { copyProgressInfo in
          log.debug("Download progress: \(copyProgressInfo)")
          progress.totalUnitCount = Int64(copyProgressInfo.size)
          totalWritten += Int64(copyProgressInfo.written)
          progress.completedUnitCount = totalWritten
        }
      )

    progress.cancellationHandler = {
      log.warn("Download cancelled by user")
      copyCancellable?.cancel()
      copyCancellable = nil
      completionHandler(nil, nil, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    return progress
  }

  private func _makeTemporaryFile() -> URL {
    let url = temporaryDirectoryURL.appending(path: "\(UUID().uuidString)")
    // Shouldn't fail at this point (random file on temporary directory)
    let _ = FileManager.default.createFile(atPath: url.path, contents: nil)
    return url
  }

  func _createItem(basedOn itemTemplate: NSFileProviderItem,
                   inParent parentIdentifier: BlinkFileItemIdentifier,
                   fields: NSFileProviderItemFields,
                   contents url: URL,
                   options: NSFileProviderCreateItemOptions = [],
                   request: NSFileProviderRequest,
                   log: BlinkLogger,
                   completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
    let fileName = itemTemplate.filename
    let itemPath = (parentIdentifier.path as NSString).appendingPathComponent(fileName)
    log.info("Creating file \(itemPath)...")

    let tmpFileName = ".blink.tmp.\(url.lastPathComponent)"

    let sourceTranslator = Local().cloneWalkTo(url.path)
    let destTranslator = self.rootTranslator
    //let destTranslator = self._itemTranslator(for: parentIdentifier)

    var totalWritten: Int64 = 0

    let totalProgress = Progress(totalUnitCount: 110)
    let uploadProgress = Progress(totalUnitCount: itemTemplate.documentSize??.int64Value ?? -1)
    let statProgress = Progress(totalUnitCount: 10)
    totalProgress.addChild(uploadProgress, withPendingUnitCount: 100)
    totalProgress.addChild(statProgress, withPendingUnitCount: 10)

    var copyCancellable: AnyCancellable? =
      self._ensureCanCreateFile(name: fileName,
                                containerIdentifier: parentIdentifier,
                                updateAlreadyExisting: options.contains(.mayAlreadyExist),
                                log: log)
      .flatMap { _ -> CopyProgressInfoPublisher in
        log.debug("Copy file \(tmpFileName)...")
        return Publishers.Zip(sourceTranslator, destTranslator)
          .flatMap { (sourceFile, destination) -> CopyProgressInfoPublisher in
            destination.copy(from: sourceFile, newName: tmpFileName, args: self.copyArguments)
          }.eraseToAnyPublisher()
      }
      .filter { copyProgressInfo in
        log.debug("Upload progress: \(copyProgressInfo.name), written: \(totalWritten), size: \(copyProgressInfo.size)")
        totalWritten += Int64(copyProgressInfo.written)
        uploadProgress.totalUnitCount = Int64(copyProgressInfo.size)
        uploadProgress.completedUnitCount = totalWritten
        return copyProgressInfo.size == totalWritten
      }
      .first()
      .flatMap { _ in
        destTranslator.flatMap { $0.cloneWalkTo(tmpFileName) }
          .flatMap { tmpFileTranslator in
            log.debug("Attributes from \(tmpFileName) to \(fileName)")
            var newAttributes: BlinkFiles.FileAttributes = [:]
            newAttributes[.name] = (self.connection.rootTranslatorPath as NSString)
              .appendingPathComponent(itemPath)

            if fields.contains(.creationDate) {
              newAttributes[.creationDate] = itemTemplate.creationDate!
            }
            if fields.contains(.contentModificationDate) {
              newAttributes[.modificationDate] = itemTemplate.contentModificationDate!
            }

            return self.workingSet.commitItemInSet(itemPath: itemPath) {
              tmpFileTranslator.wstat(newAttributes)
              // Rename after upload should succeed. Otherwise, there are problems at the final container,
              // and retrying won't fix them.
                .mapError { error in
                  log.error("\(error)")
                  return NSFileProviderError(.cannotSynchronize)
                }
                .flatMap { _ in destTranslator.flatMap { $0.cloneWalkTo(itemPath) } }
                .flatMap {
                  log.debug("Fetching \(fileName) attributes")
                  return $0.stat()
                }
                .map {
                  let newIdentifier = BlinkFileItemIdentifier.generate(name: fileName, parent: parentIdentifier)
                  let createdItem = FileProviderItem(blinkIdentifier: newIdentifier, attributes: $0)
                  return createdItem
                }
                .eraseToAnyPublisher()
            }
          }
      }
      .sink(
        receiveCompletion: { completion in
          switch completion {
          case .finished:
            log.info("Creating file completed.")
          case .failure(let error):
            log.error("Creating file error: \(error)")
            if let error = error as? NSFileProviderError {
              completionHandler(nil, fields, false, error)
            } else {
              completionHandler(nil, fields, false, NSFileProviderError.operationError(dueTo: error))
            }
          }
        },
        receiveValue: { createdItem in
          completionHandler(createdItem,
                            [],
                            false,
                            nil
          )
        })

    totalProgress.cancellationHandler = {
      log.warn("Create cancelled by user")
      copyCancellable?.cancel()
      copyCancellable = nil
      completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
    return totalProgress
  }

  func _uploadItem(_ fileItem: NSFileProviderItem,
                   inParent parentIdentifier: BlinkFileItemIdentifier,
                   originalIdentifier: BlinkFileItemIdentifier,
                   baseVersion version: NSFileProviderItemVersion,
                   changedFields: NSFileProviderItemFields,
                   contents url: URL,
                   options: NSFileProviderModifyItemOptions = [],
                   request: NSFileProviderRequest,
                   log: BlinkLogger,
                   completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
    // NOTE The parent may be in a different location than the current item if it is also reparenting.
    let fileName = fileItem.filename
    let itemPath = (parentIdentifier.path as NSString).appendingPathComponent(fileName)
    log.info("Uploading file \(itemPath)")

    let tmpFileName = ".blink.tmp.\(url.lastPathComponent)"

    let sourceTranslator = Local().cloneWalkTo(url.path)
    let destTranslator = self.rootTranslator
    //let destTranslator = self._itemTranslator(for: parentIdentifier)

    var totalWritten: Int64 = 0

    let totalProgress = Progress(totalUnitCount: 110)
    let uploadProgress = Progress(totalUnitCount: fileItem.documentSize??.int64Value ?? -1)
    let statProgress = Progress(totalUnitCount: 10)
    totalProgress.addChild(uploadProgress, withPendingUnitCount: 100)
    totalProgress.addChild(statProgress, withPendingUnitCount: 10)

    var copyCancellable: AnyCancellable? =
      self._ensureCanReplaceItem(originalIdentifier: originalIdentifier,
                                 containerIdentifier: parentIdentifier,
                                 baseVersion: version,
                                 log: log)
      .flatMap { _ -> CopyProgressInfoPublisher in
        log.debug("Upload file \(tmpFileName)")
        return Publishers.Zip(sourceTranslator, destTranslator)
          .flatMap { (sourceFile, destination) in
            destination.copy(from: sourceFile, newName: tmpFileName, args: self.copyArguments)
          }.eraseToAnyPublisher()
      }
      .filter { copyProgressInfo in
        log.debug("Upload progress: \(copyProgressInfo)")
        totalWritten += Int64(copyProgressInfo.written)
        uploadProgress.totalUnitCount = Int64(copyProgressInfo.size)
        uploadProgress.completedUnitCount = totalWritten
        return copyProgressInfo.size == totalWritten
      }
      .first()
      .flatMap { _ in
        destTranslator.flatMap { $0.cloneWalkTo(tmpFileName) }
          .flatMap { tmpFileTranslator in
            log.debug("Attributes from \(tmpFileName) to \(fileName)")
            var newAttributes: BlinkFiles.FileAttributes = [:]
            newAttributes[.name] = (self.connection.rootTranslatorPath as NSString)
              .appendingPathComponent(itemPath)

            if changedFields.contains(.creationDate) {
              newAttributes[.creationDate] = fileItem.creationDate!
            }
            if changedFields.contains(.contentModificationDate) {
              newAttributes[.modificationDate] = fileItem.contentModificationDate!
            }

            return self.workingSet.commitItemInSet(itemPath: itemPath) {
              tmpFileTranslator.wstat(newAttributes)
                .mapError { error in
                  log.error("\(error)")
                  return NSFileProviderError(.cannotSynchronize)
                }
                .flatMap { _ in destTranslator.flatMap { $0.cloneWalkTo(itemPath) } }
                .flatMap {
                  log.debug("Fetching \(fileName) attributes")
                  return $0.stat()
                }
                .map {
                  let newIdentifier = BlinkFileItemIdentifier(with: originalIdentifier.itemIdentifier,
                                                              name: fileName,
                                                              parent: parentIdentifier)
                  let uploadedItem = FileProviderItem(blinkIdentifier: newIdentifier, attributes: $0)
                  return uploadedItem
                }
                .eraseToAnyPublisher()
            }
          }
      }
      .sink(
        receiveCompletion: { completion in
          switch completion {
          case .finished:
            log.info("Completed")
          case .failure(let error):
            log.error("Upload file error: \(error)")
            if let error = error as? NSFileProviderError {
              if error.code == .filenameCollision,
               let item = error.userInfo[NSFileProviderErrorItemKey] as? NSFileProviderItem {
                completionHandler(item, [], true, nil)
              } else {
                completionHandler(nil, changedFields, false, error)
              }
            } else {
              completionHandler(nil, changedFields, false, NSFileProviderError.operationError(dueTo: error))
            }
          }
        },
        receiveValue: { uploadedItem in
          // If the operation succeeded, the item has now been uploaded to the parent.
          // Commit will replace it and make sure it is unique.
          completionHandler(uploadedItem,
                            [],
                            false,
                            nil)

        })

    totalProgress.cancellationHandler = {
      log.warn("Updated cancelled by user")
      copyCancellable?.cancel()
      copyCancellable = nil
      completionHandler(nil, changedFields, false, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    return totalProgress
  }

  func _createFolder(withName name: String,
                     inParent parentIdentifier: BlinkFileItemIdentifier,
                     log: BlinkLogger,
                     completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
    let progress = Progress(totalUnitCount: 1)
    let parentPath = parentIdentifier.path
    log.info("Create folder \(name) at \(parentPath)")

    let parentTranslatorPublisher = self._itemTranslator(for: parentIdentifier)

    var createDirectoryCancellable: AnyCancellable? = parentTranslatorPublisher
      .flatMap { parentTranslator in
        parentTranslator.cloneWalkTo(name).catch { _ in
          parentTranslator.mkdir(name: name, mode: S_IRWXU | S_IRWXG | S_IRWXO)
        }
        .tryMap {
          if $0.isDirectory {
            return $0
          } else {
            throw NSFileProviderError(.filenameCollision)
          }
        }
      }
      .flatMap { $0.stat() }
      .sink(
        receiveCompletion: { completion in
          switch completion {
          case .finished:
            log.info("Create Directory completed")
          case .failure(let error):
            log.error("Create Directory error: \(error)")
            completionHandler(nil, [], false, error)
          }
        },
        receiveValue: { dirAttrs in
          progress.completedUnitCount = 1
          do {
            // If we fail here (rare), we will be out of sync and eventually trigger a resync.
            let createdFolderIdentifier = try self.workingSet.blinkIdentifier(itemName: name, container: parentIdentifier) ??
              BlinkFileItemIdentifier.generate(name: name, parent: parentIdentifier)
            let createdItem = FileProviderItem(blinkIdentifier: createdFolderIdentifier, attributes: dirAttrs)

            try self.workingSet.commitItemInSet(createdItem)
            completionHandler(createdItem,
                              [],
                              false,
                              nil
            )
          } catch {
            log.error("Could not commit item to WorkingSet")
            completionHandler(nil, [], false, error)
          }
        })

    progress.cancellationHandler = {
      log.warn("Upload cancelled by user")
      createDirectoryCancellable?.cancel()
      createDirectoryCancellable = nil
      completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    return progress
  }

  private func _ensureCanCreateFile(name: String,
                                    containerIdentifier: BlinkFileItemIdentifier,
                                    updateAlreadyExisting: Bool,
                                    log: BlinkLogger) -> AnyPublisher<Void, Error> {
    log.debug("Ensure can create file at \(containerIdentifier.path) with \(name)")
    // Ensure the container exists.
    // Flag collisions when detected.
    return self._itemTranslator(for: containerIdentifier)
      .flatMap {
        return $0.cloneWalkTo(name)
          .map(Optional.some)
          .catch { _ in Just(nil) }
      }
      .flatMap { (translator: Translator?) in
        if let translator = translator {
          log.debug("File exists, checking flags.")
          if updateAlreadyExisting {
            return translator.remove()
              .map { _ in () }
              .eraseToAnyPublisher()
          } else {
            return translator.stat().tryMap { attributes in
              var blinkIdentifier: BlinkFileItemIdentifier
              if let existingIdentifier = try self.workingSet.blinkIdentifier(itemName: name, container: containerIdentifier)  {
                blinkIdentifier = existingIdentifier
              } else {
                blinkIdentifier = BlinkFileItemIdentifier.generate(name: name, parent: containerIdentifier)
              }
              let item = FileProviderItem(blinkIdentifier: blinkIdentifier, attributes: attributes)
              try self.workingSet.commitItemInSet(item)
              throw NSError.fileProviderErrorForCollision(with: item)
            }.eraseToAnyPublisher()
          }
        } else {
          log.debug("No file. Can create.")
          return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
      }
      .eraseToAnyPublisher()
  }

  private func _ensureCanReplaceItem(originalIdentifier: BlinkFileItemIdentifier,
                                     containerIdentifier: BlinkFileItemIdentifier,
                                     baseVersion: NSFileProviderItemVersion,
                                     log: BlinkLogger) -> AnyPublisher<Void, Error> {
    log.debug("Ensure can replace \(originalIdentifier.path)")
    // Ensure the container exists.
    // Compare versions if the item exists.
    return self._itemTranslator(for: containerIdentifier)
      .flatMap { _ in
        return self.rootTranslator.flatMap {
          $0.cloneWalkTo(originalIdentifier.path)
            .map(Optional.some)
            .catch { _ in Just(nil) }
        }
      }
      .flatMap { (translator: Translator?) -> AnyPublisher<Void, Error> in
        if let translator = translator {
          return translator.stat().flatMap { attributes -> AnyPublisher<Void, Error> in
           let item = FileProviderItem(blinkIdentifier: originalIdentifier, attributes: attributes)
           if item.isContentMoreRecent(than: baseVersion) {
             log.debug("Remote is newer, flag to redownload")
//             return Fail(error: NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.cannotSynchronize.rawValue)).eraseToAnyPublisher()
             // The output of this error is that "an item already exists".
             // But in this scenario, the upper flow will capture it and indicate to download the new version.
             return Fail(error: NSError.fileProviderErrorForCollision(with: item)).eraseToAnyPublisher()
           }
           log.debug("Local is newer, upload.")
           return translator.remove()
             .map { _ in () }
             .eraseToAnyPublisher()
          }.eraseToAnyPublisher()
        } else {
          log.debug("No file. Upload as new.")
          return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
      }.eraseToAnyPublisher()
  }

  func _modifyItemAttributes(originalIdentifier: BlinkFileItemIdentifier,
                             baseVersion version: NSFileProviderItemVersion,
                             name: String? = nil,
                             parent: BlinkFileItemIdentifier? = nil,
                             creationDate: Date? = nil,
                             modificationDate: Date? = nil,
                             log: BlinkLogger,
                             completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void)
  -> Progress {
    log.info("Modifying item attributes for \(originalIdentifier.path)")
    let progress = Progress(totalUnitCount: 10)
    let originalItemPath = originalIdentifier.path

    var newAttributes: BlinkFiles.FileAttributes = [:]
    if let creationDate = creationDate {
      newAttributes[.creationDate] = creationDate
    }
    if let modificationDate = modificationDate {
      newAttributes[.modificationDate] = modificationDate
    }

    var newIdentifier: BlinkFileItemIdentifier = {
      let newFileName = name ?? originalIdentifier.name
      if let parent = parent {
        return BlinkFileItemIdentifier(with: originalIdentifier.itemIdentifier,
                                                name: newFileName,
                                                parent: parent)
      } else {
        return BlinkFileItemIdentifier(with: originalIdentifier.itemIdentifier,
                                       name: newFileName,
                                       parentIdentifier: originalIdentifier.parentIdentifier,
                                       parentPath: originalIdentifier.parentPath)
      }
    }()

    var modifyAttributesCancellable: AnyCancellable? =
    _ensureCanModifyItemAttributes(originalIdentifier: originalIdentifier,
                                   newItemIdentifier: newIdentifier,
                                   baseVersion: version)
    .flatMap { (newItemIdentifier: BlinkFileItemIdentifier, itemTranslator: Translator) -> AnyPublisher<FileProviderItem, Error> in
      newIdentifier = newItemIdentifier

      if parent != nil {
        // Path needs to be absolute as the provider doesn't take paths relative to root.
        newAttributes[.name] = (self.connection.rootTranslatorPath as NSString).appendingPathComponent(newIdentifier.path)
      } else if let _ = name {
        // Name may have changed for newIdentifier.
        newAttributes[.name] = newIdentifier.name
      }

      return self.workingSet.commitItemInSet(itemPath: newIdentifier.path) {
        return itemTranslator.wstat(newAttributes)
          .flatMap { _ in
            self.rootTranslator.flatMap {
              $0.cloneWalkTo(newIdentifier.path)
            }
          }
          .flatMap { $0.stat() }
          .map {
            let modifiedItem = FileProviderItem(blinkIdentifier: newIdentifier, attributes: $0)
            return modifiedItem
          }.eraseToAnyPublisher()
      }
    }
    .sink(receiveCompletion: { completion in
      switch completion {
      case .finished:
        log.info("Attributes modified")
        progress.completedUnitCount = progress.totalUnitCount
      case .failure(let error):
        log.error("Error modifying attributes (wstat): \(error)")
        if let error = error as? NSFileProviderError {
          completionHandler(nil, [], false, error)
        } else {
          // FP errors can be mapped to a specific blinkFileProviderError domain?
          completionHandler(nil, [], false, NSFileProviderError.operationError(dueTo: error))
        }
      }
    }, receiveValue: { modifiedItem in
        completionHandler(modifiedItem,
                          [],
                          false,
                          nil)
    })

    progress.cancellationHandler = {
      log.warn("Modify Attributes cancelled by user")
      modifyAttributesCancellable?.cancel()
      modifyAttributesCancellable = nil
      completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    return progress
  }

  private func _ensureCanModifyItemAttributes(originalIdentifier: BlinkFileItemIdentifier,
                                              newItemIdentifier: BlinkFileItemIdentifier,
                                              baseVersion: NSFileProviderItemVersion) -> AnyPublisher<(BlinkFileItemIdentifier, Translator), Error> {
    let maybeDestinationPublisher = rootTranslator.flatMap { t -> AnyPublisher<Translator?, Error> in
        newItemIdentifier.path != originalIdentifier.path
            ? t.cloneWalkTo(newItemIdentifier.path)
                .map(Optional.some)
                .catch { _ in Just(nil).setFailureType(to: Error.self) }
                .eraseToAnyPublisher()
      : Just(nil).setFailureType(to: Error.self).eraseToAnyPublisher()
    }

    return Publishers.Zip(_itemTranslator(for: originalIdentifier), maybeDestinationPublisher)
      .flatMap { (originalTranslator: Translator, maybeDestinationTranslator: Translator?) -> AnyPublisher<(BlinkFileItemIdentifier, Translator), Error> in
        if let destinationTranslator = maybeDestinationTranslator {
          let newItemIdentifier = newItemIdentifier.renamedItem()
          return self._ensureCanModifyItemAttributes(originalIdentifier: originalIdentifier,
                                                newItemIdentifier: newItemIdentifier,
                                                baseVersion: baseVersion)
        }

        return Just((newItemIdentifier, originalTranslator)).setFailureType(to: Error.self).eraseToAnyPublisher()
//        return originalTranslator.stat().tryMap { attributes -> (BlinkFileItemIdentifier, Translator) in
//          let item = FileProviderItem(blinkIdentifier: originalIdentifier, attributes: attributes)
//          if (item.contentType == .directory || item.contentType == .folder || item.itemVersion.contentVersion == baseVersion.contentVersion) {
//            return (newItemIdentifier, originalTranslator)
//          } else {
//            //throw NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.cannotSynchronize.rawValue)
//            throw NSError.fileProviderErrorForCollision(with: item)
//          }
//        }.eraseToAnyPublisher()
      }.eraseToAnyPublisher()
  }

  private func _itemTranslator(for blinkIdentifier: BlinkFileItemIdentifier) -> TranslatorPublisher {
    self.rootTranslator
      .flatMap { $0.cloneWalkTo(blinkIdentifier.path).mapError { _ in NSError.fileProviderErrorForNonExistentItem(withIdentifier: blinkIdentifier.itemIdentifier) } }
      .eraseToAnyPublisher()
  }

  func _createEmptyFile(basedOn itemTemplate: NSFileProviderItem,
                        inParent parentIdentifier: BlinkFileItemIdentifier,
                        fields: NSFileProviderItemFields,
                        options: NSFileProviderCreateItemOptions,
                        log: BlinkLogger,
                        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
    let parentPath = parentIdentifier.path
    let fileName = itemTemplate.filename
    let itemPath = (parentIdentifier.path as NSString).appendingPathComponent(fileName)
    log.info("Creating file \(itemPath)")

    //let newItemIdentifier = NSFileProviderItemIdentifier(fileName, in: itemTemplate.parentItemIdentifier)

    let progress = Progress(totalUnitCount: 10)

    var createFileCancellable: AnyCancellable? = self._itemTranslator(for: parentIdentifier)
      .flatMap { t in t.create(name: fileName, mode: S_IRWXU).flatMap { $0.close() }.map { _ in t } }
      .flatMap { $0.cloneWalkTo(fileName) }
      .flatMap { fileTranslator in
        log.debug("Writing attributes")
        var newAttributes: BlinkFiles.FileAttributes = [:]
        if fields.contains(.creationDate) {
          newAttributes[.creationDate] = itemTemplate.creationDate!
        }
        if fields.contains(.contentModificationDate) {
          newAttributes[.modificationDate] = itemTemplate.contentModificationDate!
        }

        return self.workingSet.commitItemInSet(itemPath: itemPath) {
          fileTranslator.wstat(newAttributes).map { _ in fileTranslator }
            .flatMap {
              log.debug("Fetching \(fileName) attributes")
              return $0.stat()
            }
            .map {
              let newIdentifier = BlinkFileItemIdentifier.generate(name: fileName, parent: parentIdentifier)
              let createdItem = FileProviderItem(blinkIdentifier: newIdentifier, attributes: $0)
              return createdItem
            }
            .eraseToAnyPublisher()
        }
      }
      .sink(
        receiveCompletion: { completion in
          switch completion {
          case .finished:
            log.info("Create File completed")
            progress.completedUnitCount = progress.totalUnitCount
          case .failure(let error):
            log.error("Create file error: \(error)")
            if let error = error as? NSFileProviderError {
              completionHandler(nil, [], false, error)
            } else {
              completionHandler(nil, [], false, NSFileProviderError.operationError(dueTo: error))
            }
          }
        },
        receiveValue: { createdItem in
            completionHandler(createdItem,
                              [],
                              false,
                              nil)
        }
      )

    progress.cancellationHandler = {
      log.warn("Create item cancelled by user")
      createFileCancellable?.cancel()
      createFileCancellable = nil
      completionHandler(nil, [], false, NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    return progress
  }

  func cleanUpOldTmpFiles() -> AnyCancellable {
    // Enumerate on root, filter and remove.
    let log = self.logger("cleanUpOldTmpFiles")

    return self.rootTranslator
      .flatMap { translator in
        translator.directoryFilesAndAttributes()
          .flatMap { $0.publisher }
          .filter { fileAttributes in
            let fileName = fileAttributes[.name] as! String
            guard let modificationDate = fileAttributes[.modificationDate] as? Date else { return false }

            return fileName.starts(with: ".blink.tmp.") &&
              modificationDate < Date().addingTimeInterval(-3600)
          }
        // Flow control. Do not overwhelm the connection.
          .flatMap(maxPublishers: .max(3)) { fileAttributes in
            let fileName = fileAttributes[.name] as! String
            return translator.cloneWalkTo(fileName)
              .flatMap { $0.remove() }
            // Ignore errors.
              .catch { _ in Just(false) }
              .map { _ in fileName }
          }
      }
      .sink(
        receiveCompletion: { completion in
          switch completion {
          case .finished:
            log.info("Completed")
          case .failure(let error):
            log.error("Clean up Tmp files error: \(error)")
          }
        },
        receiveValue: { fileName in
          log.info("Cleaned up \(fileName)")
        }
      )
  }
}

extension NSFileProviderItemFields: CustomDebugStringConvertible {
  public var debugDescription: String {
    var descriptions: [String] = []

    if self.contains(.contents) { descriptions.append(".contents") }
    if self.contains(.filename) { descriptions.append(".filename") }
    if self.contains(.parentItemIdentifier) { descriptions.append(".parentItemIdentifier") }
    if self.contains(.typeAndCreator) { descriptions.append(".typeAndCreator") }
    if self.contains(.creationDate) { descriptions.append(".creationDate") }
    if self.contains(.contentModificationDate) { descriptions.append(".contentModificationDate") }
    if self.contains(.lastUsedDate) { descriptions.append(".lastUsedDate") }
    if self.contains(.tagData) { descriptions.append(".tagData") }
    if self.contains(.favoriteRank) { descriptions.append(".favoriteRank") }

    return "NSFileProviderItemFields: [" + descriptions.joined(separator: ", ") + "]"
  }
}

extension NSFileProviderCreateItemOptions: CustomDebugStringConvertible {
  public var debugDescription: String {
    var options = [String]()

    if contains(.mayAlreadyExist) { options.append("mayAlreadyExist") }
    if contains(.deletionConflicted) { options.append("deletionConflicted") }

    return "NSFileProviderCreateItemOptions: [" + options.joined(separator: ", ") + "]"
  }
}

extension NSFileProviderModifyItemOptions: CustomDebugStringConvertible {
  public var debugDescription: String {
    var options = [String]()

    if contains(.mayAlreadyExist) { options.append("mayAlreadyExist") }

    return "NSFileProviderModifyItemOptions: [" + options.joined(separator: ", ") + "]"
  }
}
