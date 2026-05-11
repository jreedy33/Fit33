import SwiftUI

// MARK: - Select All TextField (cursor at end on focus)
struct SelectAllTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .numberPad
    var font: UIFont = .systemFont(ofSize: 17, weight: .semibold)
    var textAlignment: NSTextAlignment = .center
    var textColor: UIColor = .label // Default to system label color
    // Maximum allowed character count for the resulting text after a
    // user edit. `nil` means no limit. Used by the weight field to cap
    // input at "xx.xx" (5 chars) — see SetRowView's weight input.
    var maxLength: Int? = nil
    var onFocusChange: ((Bool) -> Void)? = nil
    // Optional external focus binding. When the bound value is `true`
    // and the field is not already first responder, `updateUIView`
    // pushes the underlying `UITextField` into first-responder state
    // on the next main-actor tick. When `false`, the field is left
    // alone — we deliberately don't force-resign because the user may
    // have moved focus themselves (tapping the keyboard's dismiss, or
    // another field), and force-resigning would race with that.
    //
    // Why we need this: `SelectAllTextField` wraps a UIKit
    // `UITextField`, not a SwiftUI `TextField`. SwiftUI's `@FocusState`
    // / `.focused($flag)` modifier has no effect on UIKit textfields
    // — it only steers SwiftUI's own focus system. Before this
    // binding existed, programmatic auto-focus (e.g. "drop the
    // cursor on the new set's reps field after ADD SET") was silently
    // a no-op: the FocusState bool flipped, but the UITextField never
    // became first responder. This binding closes that loop.
    var isFocused: Binding<Bool>? = nil
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.font = font
        textField.textAlignment = textAlignment
        textField.delegate = context.coordinator
        textField.backgroundColor = .clear
        textField.textColor = textColor
        textField.tintColor = .systemBlue
        
        textField.inputAccessoryView = nil
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        // Update text color dynamically (for completion state changes)
        uiView.textColor = textColor

        // Push external focus state into the UITextField. Deferred to
        // the next main-actor tick so we don't mutate first-responder
        // state inside SwiftUI's view-update cycle (which can produce
        // "Modifying state during view update" warnings via the
        // delegate -> onFocusChange -> @State write chain).
        if let focusBinding = isFocused,
           focusBinding.wrappedValue,
           !uiView.isFirstResponder {
            Task { @MainActor in
                guard focusBinding.wrappedValue,
                      !uiView.isFirstResponder else { return }
                uiView.becomeFirstResponder()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField
        
        init(_ parent: SelectAllTextField) {
            self.parent = parent
        }
        
        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange?(true)
            
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.1))
                textField.selectAll(nil)
            }
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChange?(false)
            parent.text = textField.text ?? ""
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Allow numbers and decimal separators (both . and , for international support)
            var allowedCharacters = CharacterSet.decimalDigits
            allowedCharacters.insert(charactersIn: ".,")  // Allow period and comma for decimals
            
            let characterSet = CharacterSet(charactersIn: string)
            
            if allowedCharacters.isSuperset(of: characterSet) {
                // Update binding with new text
                if let currentText = textField.text,
                   let textRange = Range(range, in: currentText) {
                    let newText = currentText.replacingCharacters(in: textRange, with: string)

                    // Prevent multiple decimal points
                    let decimalCount = newText.filter { $0 == "." || $0 == "," }.count
                    if decimalCount > 1 {
                        return false
                    }

                    // Enforce caller-supplied max length (e.g. weight =
                    // "xx.xx" → maxLength: 5). Backspace / delete paths
                    // produce `newText.count <= currentText.count`, so
                    // they're never blocked by this check.
                    if let maxLength = parent.maxLength, newText.count > maxLength {
                        return false
                    }

                    parent.text = newText
                }
                return true
            }
            return false
        }
        
        @objc func donePressed() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
