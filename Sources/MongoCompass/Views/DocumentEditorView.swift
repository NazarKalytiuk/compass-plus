import SwiftUI

struct DocumentEditorView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case insert
        case edit([String: Any])
    }

    let mode: Mode

    @State private var jsonText: String = ""
    @State private var validationError: String?
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar
            ThemedDivider()

            // Editor
            editorArea

            // Validation / error messages
            if let error = validationError {
                errorRow(error, color: Theme.amber)
            }
            if let error = saveError {
                errorRow(error, color: Theme.crimson)
            }

            ThemedDivider()

            // Action bar
            actionBar
        }
        .frame(width: 650, height: 550)
        .background(Theme.surface)
        .onAppear {
            initializeJSON()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Image(systemName: isInsert ? "plus.circle.fill" : "pencil.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.green)
            Text(isInsert ? "Insert Document" : "Edit Document")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Spacer()

            Button {
                formatJSON()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                    Text("Format")
                }
            }
            .buttonStyle(.ghost)
            .help("Auto-format JSON")
        }
        .padding(16)
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        TextEditor(text: $jsonText)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Theme.midnight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(validationError != nil ? Theme.amber.opacity(0.5) : Theme.border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: jsonText) {
                validateJSON()
            }
    }

    // MARK: - Error Row

    private func errorRow(_ message: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.ghost)

            Spacer()

            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 8)
            }

            Button {
                save()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isInsert ? "plus" : "checkmark")
                    Text(isInsert ? "Insert" : "Save")
                }
            }
            .buttonStyle(.accent)
            .disabled(validationError != nil || isSaving)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var isInsert: Bool {
        if case .insert = mode { return true }
        return false
    }

    private func initializeJSON() {
        switch mode {
        case .insert:
            jsonText = "{\n  \n}"
        case .edit(let document):
            // Remove _id from the editable document for safety
            var editableDoc = document
            editableDoc.removeValue(forKey: "_id")
            if let data = try? JSONSerialization.data(withJSONObject: editableDoc, options: [.prettyPrinted, .sortedKeys]),
               let string = String(data: data, encoding: .utf8) {
                jsonText = string
            } else {
                jsonText = "{}"
            }
        }
    }

    private func validateJSON() {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationError = "JSON cannot be empty."
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            validationError = "Invalid text encoding."
            return
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            if obj is [String: Any] {
                validationError = nil
            } else {
                validationError = "Root element must be a JSON object ({...})."
            }
        } catch {
            validationError = "Invalid JSON: \(error.localizedDescription)"
        }
    }

    private func formatJSON() {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return }
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            let formatted = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            if let string = String(data: formatted, encoding: .utf8) {
                jsonText = string
                validationError = nil
            }
        } catch {
            validationError = "Cannot format: \(error.localizedDescription)"
        }
    }

    private func save() {
        // Validate first
        validateJSON()
        guard validationError == nil else { return }

        isSaving = true
        saveError = nil

        Task {
            switch mode {
            case .insert:
                await viewModel.insertDocument(jsonText)
                if viewModel.error == nil {
                    dismiss()
                } else {
                    saveError = viewModel.error
                }
            case .edit(let originalDoc):
                let docId = extractDocumentId(originalDoc)
                await viewModel.updateDocument(id: docId, json: jsonText)
                if viewModel.error == nil {
                    dismiss()
                } else {
                    saveError = viewModel.error
                }
            }
            isSaving = false
        }
    }
}
