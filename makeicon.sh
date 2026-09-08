#!/bin/sh
# Generates AppIcon.icns procedurally — no image assets in the repo.
set -e
cd "$(dirname "$0")"

cat > /tmp/pool8_icon.swift <<'EOF'
import AppKit
let s: CGFloat = 1024
let img = NSImage(size: NSSize(width: s, height: s))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let full = CGRect(x: 0, y: 0, width: s, height: s)
ctx.addPath(CGPath(roundedRect: full.insetBy(dx: 40, dy: 40), cornerWidth: 190, cornerHeight: 190, transform: nil))
ctx.clip()
// dark backdrop
ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.09, blue: 0.08, alpha: 1))
ctx.fill(full)
// green felt circle
ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.38, blue: 0.21, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 90, y: 90, width: 844, height: 844))
// wood rail
ctx.setStrokeColor(CGColor(srgbRed: 0.38, green: 0.24, blue: 0.12, alpha: 1))
ctx.setLineWidth(56)
ctx.strokeEllipse(in: CGRect(x: 90, y: 90, width: 844, height: 844))
// side pockets
ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 462, y: 890, width: 100, height: 100))
ctx.fillEllipse(in: CGRect(x: 462, y: 34, width: 100, height: 100))
// 8-ball
ctx.setFillColor(CGColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 282, y: 282, width: 460, height: 460))
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, white: 0.97, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 397, y: 397, width: 230, height: 230))
let a: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 150, weight: .bold),
    .foregroundColor: NSColor.black,
]
let str = "8" as NSString
let sz = str.size(withAttributes: a)
str.draw(at: CGPoint(x: 512 - sz.width / 2, y: 512 - sz.height / 2), withAttributes: a)
// highlight
ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
ctx.fillEllipse(in: CGRect(x: 360, y: 600, width: 95, height: 95))
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "icon_1024.png"))
EOF

swift /tmp/pool8_icon.swift

rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for sz in 16 32 128 256 512; do
    sips -z $sz $sz icon_1024.png --out AppIcon.iconset/icon_${sz}x${sz}.png >/dev/null
    dbl=$((sz * 2))
    sips -z $dbl $dbl icon_1024.png --out AppIcon.iconset/icon_${sz}x${sz}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset icon_1024.png
echo "AppIcon.icns generated"
