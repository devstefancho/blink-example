//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2025 Blink Mobile Shell Project
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


import SwiftUI

struct TypingText: View {
  let fullText: String
  let cursor: String
  var onFinished: (() -> Void)? = nil
  var style: (Text) -> Text

  @State private var displayedText = ""
  @State private var isTypingFinished = false
  @State private var showCursor = true


  init(fullText: String, cursor: String, onFinished: (() -> Void)? = nil, style: @escaping (Text) -> Text = { $0 }) {
    self.fullText = fullText
    self.cursor = cursor
    self.onFinished = onFinished
    self.style = style
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
        style(Text(fullText + cursor)) // layout reservation
          .hidden()

        style(Text(attributedStringWithCursor)) // visible typing
      }
      .onAppear {
        typeNextCharacter(index: 0)
        startCursorBlink()
      }
  }

  private var attributedStringWithCursor: AttributedString {
    var result = AttributedString(displayedText + cursor)

    if isTypingFinished && !showCursor {
      if let cursorRange = result.range(of: cursor, options: .backwards) {
        result[cursorRange].foregroundColor = .clear
      }
    }

    return result
  }

  private func typeNextCharacter(index: Int) {
    guard index < fullText.count else {
      isTypingFinished = true
      onFinished?()
      return
    }

    let delay = Double.random(in: 0.03...0.12)

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
      displayedText.append(fullText[fullText.index(fullText.startIndex, offsetBy: index)])
      typeNextCharacter(index: index + 1)
    }
  }

  private func startCursorBlink() {
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
      if isTypingFinished {
        showCursor.toggle()
      }
    }
  }
}

#Preview {
  TypingText(fullText: "Hello, this is a typing effect.",
             cursor: "|", onFinished: {}) { text in
    text.font(.system(size: 20, weight: .medium, design: .monospaced))
      .foregroundColor(.green)
  }
}
