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

      // Increment this value to programmatically clear the picker's selection
      // without remounting. Works because FamilyActivityPicker is driven by a
      // @Binding — setting the backing @Published var resets the SwiftUI view.
      Prop("clearTrigger") { (view: FamilyActivityPickerNativeView, trigger: Int) in
        view.clearSelection()
      }
    }
  }
}

// MARK: - ViewModel

class FamilyActivityPickerViewModel: ObservableObject {
  @Published var selection = FamilyActivitySelection()
  @Published var colorScheme: ColorScheme? = nil
  @Published var clearCounter: Int = 0
  var didSetInitial = false
}

// MARK: - Native View (ExpoView wrapper)

class FamilyActivityPickerNativeView: ExpoView {
  let onSelectionChange = EventDispatcher()
  let viewModel = FamilyActivityPickerViewModel()
  private var hostingController: UIHostingController<InlinePickerContentView>?

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

  func clearSelection() {
    viewModel.selection = FamilyActivitySelection()
    viewModel.didSetInitial = false
    viewModel.clearCounter += 1
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
    let summary: [String: Any] = [
      "type": "summary",
      "totalApps": selection.applicationTokens.count,
      "totalCategories": selection.categoryTokens.count,
      "selectionData": selectionBase64
    ]

    onSelectionChange([
      "items": items + [summary],
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
    // .id(clearCounter) forces SwiftUI to destroy and recreate FamilyActivityPicker
    // when clearSelection() is called. The picker does not respond to external
    // binding mutations after initial presentation — recreation is the only reset path.
    let picker = FamilyActivityPicker(selection: $viewModel.selection)
      .id(viewModel.clearCounter)
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
