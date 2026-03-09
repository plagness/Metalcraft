import Cocoa

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate

// Set activation policy to regular (shows in Dock, accepts focus)
NSApp.setActivationPolicy(.regular)

// Create a minimal menu bar so Cmd+Q works
let mainMenu = NSMenu()
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit VoxelEngine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu
NSApp.mainMenu = mainMenu

NSApp.run()
