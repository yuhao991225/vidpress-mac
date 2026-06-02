import AppKit
import SwiftUI

@main
@MainActor
final class VidPressApplication: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: VidPressApplication?

    private let viewModel = CompressionViewModel()
    private var window: NSWindow?

    static func main() {
        let application = NSApplication.shared
        let delegate = VidPressApplication()
        retainedDelegate = delegate

        application.delegate = delegate
        application.setActivationPolicy(.regular)
        delegate.configureMainMenu()
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rootView = ContentView(viewModel: viewModel)
            .frame(minWidth: 1040, minHeight: 680)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "VidPress"
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func addVideos(_ sender: Any?) {
        viewModel.chooseFiles()
    }

    @objc private func startQueue(_ sender: Any?) {
        viewModel.startQueue()
    }

    @objc private func cancelQueue(_ sender: Any?) {
        viewModel.cancelQueue()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "关于 VidPress",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "退出 VidPress",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let addItem = NSMenuItem(title: "添加视频...", action: #selector(addVideos(_:)), keyEquivalent: "o")
        addItem.target = self
        fileMenu.addItem(addItem)

        let startItem = NSMenuItem(title: "开始压缩", action: #selector(startQueue(_:)), keyEquivalent: "\r")
        startItem.keyEquivalentModifierMask = [.command]
        startItem.target = self
        fileMenu.addItem(startItem)

        let cancelItem = NSMenuItem(title: "取消任务", action: #selector(cancelQueue(_:)), keyEquivalent: ".")
        cancelItem.keyEquivalentModifierMask = [.command]
        cancelItem.target = self
        fileMenu.addItem(cancelItem)

        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
