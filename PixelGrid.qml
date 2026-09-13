import QtQuick
import "Sprites.js" as Sprites

// Paints a grid of palette characters as hard squares on a `unit` grid.
// Runs of one colour collapse into a single fillRect, so a wizard frame costs
// roughly 120 rects rather than the 780 a per-pixel loop would issue.
Canvas {
  id: grid

  property var rows: []
  // Real, not int: he scales continuously with distance. Pixel edges are
  // snapped in onPaint so the grid stays hard at any fractional size.
  property real unit: 4
  property bool flip: false
  property bool flipV: false
  property real wave: 0        // per-row horizontal sway, in device pixels
  property real wavePhase: 0

  readonly property int cols: rows.length > 0 ? String(rows[0]).length : 0

  implicitWidth: Math.round(cols * unit)
  implicitHeight: Math.round(rows.length * unit)
  width: implicitWidth
  height: implicitHeight

  onRowsChanged: requestPaint()
  onFlipChanged: requestPaint()
  onFlipVChanged: requestPaint()
  onUnitChanged: requestPaint()
  onWavePhaseChanged: if (wave > 0) requestPaint()

  onPaint: {
    const ctx = getContext("2d")
    ctx.reset()
    if (cols === 0)
      return

    // Each sprite pixel spans from its own rounded edge to the next one's, so
    // neighbours share an edge exactly: no seams, no overlap, and no blur. At
    // a fractional scale some pixels come out a device pixel wider than others,
    // which is exactly how nearest-neighbour scaling has always looked.
    for (let y = 0; y < rows.length; y++) {
      const top = Math.round(y * grid.unit)
      const bottom = Math.round((y + 1) * grid.unit)
      // A reflection reads its source from the bottom up, and each row slides
      // sideways a little -- that lateral shear is what sells it as water
      // rather than a copy of him pasted upside down.
      const row = String(rows[grid.flipV ? (rows.length - 1 - y) : y])
      const shift = grid.wave > 0
        ? Math.round(Math.sin(y * 0.5 + grid.wavePhase) * grid.wave) : 0
      let x = 0
      while (x < cols) {
        const c = row.charAt(x)
        if (c === ".") {
          x++
          continue
        }
        let run = 1
        while (x + run < cols && row.charAt(x + run) === c)
          run++
        // Mirroring a run reflects its far edge, not its near one.
        const dx = grid.flip ? (cols - x - run) : x
        ctx.fillStyle = Sprites.PALETTE[c]
        const left = Math.round(dx * grid.unit) + shift
        const right = Math.round((dx + run) * grid.unit) + shift
        ctx.fillRect(left, top, right - left, bottom - top)
        x += run
      }
    }
  }
}
