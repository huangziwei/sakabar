import AppKit

enum MenuUI {
    static let menuWidth: CGFloat = 320

    static func headerItem(appName: String, summary: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuHeaderView(appName: appName, summary: summary)
        return item
    }

    static func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
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

        let circleRect = NSRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
        let circle = NSBezierPath(ovalIn: circleRect)
        circle.lineWidth = 1.4
        NSColor.black.setStroke()
        circle.stroke()

        let barHeight: CGFloat = 2.2
        let barWidth: CGFloat = 9.0
        let barX = (size.width - barWidth) / 2
        let topY = (size.height / 2) + 2.4
        let bottomY = (size.height / 2) - 4.4

        let topBar = NSBezierPath(
            roundedRect: NSRect(x: barX, y: topY, width: barWidth, height: barHeight),
            xRadius: 1.1,
            yRadius: 1.1
        )
        let bottomBar = NSBezierPath(
            roundedRect: NSRect(x: barX, y: bottomY, width: barWidth, height: barHeight),
            xRadius: 1.1,
            yRadius: 1.1
        )
        NSColor.black.setFill()
        topBar.fill()
        bottomBar.fill()

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
    init(appName: String, summary: String) {
        let frame = NSRect(x: 0, y: 0, width: MenuUI.menuWidth, height: 48)
        super.init(frame: frame)
        autoresizingMask = [.width]

        let titleLabel = NSTextField(labelWithString: appName)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let summaryLabel = NSTextField(labelWithString: summary)
        summaryLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        summaryLabel.textColor = NSColor.secondaryLabelColor

        let iconView = NSImageView()
        if let image = MenuUI.symbolImage(name: "gearshape.fill") {
            iconView.image = image
            iconView.contentTintColor = NSColor.secondaryLabelColor
        }
        iconView.isHidden = (iconView.image == nil)
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let titleStack = NSStackView(views: [iconView, titleLabel])
        titleStack.spacing = 6
        titleStack.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleStack, spacer, summaryLabel])
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
