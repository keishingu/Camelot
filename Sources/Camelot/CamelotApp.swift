import AppKit
import SwiftUI

@main
@MainActor
struct CamelotApp: App {
  @StateObject private var model = CamelotAppModel()

  var body: some Scene {
    WindowGroup("Camelot") {
      CamelotDiagnosticView(model: model)
        .frame(minWidth: 480, minHeight: 420)
        .task { model.start() }
    }

    MenuBarExtra("Camelot", systemImage: "keyboard.badge.ellipsis") {
      CamelotMenu(model: model)
    }
  }
}

private struct CamelotDiagnosticView: View {
  @ObservedObject var model: CamelotAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Camelot")
          .font(.largeTitle.weight(.semibold))
        Text("Option tap → Hint → Accessibility action")
          .foregroundStyle(.secondary)
      }

      PermissionRow(
        title: "Accessibility",
        granted: model.permissions.accessibility,
        action: model.requestAccessibility
      )
      PermissionRow(
        title: "Input Monitoring",
        granted: model.permissions.inputMonitoring,
        action: model.requestInputMonitoring
      )

      HStack {
        Button("Refresh Permissions", action: model.refreshPermissions)
        Button("Show Hints Now", action: model.scanFrontmostApplication)
          .disabled(
            model.isScanning
              || !model.permissions.accessibility
              || !model.permissions.inputMonitoring
          )
      }

      Text(model.status)
        .font(.callout.monospacedDigit())
        .textSelection(.enabled)

      if !model.roleCounts.isEmpty {
        GroupBox("Last scan — role counts") {
          Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            ForEach(model.roleCounts, id: \.0) { role, count in
              GridRow {
                Text(role)
                Text(count, format: .number)
                  .monospacedDigit()
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 4)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(24)
  }
}

private struct PermissionRow: View {
  let title: String
  let granted: Bool
  let action: () -> Void

  var body: some View {
    HStack {
      Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
        .foregroundStyle(granted ? .green : .orange)
        .accessibilityHidden(true)
      Text(title)
      Spacer()
      Text(granted ? "Granted" : "Required")
        .foregroundStyle(.secondary)
      if !granted {
        Button("Request", action: action)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct CamelotMenu: View {
  @ObservedObject var model: CamelotAppModel

  var body: some View {
    Text(model.status)
    Divider()
    Button("Show Hints Now", action: model.scanFrontmostApplication)
      .disabled(
        model.isScanning
          || !model.permissions.accessibility
          || !model.permissions.inputMonitoring
      )
    Button("Refresh Permissions", action: model.refreshPermissions)
    Divider()
    Button("Quit Camelot") {
      NSApplication.shared.terminate(nil)
    }
  }
}
