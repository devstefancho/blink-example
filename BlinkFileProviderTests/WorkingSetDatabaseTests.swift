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
@testable import BlinkFileProvider

final class WorkingSetTests: XCTestCase {
   override func setUpWithError() throws {
    BlinkLogging.handle(BlinkLoggingHandlers.print)
  }

  // Unit tests for the DB itself. Not sure if we will keep them.
  // The DB needs a specific behavior in specific cases, and it is easier to go through unit tests.
  // updateItem
  // updateItemsInContainer
  // updateChangedItems

  func testWorkingSetDatabaseUpdateChanges() throws {
    let location = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let db = try WorkingSetDatabase(path: location.appendingPathComponent("workingset.tests.db").path(), reset: true)

    print("Test 1 - load data")
    let _ = try db.updateItemsInContainer(.rootContainer, items: [TestRows.file1,
                                                                  TestRows.file2,
                                                                  TestRows.container1,
                                                                  TestRows.container1_file1,
                                                                  TestRows.container1_container2,
                                                                  TestRows.container1_container2_file1])
    var items = try db.items(in: .rootContainer)
    XCTAssertTrue(items.count == 3)
    items = try db.items(in: TestRows.container1.item)
    XCTAssertTrue(items.count == 2)
    items = try db.items(in: TestRows.container1_container2.item)
    XCTAssertTrue(items.count == 1)

    print("Test 2 - no changes on root")
    var deletedRows = try db.updateItemsInContainer(.rootContainer, items: [TestRows.file1,
                                                                            TestRows.file2,
                                                                            TestRows.container1])
    XCTAssertTrue(deletedRows.count == 0)

    print("Test 3 - Update single item")
    try db.updateItem(TestRows.container1)
    items = try db.items(in: TestRows.container1.item)
    XCTAssertTrue(items.count == 2)

    print("Test 4 - Update Items in container, delete some content")
    deletedRows = try db.updateItemsInContainer(TestRows.container1.blinkIdentifier(), items: [TestRows.container1_file1])
    XCTAssertTrue(deletedRows.count == 2)
    XCTAssertThrowsError(try db.updateChangedItems(createRows: [TestRows.file1]))
    _ = try db.updateChangedItems(updateRows: [TestRows.file1])
    items = try db.items(in: .rootContainer)
    XCTAssertTrue(items.count == 3)
    items = try db.items(in: TestRows.container1.item)
    XCTAssertTrue(items.count == 1)
    items = try db.items(in: TestRows.container1_container2.item)
    XCTAssertTrue(items.count == 0)

    print("Test 5 - Update Changes, container deleted")
    deletedRows = try db.updateChangedItems(updateRows: [TestRows.file2], deleteRows: [TestRows.container1, TestRows.file1])
    XCTAssertTrue(deletedRows.count == 3)
    items = try db.items(in: .rootContainer)
    XCTAssertTrue(items.count == 1)
    items = try db.items(in: TestRows.container1.item)
    XCTAssertTrue(items.count == 0)
    items = try db.items(in: TestRows.container1_container2.item)
    XCTAssertTrue(items.count == 0)

  }

  func testWorkingSetDatabaseReplaceItems() throws {
    let location = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let db = try WorkingSetDatabase(path: location.appendingPathComponent("workingset.tests.db").path(), reset: true)
    XCTAssertTrue((try! db.newestAnchor()) == 0)

    print("Test 1 - load data")
    let _ = try db.updateItemsInContainer(.rootContainer, items: [TestRows.file1,
                                                                  TestRows.container1,
                                                                  TestRows.container1_container2,
                                                                  TestRows.container1_container2_file1,
                                                                  TestRows.container2])
    var items = try db.items(in: .rootContainer)
    XCTAssertTrue(items.count == 3)
    items = try db.items(in: TestRows.container1.item)
    XCTAssertTrue(items.count == 1)
    items = try db.items(in: TestRows.container1_container2.item)
    XCTAssertTrue(items.count == 1)

    print("Test 3 - Update on same item")
    let _ = try db.updateItem(TestRows.file1_alt)
    items = try db.items(in: .rootContainer)
    XCTAssertTrue(items.count == 3)
    XCTAssertTrue(items.contains(where: { $0.name == TestRows.file1_alt.name }))

    print("Test 3.1 - Replacing item")
    let _ = try db.updateItem(TestRows.file1)
    let _ = try db.updateItem(TestRows.file1_replacement)
    items = try db.items(in: .rootContainer)
    XCTAssertTrue(items.count == 3)
    XCTAssertTrue(items.contains(where: { $0.name == TestRows.file1.name &&
      $0.item == TestRows.file1_replacement.item }))

    print("Test 4 - Update folder")
    var replacedItems = try db.updateItem(TestRows.container1_alt)
    items = try db.items(in: TestRows.container1_alt.item)
    XCTAssertTrue(items.count == 1)
    XCTAssertTrue(replacedItems.count == 0)
    XCTAssertTrue(items[0].containerPath.contains(TestRows.container1_alt.name))
    items = try db.items(in: TestRows.container1_container2.item)
    XCTAssertTrue(items.count == 1)
    XCTAssertTrue(items[0].containerPath.contains(
                    (TestRows.container1_alt.name as NSString)
                      .appendingPathComponent(TestRows.container1_container2.name)
                  ))
    let _ = try db.updateItem(TestRows.container1)

    print("Test 4.1 - Replace folder and move down")
    replacedItems = try db.updateItem(TestRows.container1_container2_on_root)
    // Maybe tests would be easier if we tracked the IDs separately. As the intention is for the item to be the same.
    items = try db.items(in: TestRows.container1_container2.item)
    XCTAssertTrue(replacedItems.count == 1)
    XCTAssertTrue(items.count == 1)
    // Because it is replaced, the container name should be the same
    XCTAssertTrue(items[0].containerPath == replacedItems[0].name)

    // Move back up
    let _ = try db.updateItem(TestRows.container1_container2)
    items = try db.items(in: TestRows.container1_container2.item)
    XCTAssertTrue(items.count == 1)
    XCTAssertTrue(items[0].containerPath.contains(TestRows.container1_container2.containerPath))
  }

  func testConcurrentUpdates() throws {
    let location = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let db = try WorkingSetDatabase(path: location.appendingPathComponent("workingset.tests.db").path(), reset: true)
    let updateQueue = DispatchQueue(label: "ConcurrentQueue", attributes: .concurrent)
    let expectUpdates = XCTestExpectation(description: "Concurrent Updates")

    let items = [TestRows.file1,
                 TestRows.file2,
                 TestRows.container1,
                 TestRows.container1_file1,
                 TestRows.container1_container2,
                 TestRows.container1_container2_file1]

    for item in items {
      updateQueue.async {
        try! db.updateItem(item)
      }
    }

    // At the same time, check items in containers as we place them.
    // Release the expectation once we can read them.
    updateQueue.async {
      var containers = [TestRows.container1, TestRows.container1_container2]
      while !containers.isEmpty {
        for idx in containers.indices.reversed() {
          let items = try! db.items(in: containers[idx].item)
          if items.count > 0 {
            containers.remove(at: idx)
          }
        }
      }
      expectUpdates.fulfill()
    }

    wait(for: [expectUpdates], timeout: 4)
  }
}

enum TestRows {
  static let version1 = NSFileProviderItemVersion(contentVersion: "asdf".data(using: .utf8)!, metadataVersion: "asdf".data(using: .utf8)!)
  static let file1 = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                             name: "file1",
                             container: .rootContainer,
                             containerPath: "",
                             version: version1,
                             isContainer: false,
                             anchor: 1)
  static let file1_alt = ItemRow(item: file1.item,
                             name: "file1_alt",
                             container: .rootContainer,
                             containerPath: "",
                             version: version1,
                             isContainer: false,
                             anchor: 1)
  static let file1_replacement = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                                         name: "file1",
                                         container: .rootContainer,
                                         containerPath: "",
                                         version: version1,
                                         isContainer: false,
                                         anchor: 1)

  static let file2 = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                             name: "file2",
                             container: .rootContainer,
                             containerPath: "",
                             version: version1,
                             isContainer: false,
                             anchor: 1)
  static let container1 = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                                  name: "container1",
                                  container: .rootContainer,
                                  containerPath: "",
                                  version: version1,
                                  isContainer: true,
                                  anchor: 1)
  static let container1_alt = ItemRow(item: container1.item,
                                      name: "container1_alt",
                                      container: .rootContainer,
                                      containerPath: "",
                                      version: version1,
                                      isContainer: true,
                                      anchor: 1)
  static let container2 = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                                  name: "container2",
                                  container: .rootContainer,
                                  containerPath: "",
                                  version: version1,
                                  isContainer: true,
                                  anchor: 1)
  static let container2_file1 = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                                        name: "file1",
                                        container: container2.item,
                                        containerPath: "container2",
                                        version: version1,
                                        isContainer: false,
                                        anchor: 1)
  static let container1_file1 = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                                        name: "file1",
                                        container: container1.item,
                                        containerPath: "container1",
                                        version: version1,
                                        isContainer: false,
                                        anchor: 1)
  static let container1_container2 = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                                             name: "container2",
                                             container: container1.item,
                                             containerPath: "container1",
                                             version: version1,
                                             isContainer: true,
                                             anchor: 1)
  static let container1_container2_on_root = ItemRow(item: container1_container2.item,
                                                     name: container1_container2.name,
                                                     container: .rootContainer,
                                                     containerPath: "",
                                                     version: version1,
                                                     isContainer: true,
                                                     anchor: 1)
  static let container1_container2_file1 = ItemRow(item: NSFileProviderItemIdentifier.shortUUID(),
                                                   name: "file1",
                                                   container: container1_container2.item,
                                                   containerPath: "container1/container2",
                                                   version: version1,
                                                   isContainer: false,
                                                   anchor: 1)

}
