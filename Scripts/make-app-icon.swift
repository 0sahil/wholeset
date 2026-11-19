#!/usr/bin/env swift
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Draws the Wholeset app icon with CoreGraphics and writes it as classic PNG icon sets.
//
//   swift Scripts/make-app-icon.swift                  default variant into both asset catalogs
//   swift Scripts/make-app-icon.swift barbell          another variant into both asset catalogs
//   swift Scripts/make-app-icon.swift path/to/dir      contact sheet of every variant, catalogs untouched
//   swift Scripts/make-app-icon.swift dots path/to/dir contact sheet with `dots` marked as selected
//   swift Scripts/make-app-icon.swift --list           the variant names
//
// Asset catalogs (all 1024 x 1024 single-size entries, as Xcode creates them):
//   Wholeset/Assets.xcassets/AppIcon.appiconset       default (opaque, no alpha channel), dark
//                                                     (accent mark on a transparent background, the
//                                                     system adds its dark backdrop), tinted (grayscale)
//   WholesetWatch/Assets.xcassets/AppIcon.appiconset  opaque; watchOS masks it to a circle
//
// An argument is an output directory if it contains a "/" or names an existing directory.
// The drawing has no randomness and no timestamps, so repeated runs write identical files.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colours

struct RGB {
    let red: CGFloat, green: CGFloat, blue: CGFloat

    init(_ hex: UInt32) {
        red = CGFloat((hex >> 16) & 0xFF) / 255
        green = CGFloat((hex >> 8) & 0xFF) / 255
        blue = CGFloat(hex & 0xFF) / 255
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// The brand accent (the Watch title, Log button and completed-set dots).
let accent = RGB(0xFF8A3D)
/// Near-black rather than black: the Watch face is black, and a pure black icon would lose its edge there.
let iconBackground = RGB(0x1C1C1E)
/// The mark in the tinted icon. The system tints by luminance, so the mark is white on black.
let tintedMark = RGB(0xFFFFFF)
let tintedBackground = RGB(0x000000)

// MARK: - Variants

/// A candidate mark. Each draws in a unit square centred on the origin (y up), so
/// the inscribed circle the Watch keeps has radius 0.5. Every mark stays inside radius 0.40.
enum Variant: String, CaseIterable {
    case w
    case dots
    case barbell

    static let `default` = Variant.w

    var summary: String {
        switch self {
        case .w: "geometric W: one rounded stroke, the app's initial"
        case .dots: "set dots: 1, 2 and 3 logged sets, the exercise page's dots building up"
        case .barbell: "barbell profile: two plates a side on a bar"
        }
    }

    func draw(in context: CGContext, color: CGColor) {
        context.setFillColor(color)
        context.setStrokeColor(color)
        switch self {
        case .w:
            // Outer arms reach higher than the middle apex; round caps and joins match the
            // rounded figures used on the Watch.
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -0.285, y: 0.165))
            path.addLine(to: CGPoint(x: -0.145, y: -0.175))
            path.addLine(to: CGPoint(x: 0, y: 0.075))
            path.addLine(to: CGPoint(x: 0.145, y: -0.175))
            path.addLine(to: CGPoint(x: 0.285, y: 0.165))
            context.addPath(path)
            context.setLineWidth(0.112)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
        case .dots:
            let pitch: CGFloat = 0.205
            let radius: CGFloat = 0.078
            // Shifted toward the upper left so the staircase's mass, not its box, sits at the centre.
            let offset = CGPoint(x: -0.03, y: 0.03)
            for column in 0..<3 {
                for row in 0...column {
                    let center = CGPoint(
                        x: CGFloat(column - 1) * pitch + offset.x,
                        y: CGFloat(row - 1) * pitch + offset.y
                    )
                    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                }
            }
        case .barbell:
            // Bar, then inner (tall) and outer (short) plates, mirrored.
            context.addPath(CGPath(roundedRect: CGRect(x: -0.385, y: -0.032, width: 0.77, height: 0.064), cornerWidth: 0.032, cornerHeight: 0.032, transform: nil))
            for side in [-1.0, 1.0] as [CGFloat] {
                let inner = CGRect(x: 0.165, y: -0.215, width: 0.092, height: 0.43)
                let outer = CGRect(x: 0.277, y: -0.145, width: 0.072, height: 0.29)
                for plate in [inner, outer] {
                    let rect = side > 0 ? plate : CGRect(x: -plate.maxX, y: plate.minY, width: plate.width, height: plate.height)
                    context.addPath(CGPath(roundedRect: rect, cornerWidth: 0.03, cornerHeight: 0.03, transform: nil))
                }
            }
            context.fillPath()
        }
    }
}

// MARK: - Rendering

enum Appearance: String, CaseIterable {
    case iosDefault, iosDark, iosTinted, watch

    var isOpaque: Bool { self != .iosDark }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-app-icon: \(message)\n".utf8))
    exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

func makeContext(width: Int, height: Int, opaque: Bool) -> CGContext {
    // Opaque bitmaps skip the alpha byte, so the PNG is written without an alpha channel.
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: alpha.rawValue
    ) else { fail("could not create a \(width)x\(height) bitmap") }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    return context
}

func image(of context: CGContext) -> CGImage {
    guard let image = context.makeImage() else { fail("could not read back a bitmap") }
    return image
}

/// Renders one icon PNG's pixels at `size`.
func renderIcon(_ variant: Variant, _ appearance: Appearance, size: Int = 1024) -> CGImage {
    let context = makeContext(width: size, height: size, opaque: appearance.isOpaque)
    let side = CGFloat(size)
    let full = CGRect(x: 0, y: 0, width: side, height: side)
    let markColor: CGColor
    switch appearance {
    case .iosDefault, .watch:
        context.setFillColor(iconBackground.cgColor())
        context.fill(full)
        markColor = accent.cgColor()
    case .iosDark:
        context.clear(full)
        markColor = accent.cgColor()
    case .iosTinted:
        context.setFillColor(tintedBackground.cgColor())
        context.fill(full)
        markColor = tintedMark.cgColor()
    }
    context.saveGState()
    context.translateBy(x: side / 2, y: side / 2)
    context.scaleBy(x: side, y: side)
    variant.draw(in: context, color: markColor)
    context.restoreGState()
    return image(of: context)
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("could not create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("could not write \(url.path)") }
}

func write(_ text: String, to url: URL) {
    do {
        try Data(text.utf8).write(to: url, options: .atomic)
    } catch {
        fail("could not write \(url.path): \(error.localizedDescription)")
    }
}

// MARK: - Asset catalogs

let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

/// Same layout and key order as the Contents.json Xcode writes for a single-size icon set.
func iosContents() -> String {
    """
    {
      "images" : [
        {
          "filename" : "AppIcon.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "dark"
            }
          ],
          "filename" : "AppIcon-Dark.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [
            {
              "appearance" : "luminosity",
              "value" : "tinted"
            }
          ],
          "filename" : "AppIcon-Tinted.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
}

func watchContents() -> String {
    """
    {
      "images" : [
        {
          "filename" : "AppIcon.png",
          "idiom" : "universal",
          "platform" : "watchos",
          "size" : "1024x1024"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
}

func writeCatalogs(_ variant: Variant) {
    let ios = repositoryRoot.appending(path: "Wholeset/Assets.xcassets/AppIcon.appiconset")
    let watch = repositoryRoot.appending(path: "WholesetWatch/Assets.xcassets/AppIcon.appiconset")
    for folder in [ios, watch] where !FileManager.default.fileExists(atPath: folder.path) {
        fail("missing \(folder.path); run the script from a Wholeset checkout")
    }
    writePNG(renderIcon(variant, .iosDefault), to: ios.appending(path: "AppIcon.png"))
    writePNG(renderIcon(variant, .iosDark), to: ios.appending(path: "AppIcon-Dark.png"))
    writePNG(renderIcon(variant, .iosTinted), to: ios.appending(path: "AppIcon-Tinted.png"))
    write(iosContents(), to: ios.appending(path: "Contents.json"))
    writePNG(renderIcon(variant, .watch), to: watch.appending(path: "AppIcon.png"))
    write(watchContents(), to: watch.appending(path: "Contents.json"))
    print("Wrote the \(variant.rawValue) icon (\(variant.summary)) to:")
    print("  \(ios.path)")
    print("  \(watch.path)")
}

// MARK: - Contact sheet

/// Approximates the iOS icon outline with a superellipse (exponent 5).
func iosMask(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let exponent: CGFloat = 5
    let steps = 360
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle), sine = sin(angle)
        let x = pow(abs(cosine), 2 / exponent) * (cosine < 0 ? -1 : 1)
        let y = pow(abs(sine), 2 / exponent) * (sine < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

/// Example tint for the simulated tinted icon (people pick their own).
let previewTint = RGB(0x7FB2FF)
/// Stand-in for the backdrop iOS draws behind a dark icon's transparent background.
let previewDarkBackdrop = RGB(0x1C1C1E)

/// Downscales a 1024 icon the way the system resamples a single-size PNG.
func scaled(_ icon: CGImage, to size: Int, opaque: Bool) -> CGImage {
    let context = makeContext(width: size, height: size, opaque: opaque)
    if !opaque { context.clear(CGRect(x: 0, y: 0, width: size, height: size)) }
    context.draw(icon, in: CGRect(x: 0, y: 0, width: size, height: size))
    return image(of: context)
}

/// What the Home Screen shows for each appearance, at `size`.
func displayed(_ icons: [Appearance: CGImage], _ appearance: Appearance, size: Int) -> CGImage {
    guard let icon = icons[appearance] else { fail("missing \(appearance.rawValue) icon") }
    switch appearance {
    case .iosDefault, .watch:
        return scaled(icon, to: size, opaque: true)
    case .iosDark:
        let context = makeContext(width: size, height: size, opaque: true)
        context.setFillColor(previewDarkBackdrop.cgColor())
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.draw(icon, in: CGRect(x: 0, y: 0, width: size, height: size))
        return image(of: context)
    case .iosTinted:
        // Luminance of the grayscale icon becomes the tint's intensity over a dark backdrop.
        let gray = scaled(icon, to: size, opaque: true)
        let context = makeContext(width: size, height: size, opaque: true)
        context.draw(gray, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { fail("no pixel buffer") }
        let tint = [previewTint.red, previewTint.green, previewTint.blue]
        let backdrop = [previewDarkBackdrop.red, previewDarkBackdrop.green, previewDarkBackdrop.blue]
        for y in 0..<size {
            for x in 0..<size {
                let base = y * context.bytesPerRow + x * 4
                let level = CGFloat(pixels[base]) / 255
                for channel in 0..<3 {
                    let value = backdrop[channel] * (1 - level) + tint[channel] * level
                    pixels[base + channel] = UInt8((value * 255).rounded())
                }
            }
        }
        return image(of: context)
    }
}

struct Sheet {
    let context: CGContext
    let height: CGFloat

    /// Converts a top-down layout y into CoreGraphics' bottom-up y.
    func flip(_ top: CGFloat, _ itemHeight: CGFloat = 0) -> CGFloat { height - top - itemHeight }

    func fill(_ rect: CGRect, _ color: RGB) {
        context.setFillColor(color.cgColor())
        context.fill(CGRect(x: rect.minX, y: flip(rect.minY, rect.height), width: rect.width, height: rect.height))
    }

    func text(_ string: String, x: CGFloat, top: CGFloat, size: CGFloat, color: RGB, bold: Bool = false) {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor(),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: flip(top + size))
        CTLineDraw(line, context)
    }

    func icon(_ image: CGImage, x: CGFloat, top: CGFloat, size: CGFloat, circle: Bool) {
        let rect = CGRect(x: x, y: flip(top, size), width: size, height: size)
        context.saveGState()
        context.addPath(circle ? CGPath(ellipseIn: rect, transform: nil) : iosMask(rect))
        context.clip()
        context.draw(image, in: rect)
        context.restoreGState()
    }
}

func writeContactSheet(selected: Variant, to directory: URL) {
    let margin: CGFloat = 48, gap: CGFloat = 32
    let bigPanel: CGFloat = 1024 + 2 * 24
    let sizes = [180, 120, 60, 40]
    let labelWidth: CGFloat = 230, cellGap: CGFloat = 28
    let rows: [(Appearance, String)] = [
        (.iosDefault, "iOS default"), (.iosDark, "iOS dark"), (.iosTinted, "iOS tinted"), (.watch, "watchOS"),
    ]
    let gridWidth = labelWidth + CGFloat(sizes.reduce(0, +)) + CGFloat(sizes.count + 1) * cellGap
    let rowHeight: CGFloat = 180 + 44
    let gridHeight = 70 + CGFloat(rows.count) * rowHeight
    let blockHeight = 96 + max(bigPanel, gridHeight)
    let titleHeight: CGFloat = 150
    let width = margin * 2 + bigPanel + gap * 2 + gridWidth * 2
    let height = titleHeight + CGFloat(Variant.allCases.count) * (blockHeight + gap) + margin
    let sheet = Sheet(
        context: makeContext(width: Int(width), height: Int(height), opaque: true),
        height: height
    )
    let paper = RGB(0xFFFFFF), ink = RGB(0x000000), muted = RGB(0x6C6C70)
    let light = RGB(0xF2F2F7), dark = RGB(0x000000)

    sheet.fill(CGRect(x: 0, y: 0, width: width, height: height), paper)
    sheet.text("Wholeset app icon candidates", x: margin, top: margin, size: 40, color: ink, bold: true)
    sheet.text(
        "Each variant at 1024 (iOS mask) and at 180, 120, 60 and 40 px, on light and dark. iOS outline approximated (superellipse); "
            + "dark and tinted shown over a flat stand-in for the system backdrop, tinted with an example blue; watchOS masked to a circle.",
        x: margin, top: margin + 56, size: 20, color: muted
    )

    var top = titleHeight
    for variant in Variant.allCases {
        let icons = Dictionary(uniqueKeysWithValues: Appearance.allCases.map { ($0, renderIcon(variant, $0)) })
        var title = variant.rawValue
        if variant == .default { title += "  (default)" }
        if variant == selected && selected != .default { title += "  (selected)" }
        sheet.text(title, x: margin, top: top, size: 34, color: ink, bold: true)
        sheet.text("\(variant.summary).  swift Scripts/make-app-icon.swift \(variant.rawValue)", x: margin, top: top + 46, size: 20, color: muted)
        let blockTop = top + 96

        sheet.fill(CGRect(x: margin, y: blockTop, width: bigPanel, height: bigPanel), light)
        guard let big = icons[.iosDefault] else { fail("missing default icon") }
        sheet.icon(big, x: margin + 24, top: blockTop + 24, size: 1024, circle: false)

        for (index, background) in [light, dark].enumerated() {
            let left = margin + bigPanel + gap + CGFloat(index) * (gridWidth + gap)
            let textColor = index == 0 ? ink : RGB(0xFFFFFF)
            let subtle = index == 0 ? muted : RGB(0x98989D)
            sheet.fill(CGRect(x: left, y: blockTop, width: gridWidth, height: gridHeight), background)
            sheet.text(index == 0 ? "Light background" : "Dark background", x: left + cellGap, top: blockTop + 20, size: 22, color: textColor, bold: true)
            var x = left + labelWidth + cellGap
            for size in sizes {
                sheet.text("\(size)", x: x, top: blockTop + 24, size: 18, color: subtle)
                x += CGFloat(size) + cellGap
            }
            for (rowIndex, row) in rows.enumerated() {
                let rowTop = blockTop + 70 + CGFloat(rowIndex) * rowHeight
                sheet.text(row.1, x: left + cellGap, top: rowTop + 70, size: 20, color: textColor)
                var cellX = left + labelWidth + cellGap
                for size in sizes {
                    let shown = displayed(icons, row.0, size: size)
                    sheet.icon(shown, x: cellX, top: rowTop + (180 - CGFloat(size)) / 2, size: CGFloat(size), circle: row.0 == .watch)
                    cellX += CGFloat(size) + cellGap
                }
            }
        }
        top += blockHeight + gap
    }

    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        fail("could not create \(directory.path): \(error.localizedDescription)")
    }
    let output = directory.appending(path: "icon-preview.png")
    writePNG(image(of: sheet.context), to: output)
    print("Wrote the contact sheet to \(output.path)")
}

// MARK: - Main

var variant = Variant.default
var outputDirectory: URL?
for argument in CommandLine.arguments.dropFirst() {
    var isDirectory: ObjCBool = false
    if argument == "--list" {
        for candidate in Variant.allCases {
            print("\(candidate.rawValue)\(candidate == .default ? " (default)" : ""): \(candidate.summary)")
        }
        exit(0)
    } else if argument == "-h" || argument == "--help" {
        print("usage: swift Scripts/make-app-icon.swift [variant] [output-directory]")
        print("variants: \(Variant.allCases.map(\.rawValue).joined(separator: ", ")) (default: \(Variant.default.rawValue))")
        exit(0)
    } else if let named = Variant(rawValue: argument) {
        variant = named
    } else if argument.contains("/") || (FileManager.default.fileExists(atPath: argument, isDirectory: &isDirectory) && isDirectory.boolValue) {
        outputDirectory = URL(fileURLWithPath: argument, isDirectory: true)
    } else {
        fail("unknown variant \"\(argument)\"; use one of \(Variant.allCases.map(\.rawValue).joined(separator: ", ")), or a directory containing \"/\"")
    }
}

if let outputDirectory {
    writeContactSheet(selected: variant, to: outputDirectory)
} else {
    writeCatalogs(variant)
}
