// Hanasu のアプリアイコンを描いて Resources/AppIcon.icns を作る。
//   swift scripts/make-icon.swift
// 声の波形が文字の行に変わっていく図柄に、AI の整形を表すきらめきを添える。
import AppKit

let canvas: CGFloat = 1024

/// macOS のアイコン形状に近い超楕円（連続曲率の角丸）
func squirclePath(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c >= 0 ? 1 : -1) * pow(abs(c), 2 / exponent)
        let y = cy + b * (s >= 0 ? 1 : -1) * pow(abs(s), 2 / exponent)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func capsule(_ rect: CGRect) -> CGPath {
    let r = min(rect.width, rect.height) / 2
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// 4 方向に尖ったきらめき
func sparkle(center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let inner = radius * 0.28
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 + .pi / 2
        let r = i % 2 == 0 ? radius : inner
        let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        if i == 0 {
            path.move(to: p)
        } else {
            // 辺を内側に少し曲げて柔らかい星にする
            let prevAngle = CGFloat(i - 1) * .pi / 4 + .pi / 2
            let mid = (angle + prevAngle) / 2
            let control = CGPoint(x: center.x + cos(mid) * inner * 0.6, y: center.y + sin(mid) * inner * 0.6)
            path.addQuadCurve(to: p, control: control)
        }
    }
    let first = CGPoint(x: center.x + cos(.pi / 2) * radius, y: center.y + sin(.pi / 2) * radius)
    let lastMid = CGFloat(7.5) * .pi / 4 + .pi / 2
    path.addQuadCurve(to: first, control: CGPoint(x: center.x + cos(lastMid) * inner * 0.6, y: center.y + sin(lastMid) * inner * 0.6))
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // アイコン本体（1024 の中に 824 角。macOS のアイコングリッド）
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squirclePath(in: body)

    // 影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x4B3FE0))
    ctx.fillPath()
    ctx.restoreGState()

    // 背景のグラデーション（藍 → 紫 → 桃）
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [
        color(0x3D5AFE), color(0x7C4DFF), color(0xE040FB), color(0xFF6E9C),
    ] as CFArray, locations: [0, 0.42, 0.78, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // 上からの柔らかい光（ガラスの質感）
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.32), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: body.midX - 120, y: body.maxY - 60), startRadius: 0,
                           endCenter: CGPoint(x: body.midX - 120, y: body.maxY - 60), endRadius: 620, options: [])
    ctx.restoreGState()

    // 縁の細いハイライト
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xFFFFFF, 0.28))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    // 図柄（白）。左の縦の波形が、右の横の文字の行に変わる
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: color(0x2A0E6B, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let centerY: CGFloat = 470
    let barWidth: CGFloat = 50
    let gap: CGFloat = 30
    let heights: [CGFloat] = [150, 290, 420, 300]
    // 波形 4 本（290）＋すき間 42＋いちばん長い行 250 を本体の中央に置く
    var x: CGFloat = 512 - (290 + 42 + 250) / 2
    for (i, h) in heights.enumerated() {
        ctx.addPath(capsule(CGRect(x: x, y: centerY - h / 2, width: barWidth, height: h)))
        ctx.setFillColor(color(0xFFFFFF, 0.72 + 0.28 * CGFloat(i) / CGFloat(heights.count - 1)))
        ctx.fillPath()
        x += barWidth + gap
    }
    // 文字の行
    let lineX = x + 12
    let lines: [(dy: CGFloat, width: CGFloat)] = [(118, 200), (0, 250), (-118, 170)]
    for line in lines {
        ctx.addPath(capsule(CGRect(x: lineX, y: centerY + line.dy - barWidth / 2, width: line.width, height: barWidth)))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
    }
    // きらめき
    ctx.addPath(sparkle(center: CGPoint(x: 728, y: 744), radius: 84))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.addPath(sparkle(center: CGPoint(x: 812, y: 650), radius: 36))
    ctx.setFillColor(color(0xFFFFFF, 0.85))
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func renderPNG(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = context.cgContext
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try renderPNG(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try renderPNG(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try renderPNG(size: 1024).write(to: root.appendingPathComponent("build/AppIcon-preview.png"))
print("wrote \(iconset.path)")
