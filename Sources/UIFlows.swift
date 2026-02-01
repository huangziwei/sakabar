import AppKit

enum UIFlows {
    static func promptAddService() -> ServiceConfig? {
        let alert = NSAlert()
        alert.messageText = "Add Service"
        alert.informativeText = "Define the service command and optional host/port."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let nameField = makeField(placeholder: "ptts")
        let commandField = makeField(placeholder: "./bin/pmx uv run ptts play", isMonospace: true)
        let workingDirField = makeField(placeholder: "/Users/ziweih/projects/ptts", isMonospace: true)
        let hostField = makeField(placeholder: "localhost (optional)")
        let portField = makeField(placeholder: "1912 (optional)")
        let stopField = makeField(placeholder: "(optional)", isMonospace: true)

        let autoOpenButton = NSButton(checkboxWithTitle: "Auto-open URLs when ready", target: nil, action: nil)
        autoOpenButton.state = .on
        autoOpenButton.controlSize = .small
        let startAtLoginButton = NSButton(checkboxWithTitle: "Start at login (this service)", target: nil, action: nil)
        startAtLoginButton.controlSize = .small

        let serviceRows: [(String, NSTextField)] = [
            ("Name", nameField),
            ("Command (shell)", commandField),
            ("Working directory (optional)", workingDirField),
            ("Stop command (optional)", stopField)
        ]

        let networkRows: [(String, NSTextField)] = [
            ("Host (optional)", hostField),
            ("Port (optional)", portField)
        ]

        let serviceSection = makeSection(title: "Service", rows: serviceRows)
        let networkSection = makeSection(title: "Network", rows: networkRows)

        let optionsStack = NSStackView(views: [autoOpenButton, startAtLoginButton])
        optionsStack.orientation = .vertical
        optionsStack.spacing = 6
        optionsStack.alignment = .leading

        let behaviorSection = makeSection(title: "Behavior", content: optionsStack)
        let hintLabel = makeHelpLabel("Tip: leave host/port blank to infer from the command or default to localhost.")

        let containerStack = NSStackView(views: [serviceSection, networkSection, behaviorSection, hintLabel])
        containerStack.orientation = .vertical
        containerStack.spacing = 12
        containerStack.alignment = .leading
        containerStack.translatesAutoresizingMaskIntoConstraints = false

        let targetWidth: CGFloat = 560
        let container = NSView(frame: NSRect(x: 0, y: 0, width: targetWidth, height: 10))
        container.addSubview(containerStack)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: container.topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.layoutSubtreeIfNeeded()
        container.setFrameSize(NSSize(width: targetWidth, height: containerStack.fittingSize.height))

        alert.accessoryView = container
        NSApp.activate(ignoringOtherApps: true)
        let window = alert.window
        window.initialFirstResponder = nameField
        window.makeKeyAndOrderFront(nil)

        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            return nil
        }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let command = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || command.isEmpty {
            showError(message: "Name and command are required.")
            return nil
        }

        let workingDir = workingDirField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostInput = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let portInput = portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferred = inferHostPort(command: command)
        let hostValue = hostInput.isEmpty ? (inferred.host ?? "") : hostInput
        let portValue = portInput.isEmpty ? inferred.port : portInput
        let port = portValue.flatMap { Int($0) }
        if !portValue.isNilOrEmpty && port == nil {
            showError(message: "Port must be a number.")
            return nil
        }

        let stopCommand = stopField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        return ServiceConfig(
            label: name,
            command: command,
            workingDir: workingDir.isEmpty ? nil : workingDir,
            host: hostValue.isEmpty ? nil : hostValue,
            port: port,
            stopCommand: stopCommand.isEmpty ? nil : stopCommand,
            autoOpen: autoOpenButton.state == .on,
            startAtLogin: startAtLoginButton.state == .on
        )
    }

    static func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func makeField(placeholder: String, isMonospace: Bool = false) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.isEditable = true
        field.isBezeled = true
        field.isSelectable = true
        if isMonospace {
            field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        return field
    }

    private static func makeSection(title: String, rows: [(String, NSTextField)]) -> NSStackView {
        let label = makeSectionLabel(title)
        let grid = makeFormGrid(rows: rows)
        let stack = NSStackView(views: [label, grid])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        return stack
    }

    private static func makeSection(title: String, content: NSView) -> NSStackView {
        let label = makeSectionLabel(title)
        let stack = NSStackView(views: [label, content])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading
        return stack
    }

    private static func makeSectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.secondaryLabelColor
        return label
    }

    private static func makeHelpLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.textColor = NSColor.secondaryLabelColor
        return label
    }

    private static func makeFormGrid(rows: [(String, NSTextField)]) -> NSGridView {
        let rowViews: [[NSView]] = rows.map { labelText, field in
            let label = NSTextField(labelWithString: labelText)
            label.alignment = .right
            label.setContentHuggingPriority(.required, for: .horizontal)

            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 340).isActive = true

            return [label, field]
        }

        let grid = NSGridView(views: rowViews)
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private static func inferHostPort(command: String) -> (host: String?, port: String?) {
        let tokens = command.split(separator: " ").map(String.init)
        var host: String?
        var port: String?

        for (idx, token) in tokens.enumerated() {
            if token == "--host", idx + 1 < tokens.count {
                host = tokens[idx + 1]
            } else if token.hasPrefix("--host=") {
                host = String(token.dropFirst("--host=".count))
            } else if token == "--port", idx + 1 < tokens.count {
                port = tokens[idx + 1]
            } else if token.hasPrefix("--port=") {
                port = String(token.dropFirst("--port=".count))
            } else if token == "-p", idx + 1 < tokens.count {
                port = tokens[idx + 1]
            } else if token.hasPrefix("HOST=") {
                host = String(token.dropFirst("HOST=".count))
            } else if token.hasPrefix("PORT=") {
                port = String(token.dropFirst("PORT=".count))
            } else if token.contains("://") {
                if let url = URL(string: token) {
                    host = url.host ?? host
                    if let p = url.port {
                        port = String(p)
                    }
                }
            }
        }

        return (host, port)
    }
}

private extension String? {
    var isNilOrEmpty: Bool {
        guard let value = self else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
