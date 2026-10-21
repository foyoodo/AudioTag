//
//  Motion.swift
//  AudioTag
//
//  Created by foyoodo on 21/10/2026.
//

import AppKit

/// The app's animations, which are skipped where the user asked to reduce motion.
@MainActor
enum Motion {
  static var isReduced: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)

  /// Animates the changes made in `changes`: those made through views' and constraints'
  /// `animator()`, and, `implicitly`, those to frames that layout makes too.
  static func animate(
    duration: TimeInterval = 0.25, timing: CAMediaTimingFunction = easeInOut,
    implicitly: Bool = true,
    _ changes: () -> Void, completion: (@MainActor () -> Void)? = nil
  ) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = isReduced ? 0 : duration
      context.timingFunction = timing
      context.allowsImplicitAnimation = implicitly && !isReduced
      changes()
    } completionHandler: {
      MainActor.assumeIsolated { completion?() }
    }
  }

  /// Fades a layer-backed view's contents from what they were to what they're set to next.
  static func crossfade(_ view: NSView, duration: TimeInterval = 0.2) {
    guard !isReduced, let layer = view.layer else { return }
    let transition = CATransition()
    transition.type = .fade
    transition.duration = duration
    layer.add(transition, forKey: "crossfade")
  }

  /// Shows one of two views in the same place, fading between them.
  static func show(_ shown: NSView, hiding hidden: NSView) {
    guard shown.isHidden || !hidden.isHidden else { return }
    shown.alphaValue = 0
    shown.isHidden = false
    animate(duration: 0.15) {
      shown.animator().alphaValue = 1
      hidden.animator().alphaValue = 0
    } completion: {
      // Unless shown again meanwhile.
      if hidden.alphaValue == 0 { hidden.isHidden = true }
    }
  }
}
