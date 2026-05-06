import ExpoModulesCore
import FamilyControls
import ManagedSettings
import SwiftUI

public class ExpoAppBlockerPickerModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoAppBlockerPicker")

    View(FamilyActivityPickerNativeView.self) {
      Events("onSelectionChange")

      Prop("initialSelection") { (view: FamilyActivityPickerNativeView, selectionBase64: String) in
        guard !selectionBase64.isEmpty,
              let data = Data(base64Encoded: selectionBase64),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }
        view.setInitialSelection(selection)
      }

      Prop("theme") { (view: FamilyActivityPickerNativeView, theme: String) in
        view.setTheme(theme)
      }

      // Increment to clear selection in-process. Applied only after the initial
      // React prop snapshot so mounting with `{ clearTrigger: 0 }` does not wipe state.
      Prop("clearTrigger") { (view: FamilyActivityPickerNativeView, trigger: Int) in
        view.applyClearTrigger(trigger)
      }
    }
  }
}

// MARK: - ViewModel

class FamilyActivityPickerViewModel: ObservableObject {
  @Published var selection = FamilyActivitySelection()
  @Published var colorScheme: ColorScheme? = nil
  var didSetInitial = false
}

// MARK: - Native View (ExpoView wrapper)

class FamilyActivityPickerNativeView: ExpoView {
  let onSelectionChange = EventDispatcher()
  let viewModel = FamilyActivityPickerViewModel()
  private var hostingController: UIHostingController<InlinePickerContentView>?
  /// First `clearTrigger` snapshot from React establishes baseline — do not treat as clear.
  private var didSyncClearTriggerFromReact = false
  private var lastAppliedClearTrigger: Int = 0

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true

    let contentView = InlinePickerContentView(viewModel: viewModel) { [weak self] selection in
      self?.handleSelectionChange(selection)
    }
    let hc = UIHostingController(rootView: contentView)
    hc.view.backgroundColor = .clear
    addSubview(hc.view)
    hostingController = hc
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hostingController?.view.frame = bounds
  }

  func setInitialSelection(_ selection: FamilyActivitySelection) {
    guard !viewModel.didSetInitial else { return }
    viewModel.didSetInitial = true
    viewModel.selection = selection
  }

  /// Increments-only: first snapshot records baseline without clearing; higher values clear UI.
  func applyClearTrigger(_ trigger: Int) {
    if !didSyncClearTriggerFromReact {
      didSyncClearTriggerFromReact = true
      lastAppliedClearTrigger = trigger
      return
    }
    guard trigger > lastAppliedClearTrigger else { return }
    lastAppliedClearTrigger = trigger
    clearSelectionWithoutRemount()
  }

  private func clearSelectionWithoutRemount() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      viewModel.selection = FamilyActivitySelection()
    }
    viewModel.didSetInitial = false
  }

  func setTheme(_ theme: String) {
    switch theme.lowercased() {
    case "light":
      viewModel.colorScheme = .light
    case "dark":
      viewModel.colorScheme = .dark
    default:
      viewModel.colorScheme = nil // system default
    }
  }

  private func handleSelectionChange(_ selection: FamilyActivitySelection) {
    var appItems: [[String: Any]] = []
    for token in selection.applicationTokens {
      if let data = try? JSONEncoder().encode(token) {
        appItems.append([
          "type": "app",
          "token": data.base64EncodedString()
        ])
      }
    }

    var categoryItems: [[String: Any]] = []
    for token in selection.categoryTokens {
      if let data = try? JSONEncoder().encode(token) {
        categoryItems.append([
          "type": "category",
          "token": data.base64EncodedString()
        ])
      }
    }

    var selectionBase64 = ""
    if let selectionData = try? JSONEncoder().encode(selection) {
      selectionBase64 = selectionData.base64EncodedString()
    }

    let items = appItems + categoryItems

    // Do not append a synthetic "summary" row to `items` — JS counts `items.length` for UI and
    // `totalApps` / `totalCategories` / `selectionData` already carry the same metadata.
    onSelectionChange([
      "items": items,
      "totalApps": selection.applicationTokens.count,
      "totalCategories": selection.categoryTokens.count,
      "selectionData": selectionBase64
    ])
  }
}

// MARK: - SwiftUI Content View with inline FamilyActivityPicker

struct InlinePickerContentView: View {
  @ObservedObject var viewModel: FamilyActivityPickerViewModel
  var onSelectionChange: (FamilyActivitySelection) -> Void

  var body: some View {
    // Prefer binding-only resets: recreating FamilyActivityPicker (e.g. via `.id`) causes a visible flash.
    // If a future iOS/SDK build stops syncing empty selections here, reconsider a targeted redraw.
    let picker = FamilyActivityPicker(selection: $viewModel.selection)
      .onChange(of: viewModel.selection) { newSelection in
        onSelectionChange(newSelection)
      }

    if let scheme = viewModel.colorScheme {
      picker.environment(\.colorScheme, scheme)
    } else {
      picker
    }
  }
}
