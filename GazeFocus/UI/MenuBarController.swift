import AppKit

enum TrackingState {
    case active
    case paused
    case permissionMissing
    case singleDisplay  // only one display connected — nothing to switch to
}

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private var titleItem: NSMenuItem!
    private var pauseItem: NSMenuItem!

    private(set) var state: TrackingState = .active {
        didSet { render() }
    }

    var onTogglePause: (() -> Void)?
    var onRecalibrate: (() -> Void)?

    override init() {
        // variableLength so a text fallback can size naturally if the SF
        // Symbol fails to load. squareLength would pin us to a fixed width
        // and let an empty icon hide in the notch overflow on MacBook Pros.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.behavior = []
        super.init()
        buildMenu()
        render()
    }

    func setState(_ newState: TrackingState) {
        state = newState
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        titleItem = NSMenuItem(title: "GazeFocus — Active", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())

        pauseItem = NSMenuItem(title: "Pause", action: #selector(didTapPause), keyEquivalent: "g")
        pauseItem.keyEquivalentModifierMask = [.command, .option]
        pauseItem.target = self
        menu.addItem(pauseItem)

        let recalibrate = NSMenuItem(title: "Recalibrate…", action: #selector(didTapRecalibrate), keyEquivalent: "")
        recalibrate.target = self
        menu.addItem(recalibrate)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit GazeFocus",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private func render() {
        renderIcon()
        renderTitles()
    }

    private func renderIcon() {
        guard let button = statusItem.button else { return }
        let (symbolName, tint) = iconDescriptor(for: state)
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "GazeFocus")?
            .withSymbolConfiguration(config)
        image?.isTemplate = (tint == nil)
        if let image {
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            // Hard fallback so the status item is never invisible when the
            // SF Symbol fails to load.
            button.image = nil
            button.imagePosition = .noImage
            button.title = "Gaze"
        }
        button.contentTintColor = tint
    }

    private func renderTitles() {
        switch state {
        case .active:
            titleItem.title = "GazeFocus — Active"
            pauseItem.title = "Pause"
            pauseItem.isEnabled = true
        case .paused:
            titleItem.title = "GazeFocus — Paused"
            pauseItem.title = "Resume"
            pauseItem.isEnabled = true
        case .permissionMissing:
            titleItem.title = "GazeFocus — Permission Required"
            pauseItem.title = "Pause"
            pauseItem.isEnabled = false
        case .singleDisplay:
            titleItem.title = "GazeFocus — Single Display"
            pauseItem.title = "Pause"
            pauseItem.isEnabled = false
        }
    }

    private func iconDescriptor(for state: TrackingState) -> (String, NSColor?) {
        switch state {
        case .active:
            return ("eye", nil)
        case .paused:
            return ("eye.slash", nil)
        case .permissionMissing:
            return ("exclamationmark.triangle", .systemRed)
        case .singleDisplay:
            return ("eye.slash", .tertiaryLabelColor)
        }
    }

    @objc private func didTapPause() {
        onTogglePause?()
    }

    @objc private func didTapRecalibrate() {
        onRecalibrate?()
    }
}
