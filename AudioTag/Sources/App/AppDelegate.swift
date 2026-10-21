//
//  AppDelegate.swift
//  AudioTag
//
//  Created by foyoodo on 24/10/2024.
//

import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let library = Library()
  private let sources = Sources()
  private var windowController: MainWindowController?
  /// Files asked to be opened before the window was.
  private var pendingURLs: [URL] = []

  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) {
      application.run()
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenu.make()
    sources.restore()
    let windowController = MainWindowController(library: library, sources: sources)
    self.windowController = windowController
    windowController.showWindow(nil)
    if !pendingURLs.isEmpty {
      windowController.open(pendingURLs)
      pendingURLs = []
    }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    guard let windowController else {
      pendingURLs += urls
      return
    }
    windowController.showWindow(nil)
    windowController.open(urls)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard library.hasModifiedTracks, let windowController else { return .terminateNow }
    windowController.confirmClosing { shouldTerminate in
      sender.reply(toApplicationShouldTerminate: shouldTerminate)
    }
    return .terminateLater
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  /// Asks for audio files or folders to show.
  @objc func openDocument(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.message =
      "Choose folders or audio files whose tags to edit. AudioTag can reach only what you choose."
    panel.prompt = "Open"
    let open = { [weak self] (response: NSApplication.ModalResponse) in
      guard response == .OK else { return }
      self?.windowController?.open(panel.urls)
    }
    if let window = windowController?.window, window.isVisible {
      panel.beginSheetModal(for: window, completionHandler: open)
    } else {
      panel.begin(completionHandler: open)
    }
  }
}
