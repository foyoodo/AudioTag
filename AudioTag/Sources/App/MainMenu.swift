//
//  MainMenu.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// The menu bar, built in code.
@MainActor
enum MainMenu {
  static func make() -> NSMenu {
    let name = ProcessInfo.processInfo.processName
    let servicesMenu = NSMenu(title: "Services")
    let windowMenu = menu(
      "Window",
      [
        item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
        item("Zoom", #selector(NSWindow.performZoom(_:))),
        .separator(),
        item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
      ])
    let helpMenu = menu("Help", [])

    let mainMenu = NSMenu()
    for submenuMenu in [
      menu(
        name,
        [
          item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
          .separator(),
          submenu(servicesMenu),
          .separator(),
          item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
          item(
            "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
            [.command, .option]),
          item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
          .separator(),
          item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
        ]),
      menu(
        "File",
        [
          item("Open…", #selector(AppDelegate.openDocument(_:)), "o"),
          item(
            "New Folder", #selector(MainSplitViewController.newFolder(_:)), "n",
            [.command, .shift]),
          .separator(),
          item("Close", #selector(NSWindow.performClose(_:)), "w"),
          item("Save", #selector(MainWindowController.saveDocument(_:)), "s"),
          item("Revert Changes", #selector(MainWindowController.revertDocumentToSaved(_:))),
          .separator(),
          item("Rename", #selector(SidebarViewController.renameItem(_:))),
          // Command-Delete.
          item("Move to Trash", #selector(TrackListViewController.moveToTrash(_:)), "\u{8}"),
        ]),
      menu(
        "Edit",
        [
          item("Undo", Selector(("undo:")), "z"),
          item("Redo", Selector(("redo:")), "z", [.command, .shift]),
          .separator(),
          item("Cut", #selector(NSText.cut(_:)), "x"),
          item("Copy", #selector(NSText.copy(_:)), "c"),
          item("Paste", #selector(NSText.paste(_:)), "v"),
          item("Delete", #selector(NSText.delete(_:))),
          item("Select All", #selector(NSText.selectAll(_:)), "a"),
          .separator(),
          item("Find", #selector(MainWindowController.focusSearch(_:)), "f"),
        ]),
      menu(
        "View",
        [
          item(
            "Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s",
            [.command, .control]),
          item(
            "Show Inspector", #selector(NSSplitViewController.toggleInspector(_:)), "i",
            [.command, .option]),
          .separator(),
          item("Reload", #selector(MainWindowController.reloadFolder(_:)), "r"),
          .separator(),
          item(
            "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
            [.command, .control]),
        ]),
      windowMenu,
      helpMenu,
    ] {
      mainMenu.addItem(submenu(submenuMenu))
    }
    NSApp.servicesMenu = servicesMenu
    NSApp.windowsMenu = windowMenu
    NSApp.helpMenu = helpMenu
    return mainMenu
  }

  private static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
    let menu = NSMenu(title: title)
    menu.items = items
    return menu
  }

  private static func submenu(_ menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  private static func item(
    _ title: String, _ action: Selector, _ key: String = "",
    _ modifiers: NSEvent.ModifierFlags = .command
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    return item
  }
}
