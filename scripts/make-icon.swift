// Hanasu のアプリアイコンを描いて build/AppIcon.iconset を作る。
//   swift scripts/make-icon.swift .
//   iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
// 会議室の落ち着いた青緑を背景に、重なった 2 つの吹き出し（複数人の会話）を置く。
// 奥の吹き出しには声の波形、手前の吹き出しには議事録の行を描き、「話した声が記録になる」ことを表す。
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

/// 角丸の吹き出し（本体としっぽ）。tailLeft なら左下、そうでなければ右下にしっぽを付ける。
/// 本体としっぽは別々の形なので、塗るときは fillBubble でまとめて塗る（つなぎ目に線が出ないように）。
func speechBubble(_ rect: CGRect, radius: CGFloat, tailLeft: Bool) -> [CGPath] {
    let bodyPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let tail = CGMutablePath()
    let baseY = rect.minY + 40          // 本体の内側から始めて、すき間ができないようにする
    let width: CGFloat = 92
    let drop: CGFloat = 64              // 本体の下端からしっぽの先まで
    if tailLeft {
        let x0 = rect.minX + radius * 0.75
        let tip = CGPoint(x: x0 - 18, y: rect.minY - drop)
        tail.move(to: CGPoint(x: x0, y: baseY))
        tail.addLine(to: CGPoint(x: x0 + width, y: baseY))
        tail.addQuadCurve(to: tip, control: CGPoint(x: x0 + width * 0.45, y: rect.minY - drop * 0.15))
        tail.addQuadCurve(to: CGPoint(x: x0, y: baseY), control: CGPoint(x: x0 - 4, y: rect.minY - drop * 0.3))
    } else {
        let x0 = rect.maxX - radius * 0.75
        let tip = CGPoint(x: x0 + 18, y: rect.minY - drop)
        tail.move(to: CGPoint(x: x0, y: baseY))
        tail.addLine(to: CGPoint(x: x0 - width, y: baseY))
        tail.addQuadCurve(to: tip, control: CGPoint(x: x0 - width * 0.45, y: rect.minY - drop * 0.15))
        tail.addQuadCurve(to: CGPoint(x: x0, y: baseY), control: CGPoint(x: x0 + 4, y: rect.minY - drop * 0.3))
    }
    tail.closeSubpath()
    return [bodyPath, tail]
}

/// 吹き出しを影つきで塗る。透明レイヤーにまとめて塗るので、影もつなぎ目も 1 つの形として扱われる。
func fillBubble(_ ctx: CGContext, _ parts: [CGPath], fill: CGColor, shadow: CGColor, blur: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: blur, color: shadow)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(fill)
    for part in parts {
        ctx.addPath(part)
        ctx.fillPath()
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
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
    ctx.setFillColor(color(0x24525B))
    ctx.fillPath()
    ctx.restoreGState()

    // 背景: 会議室の壁やホワイトボードのような、落ち着いた青緑
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0x3A7A7E), color(0x24525B), color(0x1A3B46)] as CFArray,
                                locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY), options: [])
    // 上からの柔らかい光
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: body.midX, y: body.maxY), startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.maxY), endRadius: 640, options: [])
    ctx.restoreGState()

    // 縁の細いハイライト
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    let shadow = color(0x0B1E25, 0.45)

    // 奥の吹き出し（琥珀色）: 話している声の波形
    let back = CGRect(x: 196, y: 486, width: 430, height: 300)
    fillBubble(ctx, speechBubble(back, radius: 92, tailLeft: true), fill: color(0xF2A83B), shadow: shadow, blur: 24)
    let barWidth: CGFloat = 34
    let heights: [CGFloat] = [70, 150, 210, 120, 80]
    var x: CGFloat = 262
    for h in heights {
        ctx.addPath(capsule(CGRect(x: x, y: 658 - h / 2, width: barWidth, height: h)))
        ctx.setFillColor(color(0x5A3A12, 0.85))
        ctx.fillPath()
        x += barWidth + 22
    }

    // 手前の吹き出し（生成りの紙）: 議事録の行
    let front = CGRect(x: 398, y: 262, width: 430, height: 316)
    fillBubble(ctx, speechBubble(front, radius: 96, tailLeft: false), fill: color(0xFBF6EC), shadow: shadow, blur: 30)
    let lineHeight: CGFloat = 34
    let lines: [(y: CGFloat, width: CGFloat, color: UInt32)] = [
        (488, 270, 0x24525B), (420, 320, 0x24525B), (352, 200, 0xD98C1F),
    ]
    for line in lines {
        ctx.addPath(capsule(CGRect(x: 456, y: line.y - lineHeight / 2, width: line.width, height: lineHeight)))
        ctx.setFillColor(color(line.color))
        ctx.fillPath()
    }
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
