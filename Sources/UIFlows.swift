import AppKit

enum UIFlows {
    static func promptAddService() -> ServiceConfig? {
        let alert = NSAlert()
        alert.messageText = "Add Service"
        alert.informativeText = "Define the service command and optional host/port."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let nameField = makeField(placeholder: "ptts")
        let commandField = makeField(placeholder: "./bin/pmx uv run ptts play")
        let workingDirField = makeField(placeholder: "/Users/ziweih/projects/ptts")
        let hostField = makeField(placeholder: "localhost (optional)")
        let portField = makeField(placeholder: "1912 (optional)")
        let stopField = makeField(placeholder: "(optional)")

        let autoOpenButton = NSButton(checkboxWithTitle: "Auto-open URLs when ready", target: nil, action: nil)
        autoOpenButton.state = .on
        let startAtLoginButton = NSButton(checkboxWithTitle: "Start at login (this service)", target: nil, action: nil)

        let rows: [(String, NSTextField)] = [
            ("Name", nameField),
            ("Command (shell)", commandField),
            ("Working directory (optional)", workingDirField),
            ("Host (optional)", hostField),
            ("Port (optional)", portField),
            ("Stop command (optional)", stopField)
        ]

        let labelWidth: CGFloat = 190
        let fieldWidth: CGFloat = 360
        let rowHeight: CGFloat = 24
        let rowSpacing: CGFloat = 8
        let gap: CGFloat = 10
        let checkboxHeight: CGFloat = 20
        let checkboxSpacing: CGFloat = 4
        let optionsTopSpacing: CGFloat = 8

        let rowsHeight = CGFloat(rows.count) * rowHeight + CGFloat(rows.count - 1) * rowSpacing
        let optionsHeight = checkboxHeight * 2 + checkboxSpacing
        let totalHeight = rowsHeight + optionsTopSpacing + optionsHeight
        let totalWidth = labelWidth + gap + fieldWidth

        let container = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight))

        let rowsBottom = optionsHeight + optionsTopSpacing
        var y = rowsBottom + (rowsHeight - rowHeight)

        for (labelText, field) in rows {
            let label = NSTextField(labelWithString: labelText)
            label.alignment = .right
            label.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: rowHeight)
            field.frame = NSRect(x: labelWidth + gap, y: y, width: fieldWidth, height: rowHeight)
            container.addSubview(label)
            container.addSubview(field)
            y -= (rowHeight + rowSpacing)
        }

        startAtLoginButton.frame = NSRect(x: labelWidth + gap, y: 0, width: fieldWidth, height: checkboxHeight)
        autoOpenButton.frame = NSRect(x: labelWidth + gap, y: checkboxHeight + checkboxSpacing, width: fieldWidth, height: checkboxHeight)
        container.addSubview(autoOpenButton)
        container.addSubview(startAtLoginButton)

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

    private static func makeField(placeholder: String) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.isEditable = true
        field.isBezeled = true
        field.isSelectable = true
        return field
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
