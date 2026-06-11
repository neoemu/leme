import AppKit

// Leme icon v3: same 8-spoke wheel, with depth — richer background gradient,
// soft drop shadow under the glyph, gradient-filled wheel, glowing core,
// hairline inner rim light (Craft/Codex-style polish).

let accent = CGColor(red: 0.33, green: 0.71, blue: 0.93, alpha: 1)

func draw(into ctx: CGContext, size: CGFloat) {
    let s = size / 1024.0
    let inset = 100.0 * s
    let bgRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let corner = 185.0 * s

    ctx.saveGState()
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Background: deep indigo diagonal gradient
    let bgGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.20, green: 0.235, blue: 0.36, alpha: 1),
            CGColor(red: 0.10, green: 0.115, blue: 0.19, alpha: 1),
            CGColor(red: 0.045, green: 0.05, blue: 0.09, alpha: 1),
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: size * 0.30, y: size - inset),
        end: CGPoint(x: size * 0.70, y: inset),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Accent glow behind the wheel, slightly above center
    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.33, green: 0.62, blue: 0.95, alpha: 0.38),
            CGColor(red: 0.30, green: 0.45, blue: 0.95, alpha: 0.10),
            CGColor(red: 0.30, green: 0.45, blue: 0.95, alpha: 0.0),
        ] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: size / 2, y: size / 2 + 40 * s), startRadius: 0,
        endCenter: CGPoint(x: size / 2, y: size / 2 + 40 * s), endRadius: 470 * s,
        options: []
    )

    // Wheel geometry (same as approved v1)
    let center = CGPoint(x: size / 2, y: size / 2)
    let rimRadius = 248.0 * s
    let rimWidth = 58.0 * s
    let spokeWidth = 34.0 * s
    let handleWidth = 48.0 * s
    let handleLength = 92.0 * s
    let hubRadius = 84.0 * s

    // Glyph with uniform shadow + gradient: draw everything inside a
    // transparency layer (avoids path-union winding artifacts), shadow applies
    // to the composited layer, then tint it with sourceIn gradient.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -16 * s),
        blur: 34 * s,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
    )
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    let solid = CGColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1)
    ctx.setStrokeColor(solid)
    ctx.setFillColor(solid)
    ctx.setLineCap(.round)

    ctx.setLineWidth(rimWidth)
    ctx.strokeEllipse(in: CGRect(
        x: center.x - rimRadius, y: center.y - rimRadius,
        width: rimRadius * 2, height: rimRadius * 2
    ))

    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4
        let dx = cos(angle)
        let dy = sin(angle)

        ctx.setLineWidth(spokeWidth)
        ctx.move(to: CGPoint(x: center.x + dx * hubRadius * 0.7, y: center.y + dy * hubRadius * 0.7))
        ctx.addLine(to: CGPoint(
            x: center.x + dx * (rimRadius - rimWidth / 2 + 4 * s),
            y: center.y + dy * (rimRadius - rimWidth / 2 + 4 * s)
        ))
        ctx.strokePath()

        ctx.setLineWidth(handleWidth)
        ctx.move(to: CGPoint(
            x: center.x + dx * (rimRadius + rimWidth / 2),
            y: center.y + dy * (rimRadius + rimWidth / 2)
        ))
        ctx.addLine(to: CGPoint(
            x: center.x + dx * (rimRadius + rimWidth / 2 + handleLength),
            y: center.y + dy * (rimRadius + rimWidth / 2 + handleLength)
        ))
        ctx.strokePath()
    }

    ctx.fillEllipse(in: CGRect(
        x: center.x - hubRadius, y: center.y - hubRadius,
        width: hubRadius * 2, height: hubRadius * 2
    ))

    // Tint the layer with a vertical gradient (light top, cooler bottom)
    ctx.setBlendMode(.sourceIn)
    let wheelGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
            CGColor(red: 0.76, green: 0.81, blue: 0.90, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        wheelGradient,
        start: CGPoint(x: center.x, y: center.y + rimRadius + rimWidth / 2 + handleLength),
        end: CGPoint(x: center.x, y: center.y - rimRadius - rimWidth / 2 - handleLength),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Accent core with its own glow
    let coreRadius = 40.0 * s
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 52 * s, color: accent.copy(alpha: 0.85))
    ctx.setFillColor(accent)
    ctx.fillEllipse(in: CGRect(
        x: center.x - coreRadius, y: center.y - coreRadius,
        width: coreRadius * 2, height: coreRadius * 2
    ))
    ctx.restoreGState()

    // Core highlight (small specular dot, upper-left)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.fillEllipse(in: CGRect(
        x: center.x - coreRadius * 0.45, y: center.y + coreRadius * 0.10,
        width: coreRadius * 0.55, height: coreRadius * 0.55
    ))

    // Hairline inner rim light on the squircle edge
    let innerPath = CGPath(
        roundedRect: bgRect.insetBy(dx: 3 * s, dy: 3 * s),
        cornerWidth: corner - 3 * s, cornerHeight: corner - 3 * s, transform: nil
    )
    ctx.addPath(innerPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(4 * s)
    ctx.strokePath()

    ctx.restoreGState()
}

func savePNG(pixels: Int, to path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    draw(into: nsCtx.cgContext, size: CGFloat(pixels))
    nsCtx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/leme-icons-v3"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    savePNG(pixels: px, to: "\(outDir)/icon_\(px).png")
}
