import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var ipMenuItem: NSMenuItem!
    private var clientsMenuItem: NSMenuItem!
    private var permissionsMenuItem: NSMenuItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startServer()
        checkPermissions()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "command.square.fill", accessibilityDescription: "Android Remote") {
                button.image = img
            } else {
                button.title = "📱"
            }
            button.toolTip = "RecDrive Android Remote Receiver"
        }
        
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "RecDrive Android Remote", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        statusMenuItem = NSMenuItem(title: "Stato: Avvio in corso...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        let ip = RemoteServer.getLocalIPAddress() ?? "Non rilevato"
        let port = RemoteServer.defaultPort
        ipMenuItem = NSMenuItem(title: "IP Mac: \(ip):\(port) (Clicca per copiare)", action: #selector(copyIPAddress), keyEquivalent: "c")
        ipMenuItem.target = self
        menu.addItem(ipMenuItem)
        
        clientsMenuItem = NSMenuItem(title: "Client Android: 0 connessi", action: nil, keyEquivalent: "")
        clientsMenuItem.isEnabled = false
        menu.addItem(clientsMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        permissionsMenuItem = NSMenuItem(title: "Permessi Accessibilità: Verifica...", action: #selector(checkAndPromptPermissions), keyEquivalent: "")
        permissionsMenuItem.target = self
        menu.addItem(permissionsMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quick local testing items
        let testSubmenu = NSMenu()
        let testNext = NSMenuItem(title: "Avanti Slide (Right Arrow)", action: #selector(testSlideNext), keyEquivalent: "")
        testNext.target = self
        testSubmenu.addItem(testNext)
        
        let testPrev = NSMenuItem(title: "Indietro Slide (Left Arrow)", action: #selector(testSlidePrev), keyEquivalent: "")
        testPrev.target = self
        testSubmenu.addItem(testPrev)
        
        let testPlay = NSMenuItem(title: "Avvia Keynote (⌥⌘P)", action: #selector(testSlidePlay), keyEquivalent: "")
        testPlay.target = self
        testSubmenu.addItem(testPlay)
        
        let testItem = NSMenuItem(title: "Test Iniezione Tasti", action: nil, keyEquivalent: "")
        testItem.submenu = testSubmenu
        menu.addItem(testItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let restartItem = NSMenuItem(title: "Riavvia Server", action: #selector(restartServer), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)
        
        let quitItem = NSMenuItem(title: "Esci", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private func startServer() {
        RemoteServer.shared.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.statusMenuItem.title = "Stato: \(status)"
            }
        }
        
        RemoteServer.shared.onClientCountChanged = { [weak self] count in
            DispatchQueue.main.async {
                self?.clientsMenuItem.title = "Client Android: \(count) connessi"
                if let button = self?.statusItem.button {
                    button.title = count > 0 ? " (\(count))" : ""
                }
            }
        }
        
        RemoteServer.shared.start(port: RemoteServer.defaultPort)
    }
    
    private func checkPermissions() {
        let isTrusted = InputSynthesizer.shared.hasAccessibilityPermission()
        if isTrusted {
            permissionsMenuItem.title = "✅ Accessibilità: Concessa"
        } else {
            permissionsMenuItem.title = "⚠️ Accessibilità: Richiesta (Clicca)"
        }
    }
    
    @objc private func copyIPAddress() {
        let ip = RemoteServer.getLocalIPAddress() ?? "127.0.0.1"
        let full = "\(ip):\(RemoteServer.shared.currentPort)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
        print("[MacReceiver] Copiato negli appunti: \(full)")
    }
    
    @objc private func checkAndPromptPermissions() {
        if !InputSynthesizer.shared.hasAccessibilityPermission() {
            InputSynthesizer.shared.promptAccessibilityPermission()
        }
        checkPermissions()
    }
    
    @objc private func testSlideNext() {
        InputSynthesizer.shared.execute(IncomingCommand(type: "presentation", action: "next"))
    }
    
    @objc private func testSlidePrev() {
        InputSynthesizer.shared.execute(IncomingCommand(type: "presentation", action: "prev"))
    }
    
    @objc private func testSlidePlay() {
        InputSynthesizer.shared.execute(IncomingCommand(type: "presentation", action: "play"))
    }
    
    @objc private func restartServer() {
        RemoteServer.shared.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            RemoteServer.shared.start(port: RemoteServer.defaultPort)
        }
    }
    
    @objc private func quitApp() {
        RemoteServer.shared.stop()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Application Entry Point

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // Runs in Menu Bar without Dock icon
    app.run()
}
