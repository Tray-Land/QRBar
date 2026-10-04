import AppKit
import OSLog
import QRBarKit
import SwiftUI

/// Owns the menu bar icon and its popover. Left-click toggles the popover; right-click (or
/// Control-click) shows Open, Settings, and Quit.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()

    init(model: AppModel) {
        self.model = model
        super.init()

        statusItem.autosaveName = "QRBar"
        if let button = statusItem.button {
            let image = NSImage(resource: .menuBarIcon)
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            image.accessibilityDescription = "QRBar"
            button.image = image
            button.toolTip = "QRBar"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Fixed size, so the popover never resizes (and shifts) when switching tabs or pages.
        popover.contentViewController = NSHostingController(rootView: PopoverView().environment(model))
        popover.contentSize = PopoverView.size
        popover.behavior = .transient
        popover.delegate = self

        model.presentPopover = { [weak self] in self?.showPopover() }
        model.dismissPopover = { [weak self] in self?.popover.performClose(nil) }
    }

    func showPopover() {
        showPopover(remainingAttempts: 40)
    }

    private func showPopover(remainingAttempts: Int) {
        guard let button = statusItem.button else {
            return
        }

        // Just after launch the menu bar hasn't moved the item into place yet, and a popover anchored
        // there opens in the screen's bottom-left corner. Wait (up to 2 s) until it's in the menu bar.
        if !isInMenuBar(button.window), remainingAttempts > 0 {
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                showPopover(remainingAttempts: remainingAttempts - 1)
            }
            return
        }

        if !isInMenuBar(button.window) {
            Log.app.notice("Status item still isn't in the menu bar; showing the popover anyway")
        }

        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
        button.highlight(true)
        model.popoverDidShow()
    }

    private func isInMenuBar(_ window: NSWindow?) -> Bool {
        guard let window, let screen = window.screen, window.frame.height > 0 else {
            return false
        }

        // The menu bar sits above the screen's visible frame (or above the screen when it auto-hides).
        return window.frame.minY >= screen.visibleFrame.maxY - 1
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        model.popoverDidClose()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showMenu() {
        popover.performClose(nil)

        let menu = NSMenu()
        menu.addItem(withTitle: "Open QRBar", action: #selector(openFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit QRBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Attaching the menu only for this click keeps left-click free for the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openFromMenu() {
        model.page = .main
        showPopover()
    }

    @objc private func openSettingsFromMenu() {
        model.page = .settings
        showPopover()
    }
}
