import AppKit
import SwiftUI

@main
struct AIUsageApp: App {
    @NSApplicationDelegateAdaptor(AIUsageAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AIUsageAppDelegate: NSObject, NSApplicationDelegate {
    let services: AppServices
    private var menuBarController: MenuBarController?

    override init() {
        services = AppServices(startingUpdater: !Self.isRunningTests)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        if Self.isInstalledInApplicationsFolder {
            services.launchAtLogin.enableByDefaultIfNeeded()
        }

        let services = self.services
        let menuBarController = MenuBarController(
            store: services.store,
            preferences: services.preferences,
            launchAtLogin: services.launchAtLogin,
            updateController: services.updateController
        )
        menuBarController.start()
        self.menuBarController = menuBarController
        installMainMenu()

        Task {
            await services.store.refresh()
            services.preferences.configureDefaultMenuBarProviders(
                availableItemsByProvider:
                    services.store.availableMenuBarItemsByProvider
            )
            if !services.preferences.hasCompletedInitialSetup {
                menuBarController.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
        menuBarController = nil
    }

    @objc
    private func openSettings(_ sender: Any?) {
        menuBarController?.showSettings()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "AI Usage")

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit AI Usage",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Without an Edit menu, text fields such as the DeepSeek API key
        // cannot receive Cmd+V, Cmd+C, Cmd+X or Cmd+A.
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var isInstalledInApplicationsFolder: Bool {
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let homeApplicationsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path

        return bundlePath.hasPrefix("/Applications/") ||
            bundlePath.hasPrefix("\(homeApplicationsPath)/")
    }
}
