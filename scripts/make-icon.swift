// Gera o ícone do app em Fern/Resources/Assets.xcassets/AppIcon.appiconset.
// Uso: swift scripts/make-icon.swift [caminho-de-um-png-de-preview]
//
// O desenho: uma folha de samambaia que sobe e se enrola em espiral no topo, como o
// broto da samambaia quando começa a se abrir. Tudo é vetor (Core Graphics), em
// coordenadas de 0 a 1 dentro do quadrado do ícone, para sair nítido em todos os tamanhos.
import AppKit

let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
let output = URL(fileURLWithPath: "Fern/Resources/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Ponto de uma curva de Bézier quadrática e a direção (tangente) nesse ponto.
func quad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> (point: CGPoint, tangent: CGVector) {
    let u = 1 - t
    let point = CGPoint(
        x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x,
        y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
    let tangent = CGVector(
        dx: 2 * u * (c.x - p0.x) + 2 * t * (p1.x - c.x), dy: 2 * u * (c.y - p0.y) + 2 * t * (p1.y - c.y))
    return (point, tangent)
}

/// Folíolo: uma folhinha pontuda, desenhada a partir da base, apontando para `angle`.
func leaflet(at base: CGPoint, angle: CGFloat, length: CGFloat, width: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: .zero)
    path.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.45, y: width))
    path.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.45, y: -width))
    var transform = CGAffineTransform(translationX: base.x, y: base.y).rotated(by: angle)
    return path.copy(using: &transform) ?? path
}

func drawIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("contexto") }

    // Grade de ícones do macOS: o quadrado ocupa ~80% da tela, com cantos arredondados.
    let inset = size * 0.1
    let side = size - inset * 2
    let rect = CGRect(x: inset, y: inset, width: side, height: side)
    let tile = CGPath(roundedRect: rect, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)

    // Sombra suave sob o quadrado, como nos ícones do sistema.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: color(0x000000, 0.28))
    context.addPath(tile)
    context.setFillColor(color(0x1F5C3F))
    context.fillPath()
    context.restoreGState()

    // Fundo: verde-floresta, mais claro no alto.
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let background = CGGradient(
        colorsSpace: space, colors: [color(0x3E9A63), color(0x1B5238)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        background, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY),
        options: [])

    // Daqui em diante, coordenadas de 0 a 1 dentro do quadrado.
    context.translateBy(x: rect.minX, y: rect.minY)
    context.scaleBy(x: side, y: side)

    let frondColor = color(0xF2F0D8)
    let leafColor = color(0xCDEBB5)

    // Caule: sobe da base e entra na espiral pelo lado esquerdo.
    let center = CGPoint(x: 0.6, y: 0.63)
    let startRadius: CGFloat = 0.155
    let stemStart = CGPoint(x: 0.41, y: 0.13)
    let stemEnd = CGPoint(x: center.x - startRadius, y: center.y)
    let stemControl = CGPoint(x: 0.47, y: 0.36)

    // Folíolos ao longo do caule, alternando os lados e diminuindo em direção ao topo.
    context.setFillColor(leafColor)
    let pairs = 6
    for index in 0..<pairs {
        let t = 0.22 + CGFloat(index) * 0.12
        let (point, tangent) = quad(stemStart, stemControl, stemEnd, t)
        let direction = atan2(tangent.dy, tangent.dx)
        let length = 0.17 - CGFloat(index) * 0.019
        let width = length * 0.28
        for side in [-1.0, 1.0] as [CGFloat] {
            // Os folíolos saem do caule inclinados para cima.
            let angle = direction + side * (.pi / 2 - 0.55)
            context.addPath(leaflet(at: point, angle: angle, length: length, width: width))
            context.fillPath()
        }
    }

    // Caule e espiral num traço só, com pontas arredondadas.
    let frond = CGMutablePath()
    frond.move(to: stemStart)
    frond.addQuadCurve(to: stemEnd, control: stemControl)
    // Espiral logarítmica, em sentido horário a partir da esquerda do centro.
    let turns: CGFloat = 1.15
    let endRadius: CGFloat = 0.03
    let steps = 120
    let shrink = log(startRadius / endRadius) / (turns * 2 * .pi)
    for step in 1...steps {
        let swept = CGFloat(step) / CGFloat(steps) * turns * 2 * .pi
        let angle = CGFloat.pi - swept
        let radius = startRadius * exp(-shrink * swept)
        frond.addLine(to: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
    }
    context.addPath(frond)
    context.setStrokeColor(frondColor)
    // Nos tamanhos pequenos (barra do Finder, listas), um traço mais grosso se lê melhor.
    context.setLineWidth(pixels <= 32 ? 0.085 : 0.058)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    context.restoreGState()

    guard let image = context.makeImage() else { fatalError("imagem") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return png
}

if CommandLine.arguments.count > 1 {
    // Só um preview grande, para conferir o desenho.
    try drawIcon(pixels: 1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    exit(0)
}

var images: [String] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try drawIcon(pixels: points * scale).write(to: output.appendingPathComponent(name))
    images.append(
        """
            { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
        """)
}
let contents = """
    {
      "images" : [
    \(images.joined(separator: ",\n"))
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Ícones gerados em \(output.path)")
