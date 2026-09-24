import AppKit
import SwiftUI

public enum StatusItemState: Equatable {
    case idle
    case recording
    case stopping
    case completed
}

/// AppKit controller managing the NSStatusItem menu bar icon,
/// dynamic animations (recording pulse, upload indicator), and popover.
@MainActor
public final class StatusItemController: NSObject {
    public static let shared = StatusItemController()
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var pulseTimer: Timer?
    private var isPulseOn = false
    
    public private(set) var currentState: StatusItemState = .idle
    
    public override init() {
        super.init()
    }
    
    public func setupStatusItem(contentView: AnyView) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
        
        let p = NSPopover()
        p.contentSize = NSSize(width: 320, height: 440)
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: contentView)
        self.popover = p
        
        updateState(.idle)
    }
    
    // MARK: - State Updates & Icon Rendering
    
    public func updateState(_ state: StatusItemState) {
        self.currentState = state
        guard let button = statusItem?.button else { return }
        
        pulseTimer?.invalidate()
        pulseTimer = nil
        
        switch state {
        case .idle:
            button.title = ""
            button.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "RecDrive Idle")
            button.image?.isTemplate = true
            
        case .recording:
            startRecordingAnimation()
            
        case .stopping:
            button.title = " Sto fermando..."
            button.image = NSImage(systemSymbolName: "circle.slash", accessibilityDescription: "Stopping")
            button.image?.isTemplate = true
            
        case .completed:
            button.title = " Salvato"
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Completed")
            button.image?.isTemplate = false
            
            // Revert to idle after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                Task { @MainActor in
                    if StatusItemController.shared.currentState == .completed {
                        StatusItemController.shared.updateState(.idle)
                    }
                }
            }
        }
    }
    
    private func startRecordingAnimation() {
        guard let button = statusItem?.button else { return }
        isPulseOn = true
        button.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        button.image?.isTemplate = false
        
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let button = self.statusItem?.button else { return }
                self.isPulseOn.toggle()
                let iconName = self.isPulseOn ? "record.circle.fill" : "record.circle"
                button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Recording")
                button.image?.isTemplate = false
            }
        }
    }
    
    // MARK: - Popover Actions
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let p = popover else { return }
        
        if p.isShown {
            p.performClose(sender)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    public func closePopover() {
        popover?.performClose(nil)
    }
}
