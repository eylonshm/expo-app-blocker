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
    }
  }
}

// MARK: - ViewModel

class FamilyActivityPickerViewModel: ObservableObject {
  @Published var selection = FamilyActivitySelection()
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
    FamilyActivityPicker(selection: $viewModel.selection)
      .onChange(of: viewModel.selection) { newSelection in
        onSelectionChange(newSelection)
      }
  }
}
