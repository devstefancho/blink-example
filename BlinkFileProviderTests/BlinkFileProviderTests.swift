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


import XCTest
import BlinkFiles
import Combine
import SSH
import UniformTypeIdentifiers

@testable import BlinkFileProvider

final class BlinkFileProviderTests: XCTestCase {
  func testEnumerator() throws {
    self.continueAfterFailure = false
    let connection = connection(path: Self.testPath)
    let workingSet = try workingSet()
    let enumerator = FileProviderReplicatedEnumerator(for: .rootContainer,
                                                      workingSet: workingSet,
                                                      connection: connection,
                                                      logger: testsLogger("enumeratorFor rootContainer"))

    let expectEnumerateRoot = self.expectation(description: "Root enumerated")

    enumerator.enumerateItems(
      for: TestEnumeratorObserver(
        didEnumerate: { items in
          XCTAssertTrue(items.count > 0)
        },
        finishEnumerating: { _ in
          expectEnumerateRoot.fulfill()
        },
        finishEnumeratingWithError: { error in
          XCTFail("Enumeration failed")
        }),
      startingAt: NSFileProviderPage(Data())
    )

    wait(for: [expectEnumerateRoot])

    // Test container and symlink enumeration.
  }

  func testWorkingSetChanges() throws {
    self.continueAfterFailure = false

    // We need to use the fp as there is no way to obtain a different enumerator (we need to hit the DB, and that's what the enumeratorFor does.
    let location = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let db = try WorkingSetDatabase(path: location.appendingPathComponent("workingset.tests.db").path(), reset: true)
    let ws = try WorkingSet(domain: nil, db: db, logger: testsLogger("WorkingSet"))
    var connection = connection(path: Self.testPath)
    var fp = FileProviderReplicatedExtension(connection: connection, workingSet: ws, temporaryDirectoryURL: location)

    let enumerator = try fp.enumerator(for: .rootContainer, request: NSFileProviderRequest())
//    let enumerator = try FileProviderReplicatedEnumerator(for: BlinkFileItemIdentifier.rootContainer, workingSet: ws, connection: connection)
    // There is no identifier for the container until it is enumerated.

    // 1. Before enumeration, the enumerators are not Active for changes.
    // In code, this wasn't true because the rootEnumerator was always Active. But we can try otherwise, as now previous content cannot be reused.
    let expectNoActiveEnumerators = self.expectation(description: "No active enumerators")

    ws.prepareChanges(onCompletion: { changes in
      XCTAssertTrue(changes.isEmpty)
      expectNoActiveEnumerators.fulfill()
    })

    wait(for: [expectNoActiveEnumerators])

    // 2. Trigger enumeration.
    let expectEnumerateRoot = self.expectation(description: "Root enumerated")
    var docsContainerIdentifier: NSFileProviderItemIdentifier!
    enumerator.enumerateItems(
      for: TestEnumeratorObserver(
        didEnumerate: { items in
          docsContainerIdentifier = items.first(where: { $0.filename == "docs" })!.itemIdentifier
          XCTAssertFalse(items.contains { $0.filename == "." } )
          XCTAssertTrue(items.count > 0)
        },
        finishEnumerating: { _ in
          expectEnumerateRoot.fulfill()
        },
        finishEnumeratingWithError: { error in
          XCTFail("Enumeration failed with \(error)")
        }),
      startingAt: NSFileProviderPage(Data())
    )

    wait(for: [expectEnumerateRoot])

    let expectEnumerateContainer = self.expectation(description: "Container enumerated")
    let containerEnumerator = try fp.enumerator(for: docsContainerIdentifier, request: NSFileProviderRequest())

    containerEnumerator.enumerateItems(
      for: TestEnumeratorObserver(finishEnumerating: { _ in expectEnumerateContainer.fulfill() }),
      startingAt: NSFileProviderPage(Data())
    )
    wait(for: [expectEnumerateContainer])

    var items = try db.items(in: docsContainerIdentifier)

    // 3. No changes after recent enumeration.
    let expectNoChanges = self.expectation(description: "No changes in root")

    ws.prepareChanges(onCompletion: { changes in
      XCTAssertTrue(changes.isEmpty)
      expectNoChanges.fulfill()
    })

    wait(for: [expectNoChanges])

    enumerator.invalidate()
    containerEnumerator.invalidate()

    // 4. Prepare changes.
    // Instead of making changes to a location, we are changing the rootContainer to a different cloned location with the changes.
    connection = self.connection(path: Self.testPathChanges)
    fp = FileProviderReplicatedExtension(connection: connection, workingSet: ws, temporaryDirectoryURL: location)
    let enumeratorChanges = try fp.enumerator(for: .rootContainer, request: NSFileProviderRequest())

    let expectChanges = self.expectation(description: "Detect Changes")

    ws.prepareChanges(onCompletion: { changes in
      XCTAssertTrue(changes.creates.count == 2)
      // "." is a change too on a different folder
      XCTAssertTrue(changes.updates.count == 2 + 1)
      XCTAssertTrue(changes.deletions.count == 3)
      expectChanges.fulfill()
    })

    wait(for: [expectChanges])

    // 5. The WorkingSet updates its state when there are changes. When requested an enumeration, test different cases.
    let expectStateChange = self.expectation(description: "WorkingSet State change with enumerator")
    let anchor = ws.anchor

    ws.prepareChangesAndSignalEnumerator()

    let wsEnumerator = try fp.enumerator(for: .workingSet, request: NSFileProviderRequest())

    var updates = 0
    var deletions = 0
    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) {
      wsEnumerator.enumerateChanges!(
        for: TestEnumeratorChangeObserver(
          didUpdate: { items in
            XCTAssertFalse(items.contains { $0.filename == "." })
            updates += items.count
          },
          didDeleteItems: { items in
            deletions += items.count
          },
          finishEnumeratingChanges: { (newAnchor, moreComing) in
            XCTAssertTrue(anchor.iteration + 1 == newAnchor.iteration)
            XCTAssertTrue(updates == 4)
            // After the commit, the elements from docs directory should be released.
            XCTAssertTrue(deletions > 3)

            expectStateChange.fulfill()
          },
          finishEnumeratingWithError: { error in
            XCTFail("enumerateChanges failed with \(error)")
          }),
        from: anchor)
    }

    wait(for: [expectStateChange])
  }

  func testFetchContents() throws {
    let fp = try fileProviderExtension()
    let request = NSFileProviderRequest()
    let version: NSFileProviderItemVersion? = nil

    let expectIdentifier = self.expectation(description: "No identifier")
    let enumerator = try fp.enumerator(for: .rootContainer, request: request)
    var itemIdentifier: NSFileProviderItemIdentifier!
    enumerator.enumerateItems(
      for: TestEnumeratorObserver(
        didEnumerate: { items in
          itemIdentifier = items.first(where: { $0.filename == "image.jpg" })!.itemIdentifier
          expectIdentifier.fulfill()
        }
      ),
      startingAt: NSFileProviderPage(Data())
    )
    wait(for: [expectIdentifier])

    let expectDownload = self.expectation(description: "Download")
    var progress = fp.fetchContents(for: itemIdentifier,
                                    version: version,
                                    request: request) { (url, fileItem, error) in
      if let error = error {
        XCTFail("Download failed \(error)")
        return
      }

      let url = url!
      let fileItem = fileItem!
      expectDownload.fulfill()
    }
    wait(for: [expectDownload])

    XCTAssertTrue(progress.isFinished)

    let noItemIdentifier = NSFileProviderItemIdentifier("xxx.jpg")
    let expectNoSuchFile = self.expectation(description: "No such file")
    progress = fp.fetchContents(for: noItemIdentifier,
                                version: version,
                                request: request) { (url, fileItem, error) in
      XCTAssertTrue(error != nil && (error! as! NSFileProviderError).code == NSFileProviderError.noSuchItem)
      XCTAssertTrue(url == nil)
      expectNoSuchFile.fulfill()
    }
    wait(for: [expectNoSuchFile])
    XCTAssertFalse(progress.isFinished)
  }

  func testCreateEmptyFileItem() throws {
    self.continueAfterFailure = false
    let fp = try fileProviderExtension()

    let testItemTemplate = TestFileProviderItem(itemIdentifier: NSFileProviderItemIdentifier("empty"), parentItemIdentifier: .rootContainer, filename: "empty", contentType: .data)

    // Regular file
    let expectFileCreated = self.expectation(description: "Item created")
    var file: NSFileProviderItem!
    var _progress = fp.createItem(basedOn: testItemTemplate,
                                  fields: [.filename, .parentItemIdentifier, .creationDate, .contentModificationDate,     .fileSystemFlags, .typeAndCreator],
                                  contents: nil,
                                  request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(createdItem!.filename == "empty")
      file = createdItem!
      expectFileCreated.fulfill()
    }
    wait(for: [expectFileCreated])

    let expectDeleteFile = self.expectation(description: "Item deleted")
    _progress = fp.deleteItem(identifier: file.itemIdentifier,
                              baseVersion: file.itemVersion!,
                              options: NSFileProviderDeleteItemOptions([]),
                              request: NSFileProviderRequest()) { error in
      XCTAssertNil(error)
      expectDeleteFile.fulfill()
    }
    wait(for: [expectDeleteFile])
  }

  func testCreateStructure() throws {
    self.continueAfterFailure = false
    let fp = try fileProviderExtension()

    // Regular folder
    let testDirectoryTemplate = TestFileProviderItem(itemIdentifier: NSFileProviderItemIdentifier("tmp"), parentItemIdentifier: .rootContainer, filename: "tmp", contentType: .folder)
    let expectFolderCreated = self.expectation(description: "Folder created")
    var dir: NSFileProviderItem!
    var _progress  = fp.createItem(basedOn: testDirectoryTemplate, fields: [], contents: nil, request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(createdItem!.filename == "tmp")
      dir = createdItem!
      expectFolderCreated.fulfill()
    }
    wait(for: [expectFolderCreated])

    let fileURL = Bundle.main.url(forResource: "term", withExtension: "html")!
    let testItemTemplate = TestFileProviderItem(itemIdentifier: NSFileProviderItemIdentifier("test.html"), parentItemIdentifier: dir.itemIdentifier, filename: "test.html", contentType: .data)

    // Regular file
    let expectFileCreated = self.expectation(description: "Item created")
    _progress = fp.createItem(basedOn: testItemTemplate,
                                  // TODO Flags
                                 fields: [.contents, .filename],
                                 contents: fileURL, options: [.mayAlreadyExist],
                                 request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(createdItem!.filename == "test.html")
      expectFileCreated.fulfill()
    }
    wait(for: [expectFileCreated])
  }

  func testFileItemCreate() throws {
    self.continueAfterFailure = false
    var fp = try fileProviderExtension()

    let fileURL = Bundle.main.url(forResource: "term", withExtension: "html")!
    let testItemTemplate = TestFileProviderItem(itemIdentifier: NSFileProviderItemIdentifier("test.html"), parentItemIdentifier: .rootContainer, filename: "test.html", contentType: .data)

    // Regular file
    let expectFileCreated = self.expectation(description: "Item created")
    var fileItem: NSFileProviderItem!
    var _progress = fp.createItem(basedOn: testItemTemplate,
                                  // TODO Flags
                                 fields: [.contents, .filename],
                                 contents: fileURL, options: [.mayAlreadyExist],
                                 request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(createdItem!.filename == "test.html")
      fileItem = createdItem!
      expectFileCreated.fulfill()
    }
    wait(for: [expectFileCreated])

    // TODO Create in non-existing container.

    // Same create should return same FileItem within the Collision.
    let expectCollisionWithSameFileItem = self.expectation(description: "Collision with same File item")
    _progress = fp.createItem(basedOn: testItemTemplate,
                                  // TODO Flags
                                  fields: [.contents, .filename],
                                  contents: fileURL, options: [],
                                  request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNotNil(error)
      let error = error as! NSFileProviderError
      let itemInError = error.userInfo[NSFileProviderErrorItemKey] as! NSFileProviderItem
      XCTAssertTrue(itemInError.itemIdentifier == fileItem.itemIdentifier)
      expectCollisionWithSameFileItem.fulfill()
    }
    wait(for: [expectCollisionWithSameFileItem])

    // Resetting the fp, we should get a different FileItem within the Collision.
    fp = try fileProviderExtension()
    let expectCollisionDifferentFileItem = self.expectation(description: "Collision with different File item")
    _progress = fp.createItem(basedOn: testItemTemplate,
                              // TODO Flags
                              fields: [.contents, .filename],
                              contents: fileURL, options: [],
                              request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNotNil(error)
      let error = error as! NSFileProviderError
      let itemInError = error.userInfo[NSFileProviderErrorItemKey] as! NSFileProviderItem
      XCTAssertFalse(itemInError.itemIdentifier == fileItem.itemIdentifier)
      fileItem = itemInError
      expectCollisionDifferentFileItem.fulfill()
    }
    wait(for: [expectCollisionDifferentFileItem])

    let expectDeleteFile = self.expectation(description: "Item deleted")
    _progress = fp.deleteItem(identifier: fileItem.itemIdentifier,
                              baseVersion: fileItem.itemVersion!,
                              options: NSFileProviderDeleteItemOptions([]),
                              request: NSFileProviderRequest()) { error in
      XCTAssertNil(error)
      expectDeleteFile.fulfill()
    }
    wait(for: [expectDeleteFile])
  }

  func testDirectoryCreate() throws {
    self.continueAfterFailure = false
    var fp = try fileProviderExtension()

    // Regular folder
    let untitledDirectoryTemplate = TestFileProviderItem(itemIdentifier: NSFileProviderItemIdentifier("dir"), parentItemIdentifier: .rootContainer, filename: "untitled folder", contentType: .folder)
    let expectFolderCreated = self.expectation(description: "Folder created")
    var dir: NSFileProviderItem!
    var _progress  = fp.createItem(basedOn: untitledDirectoryTemplate, fields: [.filename], contents: nil, request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(createdItem?.filename == "untitled folder")
      dir = createdItem
      expectFolderCreated.fulfill()
    }
    wait(for: [expectFolderCreated])

    let expectFolderRename = self.expectation(description: "Folder rename")
    let testDirectoryTemplate = TestFileProviderItem(itemIdentifier: dir.itemIdentifier, parentItemIdentifier: dir.parentItemIdentifier, filename: "Test Directory", contentType: .folder)
    _progress = fp.modifyItem(testDirectoryTemplate, baseVersion: dir.itemVersion!, changedFields: [.filename], contents: nil, request: NSFileProviderRequest()) { (modifiedItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(modifiedItem?.filename == "Test Directory")
      dir = modifiedItem
      expectFolderRename.fulfill()
    }
    wait(for: [expectFolderRename])

    let expectRecreate = self.expectation(description: "Recreate")
    _progress = fp.createItem(basedOn: testDirectoryTemplate, fields: [.filename], contents: nil, request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(createdItem?.itemIdentifier == dir.itemIdentifier)
      expectRecreate.fulfill()
    }
    wait(for: [expectRecreate])
  }

  func testFileItemOperations() throws {
    self.continueAfterFailure = false
    let fp = try fileProviderExtension()

    try fileItemOperations(rootContainer: .rootContainer, fp: fp)
  }

  func fileItemOperations(rootContainer: NSFileProviderItemIdentifier, fp: FileProviderReplicatedExtension) throws {
    let fileURL = Bundle.main.url(forResource: "term", withExtension: "html")!
    let testItemTemplate = TestFileProviderItem(itemIdentifier: NSFileProviderItemIdentifier("test.html"), parentItemIdentifier: rootContainer, filename: "test.html", contentType: .data)

    // Regular file
    let expectFileCreated = self.expectation(description: "Item created")
    var file: NSFileProviderItem!
    var _progress = fp.createItem(basedOn: testItemTemplate,
                                 // TODO Flags
                                 fields: [.contents, .filename],
                                 contents: fileURL, options: [.mayAlreadyExist],
                                 request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(createdItem!.filename == "test.html")
      file = createdItem!
      expectFileCreated.fulfill()
    }

    // Regular folder
    let testDirectoryTemplate = TestFileProviderItem(itemIdentifier: NSFileProviderItemIdentifier("dir"), parentItemIdentifier: rootContainer, filename: "dir", contentType: .folder)
    let expectFolderCreated = self.expectation(description: "Folder created")
    var dir: NSFileProviderItem!
    _progress  = fp.createItem(basedOn: testDirectoryTemplate, fields: [], contents: nil, request: NSFileProviderRequest()) { (createdItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      dir = createdItem
      expectFolderCreated.fulfill()
    }
    wait(for: [expectFileCreated, expectFolderCreated])

    // Modify content and filename

    // This should check the previous has been deleted too.
    let testModifiedItemTemplate = TestFileProviderItem(itemIdentifier: file.itemIdentifier,
                                                        parentItemIdentifier: dir.itemIdentifier,
                                                        filename: "modified.html", contentType: .data)

    let expectUpdatedContentAndFilename = self.expectation(description: "Update content")
    _progress = fp.modifyItem(testModifiedItemTemplate,
                              baseVersion: file.itemVersion!,
                              changedFields: [.contents, .filename, .parentItemIdentifier],
                              contents: fileURL,
                              request: NSFileProviderRequest()) { (modifiedItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      // Our upload is shared with create, and regular parameters can change at once.
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(modifiedItem!.itemIdentifier == file.itemIdentifier)
      XCTAssertTrue(modifiedItem!.parentItemIdentifier == dir.itemIdentifier)
      file = modifiedItem
      expectUpdatedContentAndFilename.fulfill()
    }
    wait(for: [expectUpdatedContentAndFilename])

//    // Modify parent down.
//    let expectReparentingUp = self.expectation(description: "Reparenting")
//    _progress = fp.modifyItem(testModifiedItemTemplate,
//                              baseVersion: file.itemVersion!,
//                              changedFields: [.parentItemIdentifier],
//                              contents: nil,
//                              request: NSFileProviderRequest()) { (modifiedItem, pendingFields, shouldFetch, error) in
//      XCTAssertNil(error)
//      XCTAssertTrue(pendingFields.isEmpty)
//      XCTAssertTrue(modifiedItem!.filename == "modified.html")
//      XCTAssertTrue(modifiedItem!.itemIdentifier.rawValue == "dir/modified.html")
//      XCTAssertTrue(modifiedItem!.parentItemIdentifier.rawValue == "dir")
//      file = modifiedItem
//      expectReparentingUp.fulfill()
//    }
//    wait(for: [expectReparentingUp])

    let expectReparentingDown = self.expectation(description: "Reparenting")

    let testReparentItemTemplate = TestFileProviderItem(itemIdentifier: file.itemIdentifier,
                                                        parentItemIdentifier: rootContainer,
                                                        filename: "test.html", contentType: .data)
    _progress = fp.modifyItem(testReparentItemTemplate,
                              baseVersion: file.itemVersion!,
                              changedFields: [.parentItemIdentifier, .filename],
                              contents: nil,
                              request: NSFileProviderRequest()) { (modifiedItem, pendingFields, shouldFetch, error) in
      XCTAssertNil(error)
      XCTAssertTrue(pendingFields.isEmpty)
      XCTAssertTrue(modifiedItem!.filename == "test.html")
      XCTAssertTrue(modifiedItem!.itemIdentifier == file.itemIdentifier)
      XCTAssertTrue(modifiedItem!.parentItemIdentifier == rootContainer)
      file = modifiedItem
      expectReparentingDown.fulfill()
    }
    wait(for: [expectReparentingDown])


    let expectDeleteFile = self.expectation(description: "Item deleted")
    _progress = fp.deleteItem(identifier: file.itemIdentifier,
                              baseVersion: file.itemVersion!,
                              options: NSFileProviderDeleteItemOptions([]),
                              request: NSFileProviderRequest()) { error in
      XCTAssertNil(error)
      expectDeleteFile.fulfill()
    }
    wait(for: [expectDeleteFile])
  }

  func testSymlinkOperations() throws {
    // Browse the structure.
    self.continueAfterFailure = false
    let fp = try fileProviderExtension(rootPath: "sftp:localhost:~/fps/fps_symlinks")
    let request = NSFileProviderRequest()

    let expectEnumerateRoot = self.expectation(description: "Root enumerated")
    let enumerator = try fp.enumerator(for: .rootContainer, request: request)
    var symlinkRootItem: NSFileProviderItem!
    var directoryItem: NSFileProviderItem!
    enumerator.enumerateItems(
      for: TestEnumeratorObserver(
        didEnumerate: { items in
          XCTAssertTrue(items.count > 0)
          symlinkRootItem = items.first(where: { $0.filename == "test_link" })
          XCTAssertTrue(symlinkRootItem.contentType == .directory)
          directoryItem = items.first(where: { $0.filename == "dir" })
          expectEnumerateRoot.fulfill()
        }
      ),
      startingAt: NSFileProviderPage(Data())
    )
    wait(for: [expectEnumerateRoot])

    let expectEnumerateSymlink = self.expectation(description: "Symlink Root")
    let symlinkEnumerator = try fp.enumerator(for: symlinkRootItem.itemIdentifier, request: request)
    symlinkEnumerator.enumerateItems(
      for: TestEnumeratorObserver(
           didEnumerate: { items in
             XCTAssertTrue(items.count > 0)
             expectEnumerateSymlink.fulfill()
           }
         ),
      startingAt: NSFileProviderPage(Data())
    )
    wait(for: [expectEnumerateSymlink])

    // Allow delete. Content should be untouched. Note we do not allow to create the item, so this part of the test is not automated.
    // let expectSymlinkDeleted = self.expectation(description: "Symlink deleted")
    // fp.deleteItem(identifier: symlinkRootItem.itemIdentifier,
    //               baseVersion: symlinkRootItem.itemVersion!,
    //               options: [],
    //               request: request) { error in
    //   XCTAssertNil(error)
    //   expectSymlinkDeleted.fulfill()
    // }
    // wait(for: [expectSymlinkDeleted])

    // Operations inside the symlink (rename, uploads, etc...) - this is more on the SFTP side though, but
    // good to know the limitations now.
    // try fileItemOperations(rootContainer: symlinkRootItem.itemIdentifier, fp: fp)

    // Operations to the symlink:
    // - Cannot rename or move the symlink (it will break) - you can move the symlink, you cannot change where it points to.
    //   - What happens if the link breaks after the move? It should come from the changes, but not sure it is going to like it.

//    let testRenameSymlinkTemplate = TestFileProviderItem(itemIdentifier: symlinkRootItem.itemIdentifier,
//                                                         parentItemIdentifier: .rootContainer,
//                                                         filename: "other_link",
//                                                         contentType: .folder)
//    let expectRenameSymlink = self.expectation(description: "Rename symlink")
//    var _progress = fp.modifyItem(testRenameSymlinkTemplate,
//                              baseVersion: symlinkRootItem.itemVersion!,
//                              changedFields: [.filename],
//                              contents: nil,
//                              request: request) { (modifiedItem, pendingFields, shouldFetch, error) in
//      XCTAssertNil(error)
//      XCTAssertTrue(modifiedItem!.itemIdentifier == symlinkRootItem.itemIdentifier)
//      XCTAssertTrue(modifiedItem!.filename == "other_link")
//      symlinkRootItem = modifiedItem
//      expectRenameSymlink.fulfill()
//    }
//    wait(for: [expectRenameSymlink])
//
//    // Reparent the symlink.
//    let testReparentSymlinkTemplate = TestFileProviderItem(itemIdentifier: symlinkRootItem.itemIdentifier,
//                                                           parentItemIdentifier: directoryItem.itemIdentifier,
//                                                           filename: "test_link",
//                                                           contentType: .folder)
//    let expectReparentSymlink = self.expectation(description: "Reparent symlink")
//    _progress = fp.modifyItem(testReparentSymlinkTemplate,
//                              baseVersion: symlinkRootItem.itemVersion!,
//                              changedFields: [.filename, .parentItemIdentifier],
//                              contents: nil,
//                              request: request) { (modifiedItem, pendingFields, shouldFetch, error) in
//      XCTAssertNil(error)
//      // Could we return a different item in this?
//    }

    // Changes should be seen in the other enumerator too - the test here
    // would be to have get the same reference to the Destination.
  }

  func testDeleteItem() throws {
    self.continueAfterFailure = false
    let fp = try fileProviderExtension()

    let item = NSFileProviderItemIdentifier("docs")
    let version = NSFileProviderItemVersion()
    let options = NSFileProviderDeleteItemOptions([.recursive])
    let request = NSFileProviderRequest()

    let expectFolderDeleted = self.expectation(description: "Folder deleted")
    let _prorgress = fp.deleteItem(identifier: item,
                                   baseVersion: version,
                                   options: options,
                                   request: request) { error in
      XCTAssertNil(error)
      expectFolderDeleted.fulfill()
    }

    wait(for: [expectFolderDeleted])
  }

  func testCleanupTmpFiles() throws {
    self.continueAfterFailure = false
    var cancellables = Set<AnyCancellable>()
    let fp = try fileProviderExtension()

    let tmpFileNameOne = ".blink.tmp.one"
    let tmpFileNameTwo = ".blink.tmp.two"

    let expectTmpFileOneCreated = self.expectation(description: "File One created")
    fp.rootTranslator
      .flatMap { translator -> AnyPublisher<File, Error> in
        translator.create(name: tmpFileNameOne, mode: S_IRWXU) }
      .flatMap { file in
        file.write(Data(repeating: 0, count:8).withUnsafeBytes { DispatchData(bytes: $0) }, max: 8)
          .flatMap { _ in file.close() } }
      .assertNoFailure()
      .sink { _ in
        expectTmpFileOneCreated.fulfill()
      }
      .store(in: &cancellables)

    let expectTmpFileTwoCreated = self.expectation(description: "File Two created")
    fp.rootTranslator
      .flatMap { $0.create(name: tmpFileNameTwo, mode: S_IRWXU) }
      .flatMap { file in 
        file.write(Data(repeating: 0, count:16).withUnsafeBytes { DispatchData(bytes: $0) }, max: 16)
          .flatMap { _ in file.close() } }
      .assertNoFailure()
      .sink { _ in 
        expectTmpFileTwoCreated.fulfill()
      }
      .store(in: &cancellables)
    wait(for: [expectTmpFileOneCreated, expectTmpFileTwoCreated])
    cancellables = []
    let expectTmpFileTwoWriteModificationDate = self.expectation(description: "File Two modified date changed")

    fp.rootTranslator
      .flatMap { $0.cloneWalkTo(tmpFileNameTwo) }
      .flatMap { translator in
        var newAttributes: BlinkFiles.FileAttributes = [:]
        newAttributes[.modificationDate] = Date().addingTimeInterval(-6000)
        return translator.wstat(newAttributes)
      }
      .assertNoFailure()
      .sink { _ in expectTmpFileTwoWriteModificationDate.fulfill() }
      .store(in: &cancellables)

    wait(for: [expectTmpFileTwoWriteModificationDate])

    cancellables = []
    let cancelCleanup = fp.cleanUpOldTmpFiles()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 2))

    let expectFileTwoMissing = self.expectation(description: "File Two missing")

    fp.rootTranslator
      .flatMap { $0.cloneWalkTo(tmpFileNameTwo) }
      .sink(
        receiveCompletion: { completion in
          guard case .failure(_) = completion else { 
            XCTFail("File should not exist")
            return
          }
          expectFileTwoMissing.fulfill()
        },
        receiveValue: { _ in }
      )
      .store(in: &cancellables)

    let expectFileOneExists = self.expectation(description: "File One exists")

    fp.rootTranslator
      .flatMap { $0.cloneWalkTo(tmpFileNameOne) }
      .assertNoFailure()
      .flatMap { $0.remove() }
      .assertNoFailure()
      .sink { _ in expectFileOneExists.fulfill() }
      .store(in: &cancellables)

    wait(for: [expectFileOneExists, expectFileTwoMissing])
  }
}

extension BlinkFileProviderTests {
  static let testPath = "sftp:localhost:~/fps/fps"
  static let testPathChanges = "sftp:localhost:~/fps/fps_changes"

  func testsLogger(_ component: String) -> BlinkLogger {
    BlinkLogger(component, handlers: [BlinkLoggingHandlers.print])
  }

  func workingSet() throws -> WorkingSet {
    let location = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let db = try WorkingSetDatabase(path: location.appendingPathComponent("workingset.tests.db").path(), reset: true)
    return try WorkingSet(domain: nil, db: db, logger: BlinkLogger("WorkingSet", handlers: [BlinkLoggingHandlers.print]))
  }

  func connection(path: String) -> FilesTranslatorConnection {
    let providerPath = try! BlinkFileProviderPath(path)
    let connection = FilesTranslatorConnection(providerPath: providerPath, configurator: TestFactoryConfigurator())
    return connection
  }

  func fileProviderExtension(rootPath: String? = nil) throws -> FileProviderReplicatedExtension {
    let workingSet = try workingSet()
    let connection = connection(path: rootPath ?? Self.testPath)
    let location = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    return FileProviderReplicatedExtension(connection: connection, workingSet: workingSet, temporaryDirectoryURL: location)
  }
}

class TestEnumeratorObserver: NSObject, NSFileProviderEnumerationObserver {
  let _didEnumerate: (([any NSFileProviderItemProtocol]) -> Void)?
  let _finishEnumerating: ((NSFileProviderPage?) -> Void)?
  let _finishEnumeratingWithError: ((any Error) -> Void)?

  init(didEnumerate: ( ([any NSFileProviderItemProtocol]) -> Void)? = nil,
       finishEnumerating: ( (NSFileProviderPage?) -> Void)? = nil,
       finishEnumeratingWithError: ( (any Error) -> Void)? = nil) {
    self._didEnumerate = didEnumerate
    self._finishEnumerating = finishEnumerating
    self._finishEnumeratingWithError = finishEnumeratingWithError
  }

  func didEnumerate(_ updatedItems: [any NSFileProviderItemProtocol]) {
    _didEnumerate?(updatedItems)
  }

  func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
    _finishEnumerating?(nextPage)
  }

  func finishEnumeratingWithError(_ error: any Error) {
    _finishEnumeratingWithError?(error)
  }
}

class TestEnumeratorChangeObserver: NSObject, NSFileProviderChangeObserver {
  let _didUpdate: (([any NSFileProviderItemProtocol]) -> Void)?
  let _didDeleteItems: (([NSFileProviderItemIdentifier]) -> Void)?
  let _finishEnumeratingChanges: ((NSFileProviderSyncAnchor, Bool) -> Void)?
  let _finishEnumeratingWithError: ((Error) -> Void)?

  init(didUpdate: (([any NSFileProviderItemProtocol]) -> Void)? = nil,
       didDeleteItems: (([NSFileProviderItemIdentifier]) -> Void)? = nil,
       finishEnumeratingChanges: ((NSFileProviderSyncAnchor, Bool) -> Void)? = nil,
       finishEnumeratingWithError: ((Error) -> Void)? = nil
  ) {
    self._didUpdate = didUpdate
    self._didDeleteItems = didDeleteItems
    self._finishEnumeratingChanges = finishEnumeratingChanges
    self._finishEnumeratingWithError = finishEnumeratingWithError
  }

  func didUpdate(_ updatedItems: [any NSFileProviderItemProtocol]) {
    _didUpdate?(updatedItems)
  }

  func didDeleteItems(withIdentifiers deletedItemIdentifiers: [NSFileProviderItemIdentifier]) {
    _didDeleteItems?(deletedItemIdentifiers)
  }

  func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
    _finishEnumeratingChanges?(anchor, moreComing)
  }

  func finishEnumeratingWithError(_ error: any Error) {
    _finishEnumeratingWithError?(error)
  }
}

class TestFileProviderItem: NSObject, NSFileProviderItem {
  var itemIdentifier: NSFileProviderItemIdentifier
  var parentItemIdentifier: NSFileProviderItemIdentifier
  var filename: String
  var contentType: UTType

  init(itemIdentifier: NSFileProviderItemIdentifier, parentItemIdentifier: NSFileProviderItemIdentifier, filename: String, contentType: UTType) {
    self.itemIdentifier = itemIdentifier
    self.parentItemIdentifier = parentItemIdentifier
    self.filename = filename
    self.contentType = contentType
  }
}
