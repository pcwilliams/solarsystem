// Platform.swift
// SolarSystem
//
// Cross-platform typealiases that let the same source file compile unchanged
// on iOS/iPadOS (UIKit) and macOS (AppKit). The goal is that everything in
// Models/, Services/, ViewModels/, and most of Views/ stays 100% platform-
// agnostic — the only conditional code lives in this file and in the handful
// of places where the platforms genuinely diverge (scene view gesture setup,
// graphics context construction).
//
// Usage rules:
//   - Never write `UIColor`, `UIImage`, `UIViewRepresentable` etc. outside
//     this file or files already guarded with #if. Use the `Platform…`
//     typealiases instead.
//   - When a truly platform-specific branch is unavoidable (e.g. setting up
//     NSGestureRecognizer vs UIGestureRecognizer), localise the `#if os(macOS)`
//     block to the smallest unit that contains the divergence.
//   - SceneKit, SwiftUI, Foundation, Core Graphics, simd are all identical on
//     both platforms and should never be guarded.

import SwiftUI

#if canImport(UIKit)
import UIKit

/// UIColor on iOS, NSColor on macOS.
public typealias PlatformColor = UIColor

/// UIImage on iOS, NSImage on macOS.
public typealias PlatformImage = UIImage

/// UIView on iOS, NSView on macOS.
public typealias PlatformView = UIView

/// SwiftUI wrapper protocol. Views that host SceneKit or AppKit/UIKit content
/// conform to this instead of `UIViewRepresentable` / `NSViewRepresentable`
/// directly — the protocol resolves to whichever is appropriate for the
/// current build target.
public typealias PlatformViewRepresentable = UIViewRepresentable

#elseif canImport(AppKit)
import AppKit

public typealias PlatformColor = NSColor
public typealias PlatformImage = NSImage
public typealias PlatformView = NSView
public typealias PlatformViewRepresentable = NSViewRepresentable

#endif

// MARK: - CGImage bridging

/// Extract a `CGImage` from a `PlatformImage`, regardless of platform.
///
/// `UIImage.cgImage` is a direct property; `NSImage` has to be asked to
/// render its best representation via `cgImage(forProposedRect:context:hints:)`.
/// SceneKit happily accepts either a `PlatformImage` or a `CGImage` for texture
/// contents, but some code paths (geometry data, manual pixel reads) prefer
/// `CGImage` — hence this helper.
func cgImage(from image: PlatformImage) -> CGImage? {
    #if canImport(UIKit)
    return image.cgImage
    #elseif canImport(AppKit)
    var rect = CGRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    #endif
}

// MARK: - Image construction from CGImage

/// Build a `PlatformImage` from a `CGImage`, hiding the UIImage / NSImage
/// divergence. Used by `TextureGenerator` where the procedural drawing path
/// produces a raw `CGImage` that then needs to be wrapped so SceneKit's
/// `material.diffuse.contents` accepts it with the correct scale on every
/// platform.
///
/// Not expressed as an extension initialiser because NSImage already has
/// `init(cgImage:size:)` and an extension with the same signature collides
/// and recurses infinitely.
func makePlatformImage(cgImage: CGImage, size: CGSize) -> PlatformImage {
    #if canImport(UIKit)
    return PlatformImage(cgImage: cgImage)
    #elseif canImport(AppKit)
    return PlatformImage(cgImage: cgImage, size: size)
    #endif
}
