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
import SwiftUI


struct DefaultAgentSettingsView: View {
  @State private var agentSettings: BKAgentSettings? = nil
  @State private var showAlert = false
  @State private var alertMessage = ""
  @State private var dismissAfterAlert = false

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    List {
      if let binding = Binding<BKAgentSettings>($agentSettings) {
        AgentSettingsOptions(agentSettings: binding, enabled: true)
          .onChange(of: agentSettings!) { new in
            do {
              try SSHDefaultAgent.setSettings(new)
            } catch {
              self.alertMessage = "Failed to set settings: \(error.localizedDescription)"
              self.showAlert = true
              self.dismissAfterAlert = true
            }
          }
      }
    }
    .navigationBarTitle("Default Agent")
    .onAppear {
      print("OnAppear")
      if agentSettings == nil {
        print("Init settings")
        do {
          let agentSettings = try SSHDefaultAgent.getSettings() ?? BKAgentSettings()
          self.agentSettings = agentSettings
        } catch {
          self.alertMessage = "Failed to get settings: \(error.localizedDescription)"
          self.showAlert = true
          self.dismissAfterAlert = true
        }
      }
    }
    .alert(isPresented: $showAlert) {
      Alert(
        title: Text("Error"),
        message: Text(alertMessage),
        dismissButton: .default(Text("OK")) {
          if self.dismissAfterAlert {
            dismiss()
          }
        }
      )
    }
  }
}

struct AgentSettingsOptions: View {
  @Binding var agentSettings: BKAgentSettings
  @State var prompt: BKAgentSettingsPrompt
  @State var keys: [String]
  var enabled: Bool

  init(agentSettings: Binding<BKAgentSettings>, enabled: Bool) {
    self._agentSettings = agentSettings
    self.prompt = agentSettings.wrappedValue.prompt
    self.keys = agentSettings.wrappedValue.keys
    self.enabled = enabled
  }

  var body: some View {
    FieldAgentSettingsPrompt(value: $prompt, enabled: enabled)
      .onChange(of: prompt) { newPrompt in
        self.agentSettings = BKAgentSettings(prompt: newPrompt, keys: keys)
      }
    if prompt != .Deny {
      FieldAgentSettingsKeys(value: $keys, enabled: enabled)
        .onChange(of: keys) { newKeys in
          self.agentSettings = BKAgentSettings(prompt: prompt, keys: newKeys)
        }
    }
  }
}

fileprivate struct FieldAgentSettingsPrompt: View {
  @Binding var value: BKAgentSettingsPrompt
  var enabled: Bool

  var body: some View {
    Row(
      content: {
        HStack {
          FormLabel(text: "Agent Forwarding")
          Spacer()
          Text(value.label)
        }
      },
      details: {
        AgentSettingsPromptPickerView(currentValue: enabled ? $value : .constant(value))
      }
    ).disabled(!enabled)
  }
}

fileprivate struct FieldAgentSettingsKeys: View {
  @Binding var value: [String]
  var enabled: Bool

  var body: some View {
    Row(
      content: {
        HStack {
          FormLabel(text: "Load Keys")
          Spacer()
          Text(value.isEmpty ? "None" : value.joined(separator: ", "))
            .font(.system(.subheadline)).foregroundColor(.secondary)
        }
      },
      details: {
        KeyPickerView(currentKey: enabled ? $value : .constant(value), multipleSelection: true)
      }
    ).disabled(!enabled)
  }
}

struct AgentSettingsPromptPickerView: View {
  @Binding var currentValue: BKAgentSettingsPrompt

  var body: some View {
    List {
      Section(footer: Text(currentValue.hint)) {
        ForEach(BKAgentSettingsPrompt.all, id: \.self) { value in
          HStack {
            Text(value.label).tag(value)
            Spacer()
            Checkmark(checked: currentValue == value)
          }
          .contentShape(Rectangle())
          .onTapGesture { currentValue = value }
        }
      }
    }
    .listStyle(InsetGroupedListStyle())
    .navigationTitle("Agent Forwarding")
  }
}

extension BKAgentSettingsPrompt: Hashable {
  var label: String {
    switch self {
    case .Deny: return "No"
    case .Confirm: return "Confirm"
    case .Allow: return "Allow"
    case _: return ""
    }
  }

  var hint: String {
    switch self {
    case .Deny: return "Deny usage of the key for signatures."
    case .Confirm: return "Confirm each use of a key before signature."
    case .Allow: return "Allow to use the key for signature without confirmation."
    case _: return ""
    }
  }

  static var all: [BKAgentSettingsPrompt] {
    [
      Deny,
      Confirm,
      Allow,
    ]
  }
}
