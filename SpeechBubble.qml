import QtQuick
import "Sprites.js" as Sprites
import "Font5x7.js" as Font

// A speech bubble drawn on the same pixel grid as the wizard: 1-pixel border,
// notched corners, and a stepped tail underneath. `tailAt` is the tail's
// centre in this item's own coordinates, so the bubble can sit anywhere and
// still point back at his hat.
Canvas {
  id: bubble

  property var lines: []
  property int unit: 4
  property real tailAt: 0
  // Death's speech is set the other way round -- pale letters cut out of the
  // dark -- so you can tell who is talking before you have read a word.
  property bool inverted: false

  readonly property color fillColor: inverted ? Sprites.PALETTE["2"] : Sprites.PALETTE["W"]
  readonly property color inkColor: inverted ? Sprites.PALETTE["1"] : Sprites.PALETTE["K"]

  readonly property int pad: 3
  readonly property int lineGap: 2
  readonly property int tailHeight: 3

  readonly property int textWidth: {
    let w = 0
    for (let i = 0; i < lines.length; i++)
      w = Math.max(w, Font.measure(lines[i]))
    return w
  }
  readonly property int textHeight:
    lines.length * Font.H + Math.max(0, lines.length - 1) * lineGap

  readonly property int boxW: textWidth + 2 * (pad + 1)
  readonly property int boxH: textHeight + 2 * (pad + 1)

  implicitWidth: boxW * unit
  implicitHeight: (boxH + tailHeight) * unit
  width: implicitWidth
  height: implicitHeight

  onLinesChanged: requestPaint()
  onUnitChanged: requestPaint()
  onTailAtChanged: requestPaint()
  onInvertedChanged: requestPaint()

  function px(ctx, x, y, w, h) {
    ctx.fillRect(x * unit, y * unit, w * unit, h * unit)
  }

  onPaint: {
    const ctx = getContext("2d")
    ctx.reset()
    if (lines.length === 0)
      return

    const w = boxW
    const h = boxH

    // Border first, corners left out so the box reads as rounded at 1 pixel.
    ctx.fillStyle = inverted ? Sprites.PALETTE["1"] : inkColor
    px(ctx, 1, 0, w - 2, 1)
    px(ctx, 1, h - 1, w - 2, 1)
    px(ctx, 0, 1, 1, h - 2)
    px(ctx, w - 1, 1, 1, h - 2)

    ctx.fillStyle = fillColor
    px(ctx, 1, 1, w - 2, h - 2)

    // Tail: a 3-step triangle, clamped so it stays under the box.
    const tx = Math.max(3, Math.min(w - 4, Math.round(tailAt / unit)))
    ctx.fillStyle = inkColor
    px(ctx, tx - 2, h, 1, 1)
    px(ctx, tx + 2, h, 1, 1)
    px(ctx, tx - 1, h + 1, 1, 1)
    px(ctx, tx + 1, h + 1, 1, 1)
    px(ctx, tx, h + 2, 1, 1)
    ctx.fillStyle = fillColor
    px(ctx, tx - 1, h, 3, 1)
    px(ctx, tx, h + 1, 1, 1)

    // Text, glyph by glyph, on the same grid.
    ctx.fillStyle = inkColor
    for (let li = 0; li < lines.length; li++) {
      const text = Font.sanitize(lines[li])
      let cx = 1 + pad
      const cy = 1 + pad + li * (Font.H + lineGap)
      for (let i = 0; i < text.length; i++) {
        const glyph = Font.GLYPHS[text.charAt(i)]
        for (let gy = 0; gy < Font.H; gy++) {
          const grow = glyph[gy]
          let gx = 0
          while (gx < Font.W) {
            if (grow.charAt(gx) !== "#") {
              gx++
              continue
            }
            let run = 1
            while (gx + run < Font.W && grow.charAt(gx + run) === "#")
              run++
            px(ctx, cx + gx, cy + gy, run, 1)
            gx += run
          }
        }
        cx += Font.advance(text.charAt(i)) + 1
      }
    }
  }
}
