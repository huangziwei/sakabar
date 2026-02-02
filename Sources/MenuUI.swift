import AppKit

enum MenuUI {
    static let menuWidth: CGFloat = 320
    private static let sectionHeaderSpacerImage: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        return image
    }()

    static func headerItem(appName: String, version: String?, summary: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuHeaderView(appName: appName, version: version, summary: summary)
        return item
    }

    static func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = sectionHeaderSpacerImage
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        item.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: attributes)
        return item
    }

    static func menuItem(title: String, action: Selector?, target: AnyObject?, symbolName: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        if let symbolName, let image = symbolImage(name: symbolName) {
            item.image = image
        }
        return item
    }

    static func placeholderItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        item.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        return item
    }

    static func statusImage(for state: ServiceState) -> NSImage {
        let color: NSColor
        switch state {
        case .running:
            color = NSColor.systemGreen
        case .starting:
            color = NSColor.systemOrange
        case .unhealthy:
            color = NSColor.systemRed
        case .stopped:
            color = NSColor.systemGray
        }
        return dotImage(color: color)
    }

    static func serviceTitle(label: String, status: String) -> NSAttributedString {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let statusAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let result = NSMutableAttributedString(string: label, attributes: titleAttributes)
        result.append(NSAttributedString(string: " - \(status)", attributes: statusAttributes))
        return result
    }

    static func symbolImage(name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    static func statusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let bodyRect = NSRect(x: 4, y: 3, width: 8, height: 10.5)
        let body = NSBezierPath(roundedRect: bodyRect, xRadius: 1.4, yRadius: 1.4)
        body.lineWidth = 1.2
        body.stroke()

        let handleRect = NSRect(x: 12, y: 6, width: 4, height: 6.5)
        let handle = NSBezierPath(roundedRect: handleRect, xRadius: 2.2, yRadius: 2.2)
        handle.lineWidth = 1.2
        handle.stroke()

        let foamPath = NSBezierPath()
        foamPath.append(NSBezierPath(ovalIn: NSRect(x: 3.5, y: 11.6, width: 4.0, height: 4.0)))
        foamPath.append(NSBezierPath(ovalIn: NSRect(x: 6.0, y: 12.2, width: 4.2, height: 4.2)))
        foamPath.append(NSBezierPath(ovalIn: NSRect(x: 8.6, y: 11.4, width: 4.2, height: 4.2)))
        foamPath.fill()

        let foamLine = NSBezierPath()
        foamLine.move(to: NSPoint(x: 5.0, y: 11.0))
        foamLine.line(to: NSPoint(x: 10.6, y: 11.0))
        foamLine.lineWidth = 1.1
        foamLine.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func dotImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 9, height: 9)
        let image = NSImage(size: size)
        image.lockFocus()
        let insetRect = NSRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(ovalIn: insetRect)
        color.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

final class MenuHeaderView: NSView {
    init(appName: String, version: String?, summary: String) {
        let frame = NSRect(x: 0, y: 0, width: MenuUI.menuWidth, height: 48)
        super.init(frame: frame)
        autoresizingMask = [.width]

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let summaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let titleText = NSMutableAttributedString(string: appName, attributes: titleAttributes)
        if let version, !version.isEmpty {
            titleText.append(NSAttributedString(string: " v\(version)", attributes: summaryAttributes))
        }
        let titleLabel = NSTextField(labelWithAttributedString: titleText)

        let summaryLabel = NSTextField(labelWithString: summary)
        summaryLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        summaryLabel.textColor = NSColor.secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, spacer, summaryLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}
