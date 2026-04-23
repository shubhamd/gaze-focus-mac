import AppKit
import AVFoundation

/// Five-step onboarding for first launch. Plain AppKit, text-only.
/// Ramp-Up R4 adds animated illustrations, numbered screenshot guides,
/// and Back buttons.
final class OnboardingViewController: NSViewController {

    enum Step: Int {
        case welcome, howItWorks, camera, accessibility, calibration
    }

    private var step: Step = .welcome
    private var pollTimer: Timer?
    private var cameraErrorVisible = false

    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let secondaryLabel = NSTextField(wrappingLabelWithString: "")
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "", target: nil, action: nil)

    var onStartCalibration: (() -> Void)?

    // MARK: - View

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false

        bodyLabel.font = NSFont.systemFont(ofSize: 14)
        bodyLabel.alignment = .center
        bodyLabel.maximumNumberOfLines = 8
        bodyLabel.isEditable = false
        bodyLabel.isBezeled = false
        bodyLabel.drawsBackground = false

        secondaryLabel.font = NSFont.systemFont(ofSize: 12)
        secondaryLabel.alignment = .center
        secondaryLabel.maximumNumberOfLines = 4
        secondaryLabel.textColor = NSColor.systemRed
        secondaryLabel.isEditable = false
        secondaryLabel.isBezeled = false
        secondaryLabel.drawsBackground = false

        primaryButton.target = self
        primaryButton.action = #selector(primaryTapped)
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"

        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryTapped)
        secondaryButton.bezelStyle = .rounded
        secondaryButton.isHidden = true

        for v in [titleLabel, bodyLabel, secondaryLabel, primaryButton, secondaryButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 56),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 40),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -40),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            bodyLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 56),
            bodyLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -56),

            secondaryLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 20),
            secondaryLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 56),
            secondaryLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -56),

            primaryButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -40),
            primaryButton.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            secondaryButton.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -12),
            secondaryButton.centerXAnchor.constraint(equalTo: root.centerXAnchor)
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Steps

    private func render() {
        cameraErrorVisible = false
        secondaryLabel.stringValue = ""
        secondaryButton.isHidden = true

        switch step {
        case .welcome:
            titleLabel.stringValue = "GazeFocus"
            bodyLabel.stringValue = "Look at a screen. Your cursor follows."
            primaryButton.title = "Get Started"

        case .howItWorks:
            titleLabel.stringValue = "How it works"
            bodyLabel.stringValue = "GazeFocus watches your eyes using the webcam and moves the cursor to the screen you’re looking at. Everything happens on your Mac. No video ever leaves your device."
            primaryButton.title = "Continue"

        case .camera:
            titleLabel.stringValue = "Camera access"
            bodyLabel.stringValue = "GazeFocus needs permission to use your webcam so it can detect which screen you're looking at. Video is processed entirely on-device and never stored or transmitted."
            primaryButton.title = "Grant Camera Access"
            if PermissionsManager.hasCameraPermission {
                advance()
                return
            }

        case .accessibility:
            titleLabel.stringValue = "Accessibility access"
            bodyLabel.stringValue = "GazeFocus needs Accessibility permission to move the cursor for you.\n\n1. Click Open System Settings below.\n2. Find GazeFocus in the list.\n3. Toggle the switch on."
            primaryButton.title = "Open System Settings"
            if PermissionsManager.hasAccessibility {
                advance()
                return
            }
            startAccessibilityPolling()

        case .calibration:
            titleLabel.stringValue = "One last step — quick calibration"
            bodyLabel.stringValue = "We'll show 5 dots. Look at each one until it disappears. Takes about 15 seconds."
            primaryButton.title = "Start Calibration"
        }
    }

    // MARK: - Actions

    @objc private func primaryTapped() {
        switch step {
        case .welcome, .howItWorks:
            advance()

        case .camera:
            handleCameraPrimary()

        case .accessibility:
            PermissionsManager.openAccessibilityPrefs()

        case .calibration:
            onStartCalibration?()
        }
    }

    @objc private func secondaryTapped() {
        if step == .camera {
            PermissionsManager.openCameraPrefs()
            startCameraPolling()
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        step = next
        render()
    }

    private func handleCameraPrimary() {
        switch PermissionsManager.cameraStatus {
        case .authorized:
            advance()
        case .notDetermined:
            PermissionsManager.requestCamera { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.advance()
                } else {
                    self.showCameraDeniedError()
                }
            }
        case .denied, .restricted:
            showCameraDeniedError()
        @unknown default:
            showCameraDeniedError()
        }
    }

    private func showCameraDeniedError() {
        cameraErrorVisible = true
        secondaryLabel.stringValue = "Camera access was denied. Open System Settings and enable Camera for GazeFocus, then return here."
        secondaryButton.title = "Open System Settings"
        secondaryButton.isHidden = false
        primaryButton.title = "I granted access"
        startCameraPolling()
    }

    private func startCameraPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if PermissionsManager.hasCameraPermission {
                self.advance()
            }
        }
    }

    private func startAccessibilityPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if PermissionsManager.hasAccessibility {
                self.advance()
            }
        }
    }
}
