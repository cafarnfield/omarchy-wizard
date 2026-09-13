import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Sprites.js" as Sprites
import "Brain.js" as Brain

// A summoned desktop familiar who reads the wallpaper he is standing on.
//
//   omarchy-shell shell toggle landis.wizard '{}'
//
// He is a `panel` plugin with keepLoaded off, so nothing of him exists -- no
// window, no timer, no surface -- until he is summoned, and hiding destroys
// the lot again.
//
// scene.py reads the current background and reports which stretches of his
// walking band are water, where the shoreline is, and where clusters of lit
// windows sit. That is heuristic scene reading, not object recognition: it
// knows "a tall cluster of lights at x=3210", never "a castle". Everything he
// says about a place is hedged accordingly.
//
// He lives on the Wayland `bottom` layer: above the wallpaper, below every
// window. The layer surface covers the whole output but masks its input region
// down to his own box, so anywhere that is not him stays click-through.
Item {
  id: root

  // --- host contract -------------------------------------------------------
  property bool opened: false
  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "landis.wizard"
  readonly property string pluginDir: {
    const url = String(Qt.resolvedUrl("."))
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }

  // --- tunables, overridable from the summon payload -----------------------
  property int baseUnit: 4             // device pixels per sprite pixel, up close
  property real walkSpeed: 26          // sprite pixels per second on land
  property real rowSpeed: 18           // sprite pixels per second afloat
  property string screenName: ""       // output to live on; blank = focused
  property bool explore: true          // may he set off on errands
  property string layerName: "bottom"  // bottom = part of the desktop scene

  readonly property real spriteW: Sprites.W * unit
  readonly property real spriteH: Sprites.H * unit

  // Rows of empty grid under the current pose. His feet are the bottom of the
  // drawn content, not the bottom of the grid it happens to be drawn on.
  readonly property real framePad: (Sprites.FRAME_PAD[currentFrame] || 0) * unit
  readonly property real catPad: catShape !== ""
    ? (Sprites.SHAPE_PAD[catShape] || 0) * catUnit
    : (Sprites.CAT_PAD[catFrame] || 0) * catUnit

  // --- live state ----------------------------------------------------------
  property string mood: "idle"
  property real fx: 0                  // unquantised position; the sprite
  property real footY: 0               // where his feet or hull meet the world
  property real vy: 0

  // His size follows his depth, so the sprite's height depends on where he is
  // standing -- which means the feet line has to be what is stored, and the
  // sprite's top derived from it. Storing the top instead would make size and
  // position define each other in a circle.
  readonly property real fy: footY - spriteH
  property int facing: 1               // 1 faces right, -1 faces left
  property bool placed: false
  property bool leaving: false

  property real clock: 0               // seconds since this summon
  property real animClock: 0
  property real moodClock: 0
  property real moodFor: 0
  property real blinkUntil: 0
  property real nextBlink: 2
  property real nextErrand: 14
  property real lastTurn: -99          // when he last changed direction
  property real ripple: 0              // reflection sway phase
  property string waterEvent: ""       // what the lake is doing to him
  property real eventClock: 0
  property real eventFor: 0
  property real eventX: 0
  property real nextWaterEvent: 30
  property string landEvent: ""        // campfire | attention
  property real landClock: 0
  property real landFor: 0
  property real landX: 0
  property real nextLandEvent: 45
  property bool catInBed: false        // she is asleep on him
  property string catShape: ""         // what he has turned her into
  property real nextBrew: 0            // next flourish at the table
  property real sleepFor: 0            // how long he intends to sleep once in
  property real waterY: 0              // the line he is sailing along
  property real waterTargetY: 0        // where on the lake he is heading
  property int blockCount: 0           // consecutive refusals to climb
  property real ignoreSlopeUntil: 0    // escape hatch when boxed in
  property real lastBlock: -99
  property real commitUntil: 0         // hold this heading; do not dither
  property bool shoreRolled: false     // has he decided about this shoreline
  property bool willBoard: false
  property real noBoatUntil: 0         // he has just landed; let him potter
  property real stepFrom: 0            // footing at the start of a transition
  property real stepTo: 0
  property real roamMinX: 0            // how much ground he has covered
  property real roamMaxX: 0
  property real roamSince: 0

  property var sparks: []
  property var bubbleLines: []
  property real bubbleUntil: 0
  property string lastPhrase: ""

  // --- the world he is standing in ----------------------------------------
  property var scene: null
  property string backgroundPath: ""
  property real targetX: -1            // where he is headed, -1 = wandering
  property var errand: null            // the POI he is headed to
  property var visiting: null          // the structure he has stepped into
  property real noGoX: -1              // an errand he could not reach
  property real noGoUntil: 0

  // --- Soot, who follows him about ----------------------------------------
  property bool hasCat: true
  property real catX: 0
  property real catFootY: 0
  property int catFacing: 1
  property string catMood: "sit"
  property real catTurnAt: -99
  property bool catAboard: false       // she came along this time
  property real catStranded: 0         // how long the lake has been between them
  property string catIdle: "sit"       // sit | groom | loaf | stretch
  property real catIdleClock: 0
  property real catIdleFor: 4
  property real catBlinkUntil: 0
  property real catNextBlink: 3
  property bool catTailUp: false
  property bool catWasWalking: false
  property real catDawdleUntil: 0
  property bool catDawdleRolled: false
  property real catNextFlick: 1.5
  property string catTask: ""          // greet | follow | gift | underfoot | perch | crystal
  property real catTaskClock: 0
  property real catTaskFor: 0
  property real catTaskX: 0
  property real nextCatTask: 35
  property bool catGift: false         // she is away fetching something
  property string dropped: ""          // an item she has knocked loose
  property real droppedX: 0
  property real droppedUntil: 0

  // Her size follows her own footing, not his. Sharing his `unit` meant she
  // shrank into the distance while sitting on the bank, just because he had
  // rowed out. She never leaves dry land, and land is always full size.
  // True while she is drawn as part of another sprite rather than her own.
  readonly property bool catOnHim: (catInBed && mood === "sleep" && !afloat)
    || catTask === "perch"

  readonly property real catUnit: baseUnit
  readonly property real catW: Sprites.CW * catUnit
  readonly property real catH: Sprites.CH * catUnit

  // --- Death, who calls in now and then ------------------------------------
  property bool deathHere: false
  property string deathMood: "in"      // in | walk | pet | out
  property real deathX: 0
  property real deathFootY: 0
  property int deathFacing: 1
  property real deathClock: 0
  property real deathFor: 0
  property real nextDeath: 150
  property var deathLines: []

  // --- what he is carrying -------------------------------------------------
  property var inventory: []
  property string holding: ""
  property bool showPack: false

  readonly property real centerX: fx + spriteW / 2
  // Keyed on the ground beneath him rather than his mood: keying it on
  // `afloat` snapped him back to full size the moment he stepped through a
  // portal mid-lake, and popped again when he came back.
  // Measured from an anchor sized by baseUnit, not by the live `unit`.
  // Using centerX here is a binding loop: overWater sets unit, unit sets
  // spriteW, spriteW sets centerX, centerX would set overWater.
  readonly property bool overWater: surfaceAt(fx + Sprites.W * baseUnit / 2) === "water"

  // The lake is a surface in perspective, not a line: he can row out towards
  // the far shore and back. Kept clear of both edges so the hull never sits
  // half on the horizon or half off the bottom of the screen.
  readonly property real waterNear: nearY - Math.max(8, stage.height * 0.04)
  readonly property real waterFar: horizonY + Math.max(10, stage.height * 0.03)
  readonly property bool afloat: mood === "row" || mood === "board" || mood === "beach"
  // While away inside a structure there is nothing on screen to click, so the
  // input region collapses rather than leaving an invisible hitbox behind.
  readonly property bool interactive: opened && !leaving && mood !== "away"

  readonly property var targetScreen: {
    const screens = Quickshell.screens
    for (let i = 0; i < screens.length; i++)
      if (String(screens[i].name) === root.screenName)
        return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  readonly property real floorY: stage.height - spriteH

  // The near edge of the world is the bottom of the screen; the far edge is
  // the waterline, beyond which there is only sky and mountain.
  readonly property real nearY: stage.height - Math.max(6, stage.height * 0.02)
  readonly property real horizonY: (scene && scene.waterline > 0)
    ? Math.min(scene.waterline, stage.height * 0.9) : stage.height * 0.78

  // 1 at the near shore, 0 at the horizon.
  function depthOf(y) {
    return Math.max(0, Math.min(1, (y - horizonY) / Math.max(1, nearY - horizonY)))
  }

  // Size falls off continuously with distance -- derived rather than stored,
  // so it can never drift out of step with where he actually is. Only the
  // water recedes into the picture: the land is the foreground silhouette, so
  // climbing it is going up, not going away, and he keeps his full size there.
  property real unit: overWater
    ? baseUnit * (farScale + (1 - farScale) * depthOf(footY))
    : baseUnit

  // The binding above is already continuous, but his footing is not: stepping
  // into the boat, being dropped, or landing all move him a long way in one
  // frame, and the size would snap with them. Easing the result makes an
  // instant change in size impossible whatever causes it.
  Behavior on unit {
    NumberAnimation {
      duration: 260
      easing.type: Easing.OutQuad
    }
  }

  readonly property real farScale: 0.5

  readonly property real maxX: stage.width - spriteW

  // --- host entry points ---------------------------------------------------

  function open(payloadJson) {
    let payload = {}
    try {
      payload = JSON.parse(payloadJson || "{}") || {}
    } catch (e) {
      payload = {}
    }

    if (payload.scale !== undefined)
      baseUnit = Math.max(2, Math.min(12, Math.round(Number(payload.scale))))
    if (payload.speed !== undefined)
      walkSpeed = Math.max(2, Math.min(200, Number(payload.speed)))
    if (payload.explore !== undefined)
      explore = payload.explore !== false
    if (payload.cat !== undefined)
      hasCat = payload.cat !== false
    if (payload.layer !== undefined)
      layerName = String(payload.layer)

    screenName = String(payload.screen
      || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") || "")

    opened = true
    leaving = false
    enterIdle(Brain.between(0.8, 1.6))
    say(Brain.pick(Brain.GREETINGS, ""), 2.6)
    rescan("")
  }

  function close() {
    opened = false
  }

  // Reachable as: omarchy-shell shell call landis.wizard say "SOMETHING"
  function say(text, seconds) {
    const body = String(text || "").trim()
    if (body === "") {
      bubbleLines = []
      bubbleUntil = 0
      return "ok"
    }
    bubbleLines = Brain.wrap(body, 16)
    bubbleUntil = clock + (seconds > 0 ? seconds : 3.4)
    return "ok"
  }

  // Re-read the wallpaper. Also called when the background symlink moves.
  function rescan(arg) {
    if (sceneProc.running || stage.width <= 0)
      return "busy"
    sceneProc.command = ["python3", root.pluginDir + "scene.py",
                         String(Math.round(stage.width)),
                         String(Math.round(stage.height)),
                         String(root.spriteH)]
    sceneProc.running = true
    return "ok"
  }

  function applyScene(text) {
    try {
      const parsed = JSON.parse(String(text || ""))
      scene = (parsed && parsed.surface) ? parsed : null
    } catch (e) {
      scene = null
    }
    if (scene && placed && mood !== "held" && mood !== "fall" && mood !== "away") {
      footY = terrainAt(centerX)
    }
    // If the new wallpaper put water under his feet, he needs the boat.
    if (scene && placed && !afloat && mood !== "away" && surfaceAt(centerX) === "water")
      beginBoard()
  }

  // --- reading the scene ---------------------------------------------------

  function surfaceAt(x) {
    if (!scene || !scene.surface)
      return "land"
    for (let i = 0; i < scene.surface.length; i++) {
      const run = scene.surface[i]
      if (x >= run.x0 && x < run.x1)
        return String(run.kind)
    }
    return "land"
  }

  // The wallpaper's ground line at x -- where his feet go, not his sprite top.
  function terrainAt(x) {
    if (!scene || !scene.ground || scene.ground.length < 2)
      return stage.height
    const profile = scene.ground
    const stepPx = scene.groundStep > 0 ? scene.groundStep
                                        : stage.width / (profile.length - 1)
    const t = Math.max(0, Math.min(profile.length - 1, x / stepPx))
    const i = Math.floor(t)
    const j = Math.min(profile.length - 1, i + 1)
    const blend = t - i
    const surface = profile[i] * (1 - blend) + profile[j] * blend
    return Math.max(spriteH, Math.min(stage.height, surface))
  }

  // Is there water between these two points? If so they are on different
  // shores, and she has no way across on her own.
  function waterBetween(a, b) {
    if (!scene || !scene.surface)
      return false
    const lo = Math.min(a, b)
    const hi = Math.max(a, b)
    for (let i = 0; i < scene.surface.length; i++) {
      const run = scene.surface[i]
      if (String(run.kind) !== "water")
        continue
      if (run.x1 > lo && run.x0 < hi)
        return true
    }
    return false
  }

  // Nearest x at which she would be standing on solid ground. She has no
  // business on the lake: terrainAt() happily returns the water surface for a
  // water column, so without this she is drawn standing on the open water
  // whenever following him to the shoreline puts her a step too far.
  function nearestLandCenter(x) {
    if (!scene || !scene.surface || surfaceAt(x) === "land")
      return x
    let best = x
    let bestDist = Infinity
    for (let i = 0; i < scene.surface.length; i++) {
      const run = scene.surface[i]
      if (String(run.kind) !== "land")
        continue
      const inset = catW * 0.5
      if (run.x1 - run.x0 < catW)
        continue
      const edge = Math.max(run.x0 + inset, Math.min(run.x1 - inset, x))
      const dist = Math.abs(edge - x)
      if (dist < bestDist) {
        bestDist = dist
        best = edge
      }
    }
    return best
  }

  // Keeps her feet on land wherever she has ended up -- following him to the
  // water's edge, stepping out of the boat, or a wallpaper that moved the
  // shoreline out from under her.
  function settleCat() {
    const centre = catX + catW / 2
    const land = nearestLandCenter(centre)
    if (land !== centre)
      catX = land - catW / 2
    catX = Math.max(0, Math.min(stage.width - catW, catX))
    catFootY = terrainAt(catX + catW / 2)
  }

  function poisOfKind(kind) {
    if (!scene || !scene.pois)
      return []
    const out = []
    for (let i = 0; i < scene.pois.length; i++)
      if (String(scene.pois[i].kind) === kind)
        out.push(scene.pois[i])
    return out
  }

  // Every direction change funnels through here. Without a floor on how often
  // he may turn, any condition that reverses him each tick -- a notch with
  // steep ground both sides, a pointer sitting on his centre line -- turns him
  // into a 30Hz blur pinned to one spot.
  function turnAround(newFacing) {
    if (newFacing === facing)
      return true
    if (clock - lastTurn < 0.45)
      return false
    lastTurn = clock
    facing = newFacing
    return true
  }

  // --- moods ---------------------------------------------------------------

  function enterWalk(seconds) {
    mood = overWater ? "row" : "walk"
    moodClock = 0
    animClock = 0
    moodFor = seconds > 0 ? seconds : Brain.between(2.5, 7)
    if (targetX < 0 && clock > commitUntil && Math.random() < 0.35)
      turnAround(-facing)
  }

  function enterIdle(seconds) {
    // He cannot stand about in open water; idling afloat is just drifting.
    mood = overWater ? "row" : "idle"
    moodClock = 0
    animClock = 0
    moodFor = seconds > 0 ? seconds : Brain.between(1.4, 4.5)
  }

  function enterSleep() {
    sleepFor = Brain.between(10, 22)
    moodClock = 0
    animClock = 0

    // Dozing off in the boat is just dozing off. Ashore he goes to the
    // trouble of unrolling the thing first.
    if (afloat || overWater) {
      mood = "sleep"
      moodFor = sleepFor
      say("Z Z Z", Math.min(moodFor, 8))
      return
    }

    mood = "makebed"
    moodFor = 2.6
  }

  function poke() {
    if (leaving || mood === "away")
      return
    if (afloat) {
      lastPhrase = Brain.pick(Brain.WATER, lastPhrase)
      say(lastPhrase, 3.0)
      splash(8)
      return
    }
    mood = "cast"
    moodClock = 0
    animClock = 0
    moodFor = 1.15
    lastPhrase = Brain.pick(Brain.PHRASES, lastPhrase)
    say(lastPhrase, 3.6)
    spawn(14, orbX, orbY, [Sprites.PALETTE["C"], Sprites.PALETTE["A"], Sprites.PALETTE["Y"]], 150, 0.75)
  }

  function pickUp() {
    mood = "held"
    moodClock = 0
    animClock = 0
    vy = 0
    abandonErrand()
    if (Math.random() < 0.5)
      say(Brain.pick(Brain.GRUMBLES, ""), 1.8)
  }

  function drop() {
    mood = "fall"
    moodClock = 0
    vy = 0
  }

  function land() {
    if (vy > 260)
      spawn(9, fx + spriteW / 2, fy + spriteH - unit,
            [Sprites.PALETTE["G"], Sprites.PALETTE["D"]], 90, 0.45)
    vy = 0
    // Dropped in the lake? Then he is in the boat, not standing on water.
    if (surfaceAt(centerX) === "water")
      beginBoard()
    else
      enterIdle(Brain.between(1.0, 2.0))
  }

  function dismiss() {
    if (leaving)
      return
    leaving = true
    say(Brain.pick(Brain.FAREWELLS, ""), 1.0)
    spawn(26, fx + spriteW / 2, fy + spriteH / 2,
          [Sprites.PALETTE["C"], Sprites.PALETTE["A"], Sprites.PALETTE["P"]], 190, 0.7)
    leaveTimer.restart()
  }

  // --- water ---------------------------------------------------------------

  function splash(count) {
    spawn(count, centerX, fy + spriteH - unit * 2,
          [Sprites.PALETTE["A"], Sprites.PALETTE["C"], Sprites.PALETTE["G"]], 80, 0.5)
  }

  function beginBoard() {
    // Stepping off the bank into the boat is a drop of a hundred pixels or
    // so. Snapping it looked like a glitch, and leaving the old footing in
    // place had him drifting out to the waterline over the following
    // seconds -- so it is eased across the boarding animation instead.
    stepFrom = footY
    stepTo = Math.max(waterFar, Math.min(waterNear, waterNear))
    // Sometimes she comes. She has to be nearby to bother, and even then it
    // is roughly one crossing in two -- a cat that always got in the boat
    // would not be a cat.
    catAboard = hasCat && Math.abs(catX - fx) < spriteW * 2.5 && Math.random() < 0.45
    mood = "board"
    waterY = stepTo
    waterTargetY = waterY
    moodClock = 0
    animClock = 0
    moodFor = 0.7
    splash(10)
    if (Math.random() < 0.6)
      say(Brain.pick(Brain.WATER, ""), 2.4)
  }

  function beginBeach() {
    noBoatUntil = clock + Brain.between(40, 90)
    // Same in reverse: without this he arrives at the bank still standing at
    // the waterline, and the slope limit then lets him climb ashore only a
    // few pixels a tick, which is the crawl you can see.
    stepFrom = footY
    stepTo = terrainAt(centerX)
    // She steps out where he does.
    if (catAboard) {
      catAboard = false
      // Out where he steps out, then pulled onto dry ground.
      catX = fx + spriteW / 2 - catW / 2
    }
    mood = "beach"
    moodClock = 0
    animClock = 0
    moodFor = 0.6
    splash(7)
  }

  // --- things that happen on the lake --------------------------------------

  // True while an event has hold of him and he is not rowing anywhere.
  readonly property bool eventHolds: waterEvent === "fishing" || waterEvent === "overboard"

  function startWaterEvent() {
    // Only out on the water, and never while he is mid-portal or being held.
    if (!afloat || leaving || mood === "away" || mood === "vanish")
      return "no"
    nextWaterEvent = clock + Brain.between(40, 95)
    eventClock = 0
    const roll = Math.random()
    const side = facing > 0 ? -1 : 1

    if (roll < 0.20) {
      waterEvent = "tentacle"
      eventFor = 5.0
      eventX = centerX - side * spriteW * 0.95
      say(Brain.pick(Brain.TENTACLE, ""), 3.4)
      splash(8)
    } else if (roll < 0.44) {
      waterEvent = "fishing"
      eventFor = Brain.between(8, 13)
      say(Brain.pick(Brain.FISHING, ""), 3.0)
    } else if (roll < 0.58) {
      waterEvent = "overboard"
      eventFor = 6.5
      eventX = centerX + side * spriteW * 0.5
      say(Brain.pick(Brain.OVERBOARD, ""), 3.6)
      splash(22)
    } else if (roll < 0.80) {
      waterEvent = "fishjump"
      eventFor = 1.7
      eventX = centerX + (Math.random() < 0.5 ? -1 : 1) * spriteW * Brain.between(0.7, 1.6)
      if (Math.random() < 0.5)
        say(Brain.pick(Brain.LAKE_ODD, ""), 2.4)
    } else {
      waterEvent = "shadow"
      eventFor = 4.5
      eventX = centerX - side * spriteW * 1.8
      if (Math.random() < 0.6)
        say(Brain.pick(Brain.LAKE_ODD, ""), 2.6)
    }
    return waterEvent
  }

  function endWaterEvent() {
    if (waterEvent === "fishing") {
      const lucky = Math.random() < 0.5 && inventory.indexOf("fish") === -1
      say(lucky ? Brain.FISHING_LUCK[0] : Brain.pick(Brain.FISHING_LUCK.slice(1), ""), 3.0)
      if (lucky)
        acquire("fish")
    } else if (waterEvent === "overboard") {
      splash(14)
      // He can lose something over the side. Never the staff.
      if (inventory.length > 0 && Math.random() < 0.35) {
        const drop = inventory[Math.floor(Math.random() * inventory.length)]
        const kept = []
        for (let i = 0; i < inventory.length; i++)
          if (inventory[i] !== drop)
            kept.push(inventory[i])
        inventory = kept
        say("MY " + drop.toUpperCase() + "!", 2.8)
      }
    }
    waterEvent = ""
    eventClock = 0
  }

  function stepWaterEvent(dt) {
    if (waterEvent === "") {
      if (mood === "row" && clock > nextWaterEvent)
        startWaterEvent()
      return
    }
    eventClock += dt
    if (waterEvent === "tentacle") {
      if (eventClock < 0.4)
        splash(2)
      // Soot, watching from the bank, does not care for it at all. Only on
      // the way up: re-arming this every tick reset her timer every tick, and
      // she stayed startled for the rest of her natural life.
      if (eventClock < 0.5 && catIdle !== "arch" && hasCat && !catOnHim
          && catTask === "" && Math.abs(catX - eventX) < spriteW * 4) {
        catIdle = "arch"
        catIdleClock = 0
        catIdleFor = Brain.between(2.5, 4.5)
        catTurn(eventX > catX ? 1 : -1)
      }
    }
    if (eventClock >= eventFor)
      endWaterEvent()
  }

  // Crossing the shoreline ends whatever the place he just left was doing
  // to him. One handler: QML allows only a single onAfloatChanged per object,
  // and a second one silently wins over the first.
  onAfloatChanged: {
    if (!afloat && waterEvent !== "") {
      waterEvent = ""
      eventClock = 0
    }
    if (afloat && landEvent !== "") {
      landEvent = ""
      landClock = 0
    }
  }

  readonly property string tentacleFrame: {
    const list = Sprites.TENTACLE
    const t = Math.max(0, Math.min(0.999, eventClock / Math.max(0.1, eventFor)))
    return list[Math.floor(t * list.length)]
  }

  // --- things that happen ashore -------------------------------------------

  function startLandEvent() {
    if (afloat || overWater || leaving || mood === "away" || mood === "vanish"
        || landEvent !== "")
      return "no"
    nextLandEvent = clock + Brain.between(55, 130)
    landClock = 0

    const pick = Math.random()
    if (pick < 0.38) {
      landEvent = "study"
      landFor = Brain.between(26, 46)
      landX = centerX + (facing > 0 ? spriteW * 0.85 : -spriteW * 0.85)
      nextBrew = landClock + Brain.between(3, 6)
      say(Brain.pick(Brain.STUDY, ""), 3.4)
      enterIdle(landFor)
      turnAround(landX > centerX ? 1 : -1)
    } else if (pick < 0.72) {
      landEvent = "campfire"
      landFor = Brain.between(16, 26)
      landX = centerX + (facing > 0 ? spriteW * 0.75 : -spriteW * 0.75)
      say(Brain.pick(Brain.FIRESIDE, ""), 3.2)
      enterIdle(landFor)
      turnAround(landX > centerX ? 1 : -1)
      // She claims the warm spot, obviously.
      if (hasCat && !catOnHim && catTask === "")
        startCatTask("follow", landFor * 0.9,
                     landX + (landX > centerX ? spriteW * 0.45 : -spriteW * 0.45) - catW / 2)
    } else if (hasCat) {
      landEvent = "attention"
      landFor = Brain.between(5, 8)
      say(Brain.pick(Brain.CAT_WANTS, ""), 3.2)
      enterIdle(landFor)
    } else {
      return "no"
    }
    return landEvent
  }

  function stepLandEvent(dt) {
    if (landEvent === "") {
      if (!afloat && !overWater && mood === "idle" && clock > nextLandEvent)
        startLandEvent()
      return
    }
    landClock += dt

    if (landEvent === "study") {
      // Keep him at the bench rather than wandering off mid-experiment.
      if (mood === "walk")
        enterIdle(Math.max(1.0, landFor - landClock))

      if (landClock > nextBrew) {
        nextBrew = landClock + Brain.between(4, 8)
        const what = Math.random()
        if (what < 0.34) {
          // Something in the glassware objects to being mixed.
          spawn(9, landX - spriteW * 0.28, terrainAt(landX) - baseUnit * 10,
                [Sprites.PALETTE["V"] || Sprites.PALETTE["C"], Sprites.PALETTE["C"],
                 Sprites.PALETTE["A"]], 70, 0.9)
          if (Math.random() < 0.3) {
            say(Brain.pick(Brain.BREW_LUCK, ""), 3.2)
            if (Math.random() < 0.5)
              acquire(["crystal", "book", "mushroom"][Math.floor(Math.random() * 3)])
          }
        } else if (what < 0.62 && hasCat && catShape === "" && !catOnHim
                   && Math.abs(catX - fx) < spriteW * 2.2) {
          transformCat()
        } else {
          say(Brain.pick(Brain.STUDY, ""), 3.2)
          if (Math.random() < 0.4) {
            mood = "cast"
            moodClock = 0
            animClock = 0
            moodFor = 1.0
            spawn(8, orbX, orbY, [Sprites.PALETTE["C"], Sprites.PALETTE["Y"]], 90, 0.7)
          }
        }
      }
    }

    if (landEvent === "campfire") {
      // Embers drifting up off it.
      if (Math.random() < dt * 5)
        spawn(1, landX, footY - unit * 4,
              [Sprites.PALETTE["Y"], Sprites.PALETTE["R"]], 40, 1.0)
      // He stays by the fire rather than wandering off mid-warm.
      if (mood === "walk")
        enterIdle(Math.max(1.0, landFor - landClock))
    }

    if (landClock >= landFor) {
      if (landEvent === "campfire")
        spawn(6, landX, footY - unit * 3, [Sprites.PALETTE["G"]], 45, 0.8)
      if (landEvent === "study")
        revertCat()
      landEvent = ""
      landClock = 0
    }
  }

  // --- turning the cat into things ----------------------------------------

  function transformCat() {
    catShape = Sprites.SHAPE_NAMES[Math.floor(Math.random() * Sprites.SHAPE_NAMES.length)]
    catTask = ""
    catMood = "sit"
    catIdle = "sit"
    say(Brain.pick(Brain.TRANSFORM, ""), 3.2)
    spawn(16, catX + catW / 2, catFootY - catH / 2,
          [Sprites.PALETTE["C"], Sprites.PALETTE["A"], Sprites.PALETTE["L"]], 110, 0.8)
  }

  function revertCat() {
    if (catShape === "")
      return
    spawn(16, catX + catW / 2, catFootY - catH / 2,
          [Sprites.PALETTE["C"], Sprites.PALETTE["A"], Sprites.PALETTE["Y"]], 110, 0.8)
    catShape = ""
    // She takes a dim view of the whole business.
    catIdle = "arch"
    catIdleClock = 0
    catIdleFor = Brain.between(3, 5)
    say(Brain.pick(Brain.REVERT, ""), 3.0)
  }

  readonly property string tableFrame:
    Sprites.TABLE_NAMES[Math.floor(animClock / 0.22) % Sprites.TABLE_NAMES.length]

  readonly property string fireFrame:
    Sprites.FIRE_NAMES[Math.floor(animClock / 0.13) % Sprites.FIRE_NAMES.length]

  // Touching one of the crystals on the bank.
  function touchCrystal() {
    mood = "cast"
    moodClock = 0
    animClock = 0
    moodFor = 1.4
    say(Brain.pick(Brain.CRYSTAL, ""), 3.4)
    spawn(18, orbX, orbY,
          [Sprites.PALETTE["C"], Sprites.PALETTE["A"], Sprites.PALETTE["L"]], 140, 0.9)
    if (Math.random() < 0.4)
      acquire("crystal")
  }

  // --- errands -------------------------------------------------------------

  // Pick somewhere on the wallpaper worth walking to. Structures are worth a
  // visit; lights are worth a look.
  function chooseErrand() {
    if (!explore || !scene)
      return
    const structures = poisOfKind("structure")
    const lights = poisOfKind("light")
    const crystals = poisOfKind("crystal")
    const pool = []
    for (let c = 0; c < crystals.length; c++)
      pool.push(crystals[c])
    for (let i = 0; i < structures.length; i++)
      pool.push(structures[i])
    for (let j = 0; j < lights.length && j < 4; j++)
      pool.push(lights[j])
    if (pool.length === 0)
      return

    // Drop anywhere he recently failed to reach, or he will set off for the
    // same clifftop over and over and pace at the bottom of it.
    const reachable = []
    for (let k = 0; k < pool.length; k++) {
      if (clock < noGoUntil && Math.abs(Number(pool[k].x) - noGoX) < spriteW * 2)
        continue
      // While he is having his spell ashore, only errands on this side of
      // the water count. Otherwise every structure across the lake overrides
      // the cooldown and he is straight back in the boat.
      if (clock < noBoatUntil && waterBetween(centerX, Number(pool[k].x)))
        continue
      reachable.push(pool[k])
    }
    if (reachable.length === 0)
      return

    const choice = reachable[Math.floor(Math.random() * reachable.length)]
    const x = Math.max(0, Math.min(maxX, Number(choice.x) - spriteW / 2))
    // Already standing there; nothing to set off for.
    if (Math.abs(x - fx) < spriteW)
      return

    errand = choice
    targetX = x
    // Something high up the picture is far away, so he rows out towards the
    // far shore to reach it rather than staying on the near bank.
    waterTargetY = Math.max(waterFar, Math.min(waterNear, Number(choice.y)))
    if (String(choice.kind) === "structure")
      say(Brain.sightFor(String(choice.shape || "keep")), 3.2)
    enterWalk(0)
  }

  // Errands used to be picked only from the idle mood, which he never enters
  // while afloat -- so on a wallpaper that is mostly lake he almost never set
  // off anywhere. Both the idle and rowing branches ask here now.
  function maybeErrand() {
    // Nobody wanders off on an errand while they have a visitor.
    if (!explore || !scene || targetX >= 0 || clock < nextErrand || deathHere)
      return false
    nextErrand = clock + Brain.between(25, 70)
    chooseErrand()
    return targetX >= 0
  }

  // Point him at the nearer bank and let the usual beaching logic finish it.
  function headAshore() {
    if (!scene || !scene.surface)
      return
    let best = -1
    let bestDist = Infinity
    for (let i = 0; i < scene.surface.length; i++) {
      const run = scene.surface[i]
      if (String(run.kind) !== "land")
        continue
      const edge = Math.max(run.x0, Math.min(run.x1, centerX))
      const dist = Math.abs(edge - centerX)
      if (dist < bestDist) {
        bestDist = dist
        best = edge
      }
    }
    if (best < 0)
      return
    // A destination, not just a heading. Merely pointing him at the bank got
    // undone by the next random course change, and he never actually landed.
    const inland = best + (best > centerX ? spriteW : -spriteW)
    targetX = Math.max(0, Math.min(maxX, inland - spriteW / 2))
    commitUntil = clock + 12
  }

  function abandonErrand() {
    errand = null
    targetX = -1
  }

  function arriveAtErrand() {
    const goal = errand
    abandonErrand()
    if (!goal) {
      enterIdle(0)
      return
    }
    if (String(goal.kind) === "structure") {
      visiting = goal
      beginVisit()
    }
    else
      admire()
  }

  function admire() {
    mood = "cast"
    moodClock = 0
    animClock = 0
    moodFor = 1.1
    say(Brain.pick(Brain.LAMPS, ""), 3.0)
    spawn(10, orbX, orbY, [Sprites.PALETTE["Y"], Sprites.PALETTE["A"]], 110, 0.7)
    if (Math.random() < 0.45)
      acquire("crystal")
  }

  // He does not climb into the middle distance -- he is a wizard, so he steps
  // out of the world and back into it. A sprite scrambling up an invisible
  // hillside would look far worse than a column of sparks.
  function beginVisit() {
    mood = "vanish"
    moodClock = 0
    animClock = 0
    moodFor = 1.2
    spawn(30, centerX, fy + spriteH / 2,
          [Sprites.PALETTE["C"], Sprites.PALETTE["A"], Sprites.PALETTE["P"]], 130, 1.0)
  }

  function beginAway() {
    mood = "away"
    moodClock = 0
    moodFor = Brain.between(14, 34)
    bubbleLines = []
    bubbleUntil = 0
  }

  function returnHome() {
    mood = "arrive"
    moodClock = 0
    animClock = 0
    moodFor = 1.0
    spawn(24, centerX, fy + spriteH / 2,
          [Sprites.PALETTE["C"], Sprites.PALETTE["A"], Sprites.PALETTE["Y"]], 130, 0.9)
    say(Brain.pick(Brain.RETURNS, ""), 3.4)
    if (Math.random() < 0.7)
      acquire(["key", "book", "crystal", "lantern"][Math.floor(Math.random() * 4)])
  }

  // --- items ---------------------------------------------------------------

  function acquire(name) {
    if (inventory.indexOf(name) !== -1)
      return
    const next = inventory.slice()
    next.push(name)
    inventory = next
    holding = name
    holdTimer.restart()
    say(Brain.FINDS[name] || "A FIND.", 3.0)
  }

  function useItem(name) {
    if (inventory.indexOf(name) === -1)
      return "unknown"
    holding = name
    holdTimer.restart()
    say(Brain.USES[name] || "HMM.", 3.0)

    if (name === "lantern")
      spawn(8, orbX, orbY, [Sprites.PALETTE["Y"]], 70, 0.8)
    else if (name === "crystal")
      spawn(10, orbX, orbY, [Sprites.PALETTE["C"], Sprites.PALETTE["A"]], 90, 0.7)

    // Perishables get eaten.
    if (name === "fish" || name === "mushroom") {
      const next = []
      for (let i = 0; i < inventory.length; i++)
        if (inventory[i] !== name)
          next.push(inventory[i])
      inventory = next
    }
    return "ok"
  }

  // Reachable as: omarchy-shell shell call landis.wizard summonDeath ""
  function summonDeath(arg) {
    return callDeath() ? "ok" : "busy"
  }

  // Reachable as: omarchy-shell shell call landis.wizard pack ""
  function pack(arg) {
    return inventory.join(",")
  }

  // What he is doing and what he believes is under him, as JSON. Exists so
  // his behaviour can be checked without a screenshot:
  //   omarchy-shell shell call landis.wizard report ""
  // Named `report` rather than `state` because Item already has a `state`
  // property, and a function of that name never registers.
  function report(arg) {
    const structures = poisOfKind("structure")
    const lights = poisOfKind("light")
    return JSON.stringify({
      mood: mood,
      x: Math.round(fx),
      centerX: Math.round(centerX),
      facing: facing,
      afloat: afloat,
      surface: surfaceAt(centerX),
      y: Math.round(fy),
      footing: Math.round(terrainAt(centerX)),
      footY: Math.round(footY),
      unit: Math.round(unit * 100) / 100,
      depth: Math.round(depthOf(footY) * 100) / 100,
      targetX: Math.round(targetX),
      errand: errand ? String(errand.kind) + ":" + String(errand.shape || "") : "",
      visiting: visiting ? String(visiting.shape || "") + "@" + String(visiting.x) : "",
      portalOpen: Math.round(portalOpen * 100) / 100,
      noGoX: Math.round(noGoX),
      roam: Math.round(roamMaxX - roamMinX),
      event: waterEvent,
      land: landEvent,
      overWater: overWater,
      catInBed: catInBed,
      catGap: Math.round(Math.abs(catX - fx)),
      stranded: Math.round(catStranded),
      frame: currentFrame,
      cat: catMood,
      catIdle: catIdle,
      catTask: catTask,
      catShape: catShape,
      catIdleClock: Math.round(catIdleClock*10)/10,
      catIdleFor: Math.round(catIdleFor*10)/10,
      dropped: dropped,
      catFrame: catFrame,
      catX: Math.round(catX),
      catFacing: catFacing,
      catAboard: catAboard,
      catSurface: surfaceAt(catX + catW / 2),
      catUnit: catUnit,
      death: deathHere ? deathMood : "",
      deathX: Math.round(deathX),
      inventory: inventory,
      holding: holding,
      sceneLoaded: scene !== null,
      water: scene ? scene.waterFraction : null,
      structures: structures.length,
      lights: lights.length,
      background: backgroundPath.split("/").pop()
    })
  }

  // --- Soot ----------------------------------------------------------------

  readonly property string catFrame: {
    if (catMood === "walk")
      return Sprites.CAT_WALK[Math.floor(animClock / 0.16) % Sprites.CAT_WALK.length]
    if (catMood === "curl")
      return "cat_curl"
    switch (catIdle) {
    case "loaf":
      return "cat_curl"
    case "stretch":
      return "cat_stretch"
    case "knead":
      return Sprites.CAT_KNEAD[Math.floor(catIdleClock / 0.3) % Sprites.CAT_KNEAD.length]
    case "rub":
      return Math.floor(catIdleClock / 0.45) % 2 ? "cat_rub" : "cat_sit2"
    case "paw":
      return Math.floor(catIdleClock / 0.4) % 2 ? "cat_paw" : "cat_sit"
    case "arch":
      return "cat_arch"
    case "pounce": {
      const seq = Sprites.CAT_POUNCE
      const t = Math.min(0.999, catIdleClock / Math.max(0.1, catIdleFor))
      return seq[Math.floor(t * seq.length)]
    }
    case "stare":
      // Deliberately still. A cat staring at nothing for an uncomfortably
      // long time is the joke; a flicking tail would ruin it.
      return clock < catBlinkUntil ? "cat_blink" : "cat_sit"
    case "groom":
      return Sprites.CAT_GROOM[Math.floor(catIdleClock / 0.34) % Sprites.CAT_GROOM.length]
    default:
      if (clock < catBlinkUntil)
        return "cat_blink"
      return catTailUp ? "cat_sit2" : "cat_sit"
    }
  }

  // What she does with herself while he is busy. A cat sitting perfectly
  // still is a cat that looks stuffed; the tail is doing most of the work
  // here, and it costs two frames.
  function pickCatIdle() {
    catIdleClock = 0
    if (catIdle === "loaf") {
      // Always a stretch on the way out of a nap.
      catIdle = "stretch"
      catIdleFor = 1.3
      return
    }
    if (catIdle === "stretch") {
      catIdle = "sit"
      catIdleFor = Brain.between(3, 6)
      return
    }
    // Weighted by time, not by roll: loafing is a single still frame, so a
    // long nap undoes the point of animating her at all. Sitting has the
    // flicking tail, grooming has two frames -- keep her in those.
    if (catIdle === "knead") {
      catIdle = "loaf"
      catIdleFor = Brain.between(5, 11)
      return
    }

    const roll = Math.random()
    if (roll < 0.30) {
      catIdle = "sit"
      catIdleFor = Brain.between(3, 7)
    } else if (roll < 0.50) {
      catIdle = "groom"
      catIdleFor = Brain.between(2.5, 5.5)
    } else if (roll < 0.62) {
      catIdle = "pounce"
      catIdleFor = 2.4
    } else if (roll < 0.72) {
      catIdle = "stare"
      catIdleFor = Brain.between(5, 14)
    } else if (roll < 0.80 && nearWater(catX + catW / 2)) {
      catIdle = "paw"
      catIdleFor = Brain.between(3, 6)
    } else if (roll < 0.90 && !afloat && Math.abs(catX - fx) < spriteW * 1.3) {
      // Winding round his legs, which only works if he is standing there.
      catIdle = "rub"
      catIdleFor = Brain.between(2.5, 5)
    } else {
      // Cats knead before they settle.
      catIdle = "knead"
      catIdleFor = Brain.between(1.2, 2.2)
    }
  }

  function stepCatIdle(dt) {
    if (catMood === "walk") {
      // Reset once when she sets off, not on every tick of walking. Resetting
      // per tick meant that while she was following him about -- which is
      // most of the time ashore -- her activity timer never reached its end
      // and she could only ever sit.
      if (!catWasWalking) {
        catIdle = "sit"
        catIdleClock = 0
        catIdleFor = Brain.between(2, 5)
        catWasWalking = true
      }
      return
    }
    catWasWalking = false
    catIdleClock += dt
    if (catIdleClock >= catIdleFor)
      pickCatIdle()

    if (catIdle === "sit") {
      // The tail is the constant background motion, so it has to be doing
      // something a decent fraction of the time. At one flick every few
      // seconds she still read as a stuffed cat between them.
      if (clock > catNextFlick) {
        catTailUp = !catTailUp
        catNextFlick = clock + (catTailUp ? Brain.between(0.5, 1.3)
                                          : Brain.between(0.6, 1.9))
      }
      if (clock > catNextBlink) {
        catBlinkUntil = clock + 0.22
        catNextBlink = clock + Brain.between(2.0, 5.5)
      }
    }
  }

  function stepCat(dt) {
    if (!hasCat)
      return

    if (catShape !== "") {
      // Teapots do not follow people about.
      catMood = "sit"
      settleCat()
      return
    }

    maybeCatTask()
    if (catTask !== "") {
      stepCatTask(dt)
      return
    }

    // She will not get in the boat. No cat would. While he is out on the
    // water, or off through a doorway, she waits where she last stood.
    if (catOnHim) {
      // Tucked up on his chest; her own position just tracks him for when
      // she gets off again.
      catX = fx + spriteW * 0.35
      catFootY = footY
      catMood = "curl"
      return
    }

    // She will not cross the lake, so if he rows off without her she is
    // marooned on the wrong bank for good. Rather than have her sit there
    // forever, she does what cats do: turns up, having apparently known
    // where he was the whole time.
    if (waterBetween(catX + catW / 2, centerX) && !catAboard) {
      catStranded += dt
      if (catStranded > 22 && !afloat && mood !== "away" && mood !== "vanish") {
        catStranded = 0
        spawn(6, catX + catW / 2, catFootY - catH / 2,
              [Sprites.PALETTE["G"], Sprites.PALETTE["D"]], 60, 0.5)
        catX = nearestLandCenter(fx + spriteW / 2 - facing * spriteW * 1.1) - catW / 2
        settleCat()
        catMood = "sit"
        spawn(8, catX + catW / 2, catFootY - catH / 2,
              [Sprites.PALETTE["G"], Sprites.PALETTE["x"] || Sprites.PALETTE["D"]], 70, 0.6)
        if (Math.random() < 0.65)
          say(Brain.pick(Brain.CAT_APPEARS, ""), 3.0)
        return
      }
    } else {
      catStranded = 0
    }

    if (afloat || mood === "away" || mood === "vanish") {
      // Aboard she is part of the boat sprite, so her own position only has
      // to keep up with his for the moment she steps back out.
      if (catAboard) {
        catX = fx
        catFootY = footY
        catMood = "sit"
        return
      }
      catMood = "sit"
      // Waiting on the bank, she watches whichever way he went.
      catTurn(centerX > catX ? 1 : -1)
      settleCat()
      stepCatIdle(dt)
      return
    }

    // She closes the distance to him rather than aiming for a spot behind
    // him. Targeting a side meant her destination jumped clean across him
    // every time he turned around, and she sprinted back and forth after it.
    const near = spriteW * 0.6
    const far = spriteW * 1.15
    const dist = (fx + spriteW / 2) - (catX + catW / 2)
    const away = Math.abs(dist)

    // A band between the two distances, so she is not deciding afresh every
    // frame whether she has arrived.
    if (catMood === "walk") {
      if (away <= near)
        catMood = (mood === "sleep") ? "curl" : "sit"
    } else if (away >= far) {
      // She does not necessarily come when he sets off. Rolled once per
      // separation, not per tick, or she would never follow him at all.
      if (!catDawdleRolled) {
        catDawdleRolled = true
        if (Math.random() < 0.35)
          catDawdleUntil = clock + Brain.between(1.5, 4.0)
      }
      if (clock >= catDawdleUntil)
        catMood = "walk"
    } else {
      catDawdleRolled = false
      catMood = (mood === "sleep") ? "curl" : "sit"
    }

    if (catMood === "walk") {
      const dir = dist > 0 ? 1 : -1
      const speed = walkSpeed * catUnit * 1.25
      // Never step past the stopping band, or she overshoots and comes back.
      const stride = Math.min(speed * dt, Math.max(0, away - near * 0.85))
      const next = catX + dir * stride
      // She stops at the water's edge rather than padding out onto the lake
      // after him.
      if (surfaceAt(next + catW / 2) === "water") {
        catMood = "sit"
      } else {
        catX = next
        catTurn(dir)
      }
    } else if (deathHere && deathMood === "pet") {
      catTurn(deathX > catX ? 1 : -1)
    }

    settleCat()
    stepCatIdle(dt)
  }

  // --- things she goes off and does ----------------------------------------

  function startCatTask(kind, seconds, towardX) {
    catTask = kind
    catTaskClock = 0
    catTaskFor = seconds
    catTaskX = Math.max(0, Math.min(stage.width - catW, towardX))
    catIdle = "sit"
    catIdleClock = 0
  }

  function maybeCatTask() {
    if (catTask !== "" || !hasCat || clock < nextCatTask)
      return
    if (afloat || catAboard || mood === "away" || mood === "vanish" || catOnHim)
      return
    nextCatTask = clock + Brain.between(40, 90)

    const roll = Math.random()
    if (roll < 0.30) {
      // Off to fetch him something. She is simply gone for a while.
      catGift = true
      startCatTask("gift", Brain.between(8, 14),
                   catX + (Math.random() < 0.5 ? -1 : 1) * spriteW * 2.5)
    } else if (roll < 0.55 && (mood === "walk" || mood === "idle")) {
      // Directly in his way, which is where cats prefer to be.
      startCatTask("underfoot", Brain.between(3, 6), fx + facing * spriteW * 0.5)
    } else if (roll < 0.75 && !overWater) {
      startCatTask("perch", Brain.between(10, 20), fx)
    } else if (roll < 0.88 && inventory.length > 0
               && Math.abs(catX - fx) < spriteW * 1.5) {
      // The most cat-shaped idea available: something leaves his pack.
      const lost = inventory[Math.floor(Math.random() * inventory.length)]
      const kept = []
      for (let i = 0; i < inventory.length; i++)
        if (inventory[i] !== lost)
          kept.push(inventory[i])
      inventory = kept
      dropped = lost
      droppedX = fx + spriteW * 0.5 + (facing > 0 ? 1 : -1) * spriteW * 0.4
      droppedUntil = clock + 9
      say("SOOT. THAT WAS MY " + lost.toUpperCase() + ".", 3.2)
      startCatTask("underfoot", Brain.between(3, 5), droppedX - catW / 2)
    } else {
      const crystals = poisOfKind("crystal")
      if (crystals.length === 0)
        return
      const c = crystals[Math.floor(Math.random() * crystals.length)]
      startCatTask("crystal", Brain.between(5, 9), Number(c.x) - catW / 2)
    }
  }

  // Walk her toward a spot; true once she is there.
  function catWalkTo(dt, goal) {
    const dist = goal - catX
    if (Math.abs(dist) < catUnit * 3)
      return true
    const dir = dist > 0 ? 1 : -1
    const next = catX + dir * walkSpeed * catUnit * 1.45 * dt
    if (surfaceAt(next + catW / 2) === "water")
      return true
    catX = next
    catTurn(dir)
    catMood = "walk"
    return false
  }

  function stepCatTask(dt) {
    catTaskClock += dt

    switch (catTask) {
    case "greet":
      // Straight over to him. Death is the one visitor she gets up for.
      if (catWalkTo(dt, deathX + spriteW * 0.5 - catW / 2)) {
        catMood = "sit"
        catIdle = "rub"
        catTurn(deathX > catX ? 1 : -1)
      }
      if (!deathHere)
        catTask = ""
      break
    case "follow":
      if (catWalkTo(dt, catTaskX))
        catMood = "sit"
      if (catTaskClock >= catTaskFor)
        catTask = ""
      break
    case "gift":
      if (catTaskClock < catTaskFor * 0.5) {
        catWalkTo(dt, catTaskX)
      } else if (catWalkTo(dt, fx + spriteW * 0.4)) {
        catMood = "sit"
      }
      if (catTaskClock >= catTaskFor) {
        catTask = ""
        if (catGift) {
          catGift = false
          const gift = Math.random() < 0.5 ? "fish" : "mushroom"
          if (inventory.indexOf(gift) === -1) {
            acquire(gift)
            say(gift === "fish" ? "SHE BROUGHT ME A FISH."
                                : "THANK YOU. I THINK.", 3.2)
          }
        }
      }
      break
    case "underfoot":
      if (catWalkTo(dt, catTaskX)) {
        catMood = "sit"
        catTurn(fx > catX ? 1 : -1)
        if (mood === "walk")
          enterIdle(Brain.between(1.5, 3.0))
        if (Math.random() < dt * 0.5)
          say("YOU ARE STANDING ON MY FOOT.", 2.6)
      }
      if (catTaskClock >= catTaskFor)
        catTask = ""
      break
    case "perch":
      // Riding: she is drawn into his frame, so she just tracks him.
      catX = fx
      catFootY = footY
      catMood = "sit"
      if (catTaskClock >= catTaskFor || afloat || overWater || mood === "sleep")
        catTask = ""
      break
    case "crystal":
      if (catWalkTo(dt, catTaskX)) {
        catMood = "sit"
        catIdle = "rub"
        if (Math.random() < dt * 1.2)
          spawn(2, catX + catW / 2, catFootY - catH / 2,
                [Sprites.PALETTE["C"], Sprites.PALETTE["A"]], 45, 0.6)
      }
      if (catTaskClock >= catTaskFor)
        catTask = ""
      break
    }

    if (catTask !== "perch")
      settleCat()
  }

  // Reachable as: omarchy-shell shell call landis.wizard catDo greet
  function catDo(kind) {
    const what = String(kind || "").trim()
    switch (what) {
    case "greet":
      if (!deathHere)
        return "no death"
      startCatTask("greet", 30, deathX)
      return "ok"
    case "gift":
      catGift = true
      startCatTask("gift", Brain.between(8, 14), catX + spriteW * 2.5)
      return "ok"
    case "underfoot":
      startCatTask("underfoot", Brain.between(3, 6), fx + facing * spriteW * 0.5)
      return "ok"
    case "perch":
      startCatTask("perch", Brain.between(10, 20), fx)
      return "ok"
    case "crystal": {
      const crystals = poisOfKind("crystal")
      if (crystals.length === 0)
        return "no crystals"
      const c = crystals[Math.floor(Math.random() * crystals.length)]
      startCatTask("crystal", Brain.between(5, 9), Number(c.x) - catW / 2)
      return "ok"
    }
    default:
      // Anything else is treated as an idle activity name.
      catIdle = what
      catIdleClock = 0
      catIdleFor = 4
      return "ok"
    }
  }

  // True while she is riding on his hat and drawn as part of his sprite.
  readonly property bool catRiding: catTask === "perch"

  // Is there water within a step or two of here? Used for her batting at it.
  function nearWater(x) {
    return surfaceAt(x + spriteW * 0.8) === "water" || surfaceAt(x - spriteW * 0.8) === "water"
  }

  // Same idea as turnAround(), for her: a floor on how often she may change
  // which way she is looking.
  function catTurn(dir) {
    if (dir === catFacing || clock - catTurnAt < 0.4)
      return
    catFacing = dir
    catTurnAt = clock
  }

  // --- Death ---------------------------------------------------------------

  readonly property string deathFrame: {
    const list = deathMood === "pet" ? Sprites.DEATH_PET : Sprites.DEATH
    return list[Math.floor(animClock / 0.55) % list.length]
  }

  readonly property real deathOpacity: {
    if (!deathHere)
      return 0
    if (deathMood === "in")
      return Math.min(1, deathClock / 0.9)
    if (deathMood === "out")
      return Math.max(0, 1 - deathClock / 1.1)
    return 1
  }

  // He turns up for the cat. Not for anybody in particular, and never
  // while Landis is out on the lake where there is nobody to stand beside.
  function callDeath() {
    if (deathHere || !hasCat || afloat || mood === "away")
      return false
    const side = catX > stage.width / 2 ? -1 : 1
    deathX = Math.max(0, Math.min(stage.width - spriteW, catX - side * spriteW * 3.2))
    deathFootY = terrainAt(deathX + spriteW / 2)
    deathFacing = side
    deathMood = "in"
    deathClock = 0
    deathHere = true
    // She gets up for him. He is the one visitor she does that for, and him
    // walking to a motionless cat had the relationship backwards.
    if (hasCat && !catOnHim && !afloat)
      startCatTask("greet", 30, deathX)
    return true
  }

  function stepDeath(dt) {
    if (!deathHere) {
      if (hasCat && clock > nextDeath) {
        nextDeath = clock + Brain.between(200, 420)
        callDeath()
      }
      return
    }

    deathClock += dt

    // Landis stays put and turns to face him. Without this he would happily
    // set off rowing while Death was still bent over his cat.
    if (!afloat && mood !== "away" && mood !== "vanish" && mood !== "held"
        && mood !== "fall" && mood !== "cast") {
      if (mood === "walk" || mood === "sleep")
        enterIdle(Brain.between(2.0, 3.5))
      else if (mood === "idle" && moodClock > moodFor - 0.2)
        moodFor += 2.0
      turnAround(deathX > fx ? 1 : -1)
    }

    const targetX = catX + (deathFacing > 0 ? -spriteW * 0.55 : spriteW * 0.55)

    switch (deathMood) {
    case "in":
      if (deathClock >= 0.9) {
        deathMood = "walk"
        deathClock = 0
      }
      break
    case "walk": {
      const dx = targetX - deathX
      if (Math.abs(dx) < unit * 3 || deathClock > 12) {
        deathMood = "pet"
        deathClock = 0
        deathFor = Brain.between(9, 14)
        deathLines = Brain.wrap(Brain.pick(Brain.DEATH_LINES, ""), 16)
        deathSpeech.restart()
        if (Math.random() < 0.6)
          replyTimer.restart()
      } else {
        const speed = walkSpeed * unit * 0.8
        deathX += Math.max(-speed * dt, Math.min(speed * dt, dx))
        deathFacing = dx > 0 ? 1 : -1
      }
      deathFootY = terrainAt(deathX + spriteW / 2)
      break
    }
    case "pet":
      if (deathClock >= deathFor) {
        deathMood = "out"
        deathClock = 0
      }
      break
    case "out":
      if (deathClock >= 1.1) {
        deathHere = false
        deathLines = []
        // A few steps after him, then thinking better of it.
        if (hasCat && catTask === "greet" && !catOnHim)
          startCatTask("follow", Brain.between(2.5, 4.5),
                       deathX + (deathFacing > 0 ? spriteW : -spriteW))
      }
      break
    }
  }

  // --- particles -----------------------------------------------------------

  function spawn(count, ox, oy, colors, speed, life) {
    const next = sparks.slice()
    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2
      const s = speed * (0.35 + Math.random() * 0.9)
      next.push({
        x: ox,
        y: oy,
        vx: Math.cos(angle) * s,
        vy: Math.sin(angle) * s - speed * 0.45,
        age: 0,
        life: life * (0.6 + Math.random() * 0.7),
        c: colors[Math.floor(Math.random() * colors.length)],
        size: unit * (Math.random() < 0.35 ? 2 : 1)
      })
    }
    sparks = next
  }

  function stepSparks(dt) {
    if (sparks.length === 0)
      return
    const next = []
    for (let i = 0; i < sparks.length; i++) {
      const p = sparks[i]
      p.age += dt
      if (p.age >= p.life)
        continue
      p.x += p.vx * dt
      p.y += p.vy * dt
      p.vy += 300 * dt
      next.push(p)
    }
    sparks = next
  }

  // --- the wizard's own coordinates ---------------------------------------

  // Column 9 of the sprite is the middle of the staff orb; column 17 is the
  // crown of his hat. Mirroring swaps them to the far side of the grid.
  readonly property real orbX: fx + (facing < 0 ? (Sprites.W - 9) : 9) * unit
  readonly property real orbY: fy + 5 * unit
  readonly property real headX: fx + (facing < 0 ? (Sprites.W - 17) : 17) * unit

  readonly property string currentFrame: {
    if (clock < blinkUntil && !afloat)
      return "blink"
    switch (mood) {
    case "walk":
      if (catRiding)
        return Sprites.PERCH[Math.floor(animClock / 0.17) % Sprites.PERCH.length]
      return Sprites.WALK[Math.floor(animClock / 0.17) % Sprites.WALK.length]
    case "row":
    case "board":
    case "beach": {
      if (waterEvent === "overboard")
        return Sprites.SWIM[Math.floor(animClock / 0.22) % Sprites.SWIM.length]
      if (waterEvent === "fishing")
        return Sprites.ROW_ROD[Math.floor(animClock / 0.5) % Sprites.ROW_ROD.length]
      const oars = catAboard ? Sprites.ROW_CAT : Sprites.ROW
      return oars[Math.floor(animClock / 0.28) % oars.length]
    }
    case "makebed": {
      const laying = Math.min(0.999, moodClock / Math.max(0.1, moodFor))
      return Sprites.MAKEBED[Math.floor(laying * Sprites.MAKEBED.length)]
    }
    case "packbed": {
      // The same four beats played backwards: he rolls it up and stands.
      const packing = Math.min(0.999, moodClock / Math.max(0.1, moodFor))
      return Sprites.MAKEBED[Sprites.MAKEBED.length - 1
        - Math.floor(packing * Sprites.MAKEBED.length)]
    }
    case "sleep": {
      if (afloat)
        return Sprites.SLEEP[Math.floor(animClock / 0.9) % Sprites.SLEEP.length]
      // Ashore he unrolls a bedroll, and she sleeps on him.
      const bunk = catInBed ? Sprites.BED : Sprites.BED_ALONE
      return bunk[Math.floor(animClock / 1.1) % bunk.length]
    }
    case "held":
    case "fall":
      return Sprites.HELD[Math.floor(animClock / 0.12) % Sprites.HELD.length]
    case "cast":
    case "vanish":
    case "arrive":
      // Plays once and holds on the flourish rather than looping.
      return Sprites.CAST[Math.min(Sprites.CAST.length - 1, Math.floor(moodClock / 0.16))]
    default:
      if (catRiding)
        return Sprites.PERCH[Math.floor(animClock / 0.6) % 2]
      return Sprites.IDLE[Math.floor(animClock / 0.6) % Sprites.IDLE.length]
    }
  }

  // The doorway irises open while he walks into it, and closes behind him on
  // the way back. 0 is shut, 1 is fully open.
  readonly property real portalOpen: {
    if (mood === "vanish")
      return Math.max(0, Math.min(1, moodClock / (moodFor * 0.55)))
    if (mood === "arrive")
      return Math.max(0, Math.min(1, 1 - moodClock / (moodFor * 0.85)))
    return 0
  }

  readonly property string portalFrame: {
    const list = Sprites.PORTAL
    const step = Math.floor(portalOpen * 4)
    if (step >= 3)
      return list[3 + (Math.floor(animClock / 0.11) % 3)]
    return list[Math.max(0, Math.min(3, step))]
  }

  // He dissolves into the doorway once it is open, and resolves out of it.
  readonly property real bodyOpacity: {
    if (leaving || mood === "away")
      return 0
    if (mood === "vanish")
      return Math.max(0, 1 - Math.max(0, moodClock - moodFor * 0.45) / (moodFor * 0.5))
    if (mood === "arrive")
      return Math.max(0, Math.min(1, moodClock / (moodFor * 0.55)))
    return 1
  }

  // How far ahead he checks the ground before putting a foot in the lake.
  readonly property real lookAhead: spriteW * 0.35

  function travel(dt, speed) {
    let dir = facing
    if (targetX >= 0) {
      const delta = targetX - fx
      if (Math.abs(delta) < Math.max(unit * 4, spriteW * 0.6)) {
        fx = targetX
        footY = terrainAt(centerX)
        arriveAtErrand()
        return
      }
      dir = delta > 0 ? 1 : -1
      facing = dir
    }

    const before = fx
    fx += dir * speed * unit * dt

    if (fx <= 0) {
      fx = 0
      turnAround(1)
    } else if (fx >= maxX) {
      fx = maxX
      turnAround(-1)
    }

    // Follow the terrain, but only up gentle ground. A rise steeper than he
    // could plausibly step is a cliff face, so he turns back rather than
    // levitating up the side of it.
    const footing = terrainAt(centerX)
    const climb = footY - footing
    const maxClimb = Math.abs(fx - before) * 2.5 + unit * 0.5
    if (!afloat && clock > ignoreSlopeUntil && climb > maxClimb) {
      fx = before

      if (errand) {
        // A light partway up a cliff is worth looking at, not scaling. If he
        // got near enough to see it, that counts as arriving; if not, this
        // one is written off for a while so he stops trying.
        if (Math.abs(targetX - fx) < spriteW * 3) {
          arriveAtErrand()
        } else {
          noGoX = targetX + spriteW / 2
          noGoUntil = clock + 120
          abandonErrand()
          turnAround(-dir)
        }
        return
      }

      // Having turned away from a wall, commit to that heading for a while.
      // Without this he flips back on the next random re-roll and paces the
      // same few hundred pixels for as long as you care to watch.
      blockCount += 1
      lastBlock = clock
      commitUntil = clock + 6.0
      if (blockCount >= 2) {
        blockCount = 0
        ignoreSlopeUntil = clock + 2.5
      } else if (!turnAround(-dir)) {
        enterIdle(Brain.between(1.0, 2.0))
      }
      return
    }

    blockCount = 0
    footY = footing

    // Look at the ground he is about to step on, not the ground he is on.
    const ahead = centerX + dir * (afloat ? spriteW * 1.6 : lookAhead)
    const surface = surfaceAt(ahead)

    if (surface === "land")
      shoreRolled = false

    if (!afloat && surface === "water") {
      // He does not get in the boat merely because the ground ahead is wet.
      // Decided once per approach rather than per tick, so he either commits
      // to the crossing or turns back and walks somewhere else for a while.
      if (!shoreRolled) {
        shoreRolled = true
        // The lake is most of his walking band and he moves slower on it, so
        // even even-handed behaviour leaves him afloat ~70% of the time. The
        // lever that actually works is a spell ashore after each landing.
        const mustCross = targetX >= 0 && waterBetween(centerX, targetX + spriteW / 2)
        willBoard = mustCross || (clock > noBoatUntil && Math.random() < 0.5)
      }
      if (willBoard) {
        beginBoard()
      } else {
        fx = before
        turnAround(-dir)
        commitUntil = clock + Brain.between(3, 6)
      }
    }
    else if (afloat && surface === "land") {
      // Start pulling in well before landfall, then only step ashore once he
      // is actually at the near shore. Beaching from the middle distance would
      // pop him from small to full size the moment he touched the bank.
      waterTargetY = waterNear
      if (footY < waterNear - unit * 3)
        fx = before
      else if (surfaceAt(centerX) === "land")
        beginBeach()
    }
  }

  function step(dt) {
    clock += dt
    animClock += dt
    moodClock += dt
    stepSparks(dt)
    stepWaterEvent(dt)
    stepLandEvent(dt)
    stepCat(dt)
    stepDeath(dt)
    checkPenned()

    // Nobody stands on the lake. `afloat` tracks his *mood*, so any path that
    // left him over water in a grounded mood -- stepping back out of a portal
    // mid-crossing, most obviously -- had him walking, sleeping and lighting
    // campfires on open water. One invariant beats guarding every caller.
    if (overWater && !afloat && mood !== "held" && mood !== "fall"
        && mood !== "away" && mood !== "vanish" && mood !== "arrive") {
      landEvent = ""
      landClock = 0
      beginBoard()
    }

    // Keep whoever is standing still actually standing on something. travel()
    // is the only thing that sets his footing, so every mood that repositions
    // him another way -- arriving at an errand, stepping out of a portal, a
    // fresh wallpaper -- used to leave him hovering at his old height.
    if (!afloat && mood !== "held" && mood !== "fall" && mood !== "walk") {
      const ground = terrainAt(centerX)
      const drop = ground - footY
      if (Math.abs(drop) > 0.5)
        footY += Math.max(-280 * dt, Math.min(280 * dt, drop))
    }

    if (dropped !== "") {
      if (clock > droppedUntil || Math.abs(centerX - droppedX) < spriteW * 0.5) {
        if (inventory.indexOf(dropped) === -1 && Math.abs(centerX - droppedX) < spriteW * 0.6)
          acquire(dropped)
        dropped = ""
      }
    }

    if (bubbleUntil > 0 && clock > bubbleUntil) {
      bubbleLines = []
      bubbleUntil = 0
    }

    if ((mood === "idle" || mood === "walk") && clock > nextBlink) {
      blinkUntil = clock + 0.12
      nextBlink = clock + Brain.between(2.5, 7)
    }

    switch (mood) {
    case "walk":
      travel(dt, walkSpeed)
      if (mood === "walk" && targetX < 0 && moodClock >= moodFor)
        enterIdle(0)
      break
    case "row": {
      // Fishing and falling in both stop him getting anywhere.
      if (!eventHolds)
        travel(dt, rowSpeed)
      ripple = Math.round((clock * 2.2) * 4) / 4
      // Ease out towards the far shore or back in, shrinking as he goes.
      const drift = (waterTargetY - waterY)
      if (Math.abs(drift) > 1)
        waterY += Math.max(-rowSpeed * unit * dt * 0.7,
                           Math.min(rowSpeed * unit * dt * 0.7, drift))
      footY = Math.max(waterFar, Math.min(waterNear, waterY))
      // A wake, and the occasional fish.
      if (mood === "row" && Math.random() < dt * 1.2)
        spawn(1, centerX, fy + spriteH - unit * 3, [Sprites.PALETTE["A"]], 30, 0.6)
      if (mood === "row" && targetX < 0 && moodClock >= moodFor) {
        moodClock = 0
        moodFor = Brain.between(3, 8)
        if (maybeErrand())
          break
        // Most aimless crossings should end at a shore rather than turning
        // into an afternoon on the water.
        if (Math.random() < 0.55) {
          headAshore()
          break
        }
        if (Math.random() < 0.25 && inventory.indexOf("fish") === -1)
          acquire("fish")
        else if (Math.random() < 0.3)
          turnAround(-facing)
        else
          waterTargetY = Brain.between(waterFar, waterNear)
      }
      break
    }
    case "board":
      footY = stepFrom + (stepTo - stepFrom) * Math.min(1, moodClock / Math.max(0.1, moodFor))
      if (moodClock >= moodFor) {
        footY = stepTo
        enterWalk(0)
      }
      break
    case "beach":
      footY = stepFrom + (stepTo - stepFrom) * Math.min(1, moodClock / Math.max(0.1, moodFor))
      if (moodClock >= moodFor) {
        footY = stepTo
        mood = "walk"
        moodClock = 0
        moodFor = Brain.between(2.5, 7)
      }
      break
    case "idle":
      if (moodClock >= moodFor) {
        if (maybeErrand())
          break
        if (inventory.length > 0 && Math.random() < 0.25)
          useItem(inventory[Math.floor(Math.random() * inventory.length)])
        else if (Math.random() < 0.12)
          enterSleep()
        else if (Math.random() < 0.12 && surfaceAt(centerX) === "land")
          acquire("mushroom")
        else
          enterWalk(0)
      }
      break
    case "makebed":
      if (moodClock >= moodFor) {
        // Decided as he lies down, not when he decided to: that gives her the
        // couple of seconds it takes him to unroll it to come and join him.
        // She is generous about sharing a bed she was already sitting on.
        catInBed = hasCat && !overWater && !catRiding
          && Math.abs(catX - fx) < spriteW * 1.8
        mood = "sleep"
        moodClock = 0
        animClock = 0
        moodFor = sleepFor
        say(catInBed ? Brain.pick(Brain.BEDTIME, "") : "Z Z Z",
            catInBed ? 2.8 : Math.min(sleepFor, 8))
      }
      break
    case "sleep":
      if (moodClock >= moodFor) {
        catInBed = false
        if (afloat || overWater) {
          enterIdle(Brain.between(0.6, 1.4))
        } else {
          mood = "packbed"
          moodClock = 0
          animClock = 0
          moodFor = 1.8
        }
      }
      break
    case "packbed":
      if (moodClock >= moodFor)
        enterIdle(Brain.between(0.6, 1.4))
      break
    case "cast":
      if (moodClock >= moodFor)
        enterIdle(0)
      break
    case "vanish":
      if (moodClock >= moodFor)
        beginAway()
      break
    case "away":
      if (moodClock >= moodFor)
        returnHome()
      break
    case "arrive":
      if (moodClock >= moodFor)
        enterIdle(Brain.between(1.0, 2.0))
      break
    case "fall": {
      // Braced: a bare `const` in a case clause shares the whole switch block's
      // scope, which is a trap waiting for the next case that wants the name.
      vy += 1500 * dt
      footY += vy * dt
      const rest = surfaceAt(centerX) === "water"
        ? Math.max(waterFar, Math.min(waterNear, footY)) : terrainAt(centerX)
      if (footY >= rest) {
        footY = rest
        land()
      }
      break
    }
    }
  }

  // Whatever the terrain does, he should not spend his life in one pocket of
  // it. If he has barely covered any ground for a while, the slope limit lifts
  // long enough for him to climb out of wherever he has got himself.
  function checkPenned() {
    if (mood !== "walk" && mood !== "idle")
      return
    roamMinX = Math.min(roamMinX, fx)
    roamMaxX = Math.max(roamMaxX, fx)
    if (clock - roamSince < 22)
      return
    if (roamMaxX - roamMinX < spriteW * 3) {
      ignoreSlopeUntil = clock + 4.0
      commitUntil = 0
      // If he has boxed himself onto one stretch of bank, the boat is the
      // way out of it -- so stop refusing the crossing.
      shoreRolled = true
      willBoard = true
    }
    roamSince = clock
    roamMinX = fx
    roamMaxX = fx
  }

  function clampToStage() {
    fx = Math.max(0, Math.min(maxX, fx))
    footY = Math.max(spriteH, Math.min(stage.height, footY))
  }

  Timer {
    id: tick
    interval: 33
    repeat: true
    running: root.opened && root.placed
    onTriggered: root.step(interval / 1000)
  }

  Timer {
    id: deathSpeech
    interval: 7000
    onTriggered: root.deathLines = []
  }

  Timer {
    id: replyTimer
    interval: 2600
    onTriggered: {
      if (root.deathHere && root.mood !== "away")
        root.say(Brain.pick(Brain.LANDIS_TO_DEATH, ""), 3.2)
    }
  }

  Timer {
    id: holdTimer
    interval: 2600
    onTriggered: root.holding = ""
  }

  Timer {
    id: leaveTimer
    interval: 620
    onTriggered: {
      if (root.shell)
        root.shell.hide(root.pluginId)
      else
        root.opened = false
    }
  }

  Process {
    id: sceneProc
    stdout: StdioCollector {
      onStreamFinished: root.applyScene(text)
    }
  }

  // Omarchy fires a hook when the theme changes but not when the background
  // alone is cycled, so the wallpaper is watched here instead. readlink is a
  // few milliseconds; re-analysis only runs when the target actually moves.
  Process {
    id: bgWatch
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: {
        const path = String(text || "").trim()
        if (path === "" || path === root.backgroundPath)
          return
        const first = root.backgroundPath === ""
        root.backgroundPath = path
        if (!first)
          root.rescan("")
      }
    }
  }

  Timer {
    interval: 15000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: if (!bgWatch.running) bgWatch.running = true
  }

  PanelWindow {
    id: panel

    visible: root.opened
    screen: root.targetScreen
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "landis-wizard"
    // Bottom puts him above the wallpaper but beneath every window, so he is
    // part of the desktop scene rather than something in front of your work.
    // That is also what makes his terrain-following read correctly: he is only
    // ever seen against the landscape he is walking on.
    WlrLayershell.layer: root.layerName === "top" ? WlrLayer.Top
      : (root.layerName === "overlay" ? WlrLayer.Overlay : WlrLayer.Bottom)
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Everything but the wizard himself stays click-through, so the rest of
    // this full-screen surface never comes between you and your windows. Given
    // as explicit geometry rather than `item:` so it can collapse to nothing
    // while he is away inside something.
    mask: Region {
      x: root.interactive ? wizardBox.x : 0
      y: root.interactive ? wizardBox.y : 0
      width: root.interactive ? wizardBox.width : 0
      height: root.interactive ? wizardBox.height : 0
    }

    Item {
      id: stage
      anchors.fill: parent

      onWidthChanged: root.place()
      onHeightChanged: root.place()
      Component.onCompleted: root.place()

      Repeater {
        model: root.sparks

        Rectangle {
          required property var modelData
          x: Math.round(modelData.x)
          y: Math.round(modelData.y)
          width: modelData.size
          height: modelData.size
          color: modelData.c
          antialiasing: false
          opacity: Math.max(0, 1 - modelData.age / modelData.life)
        }
      }

      // While he is inside, his arrival stirs the lit windows of the place he
      // stepped into -- so you can see where he went. These are the actual
      // window positions the analyser found, not invented spots.
      Repeater {
        model: (root.mood === "away" && root.visiting && root.visiting.windows)
          ? root.visiting.windows : []

        Rectangle {
          required property var modelData
          required property int index

          readonly property real pulse: {
            const v = Math.sin(root.clock * 2.0 + index * 1.9)
            // Mostly dark, with brief flares: a window lights, not a lamp
            // left burning.
            return v > 0.45 ? (v - 0.45) / 0.55 : 0
          }

          width: Math.max(3, root.baseUnit)
          height: width
          x: Math.round(modelData[0] - width / 2)
          y: Math.round(modelData[1] - height / 2)
          color: Sprites.PALETTE["A"]
          antialiasing: false
          opacity: pulse * 0.85
        }
      }

      // Whatever the lake is doing. Drawn behind him so a tentacle rises
      // from beyond the boat rather than in front of it.
      PixelGrid {
        id: tentacleGrid
        rows: root.waterEvent === "tentacle" ? Sprites.FRAMES[root.tentacleFrame] : []
        unit: root.unit
        x: Math.round(root.eventX - width / 2)
        y: Math.round(root.footY - height
             + (Sprites.FRAME_PAD[root.tentacleFrame] || 0) * root.unit)
        z: -2
        opacity: root.waterEvent === "tentacle" ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 200
          }
        }
      }

      // His boat, bobbing off on its own while he is in the water.
      PixelGrid {
        id: looseBoat
        rows: root.waterEvent === "overboard" ? Sprites.FRAMES["boatempty"] : []
        unit: root.unit
        flip: root.facing < 0
        x: Math.round(root.eventX - width / 2)
        y: Math.round(root.footY - height
             + (Sprites.FRAME_PAD["boatempty"] || 0) * root.unit)
        z: -1
        opacity: root.waterEvent === "overboard" ? 1 : 0
      }

      // A fish, briefly reconsidering its life above the waterline.
      PixelGrid {
        id: jumper
        rows: root.waterEvent === "fishjump" ? Sprites.ITEMS["fish"] : []
        unit: root.unit
        x: Math.round(root.eventX - width / 2)
        y: {
          const t = Math.max(0, Math.min(1, root.eventClock / Math.max(0.1, root.eventFor)))
          const arc = 4 * t * (1 - t)     // 0 at each end, 1 at the top
          return Math.round(root.footY - height - arc * root.spriteH * 0.8)
        }
        rotation: root.waterEvent === "fishjump"
          ? -40 + 80 * Math.min(1, root.eventClock / Math.max(0.1, root.eventFor)) : 0
        z: -1
        opacity: root.waterEvent === "fishjump" ? 1 : 0
      }

      // Something big, passing underneath and not surfacing.
      Rectangle {
        id: shadowShape
        visible: root.waterEvent === "shadow"
        width: Math.round(root.spriteW * 1.5)
        height: Math.round(root.unit * 5)
        radius: height / 2
        color: Sprites.PALETTE["5"]
        opacity: root.waterEvent === "shadow"
          ? 0.5 * Math.sin(Math.PI * Math.min(1, root.eventClock / Math.max(0.1, root.eventFor))) : 0
        x: Math.round(root.eventX - width / 2
             + (root.facing > 0 ? 1 : -1) * root.eventClock * root.unit * 14)
        y: Math.round(root.footY - height * 0.4)
        z: -2
      }

      // His working table.
      PixelGrid {
        id: workTable
        rows: root.landEvent === "study" ? Sprites.TABLE[root.tableFrame] : []
        unit: root.baseUnit
        x: Math.round(root.landX - width / 2)
        y: Math.round(root.terrainAt(root.landX) - height
             + (Sprites.TABLE_PAD[root.tableFrame] || 0) * root.baseUnit)
        z: -1
        opacity: root.landEvent === "study" ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 400
          }
        }
      }

      // His campfire.
      PixelGrid {
        id: campfire
        rows: root.landEvent === "campfire" ? Sprites.FIRE[root.fireFrame] : []
        unit: root.baseUnit
        x: Math.round(root.landX - width / 2)
        y: Math.round(root.terrainAt(root.landX) - height
             + (Sprites.FIRE_PAD[root.fireFrame] || 0) * root.baseUnit)
        z: -1
        opacity: root.landEvent === "campfire" ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 400
          }
        }
      }

      // Something she has batted out of his pack, lying where it fell.
      PixelGrid {
        id: droppedItem
        rows: (root.dropped !== "" && Sprites.ITEMS[root.dropped])
          ? Sprites.ITEMS[root.dropped] : []
        unit: root.baseUnit
        x: Math.round(root.droppedX - width / 2)
        y: Math.round(root.terrainAt(root.droppedX) - height)
        z: -1
        opacity: root.dropped !== "" ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 250
          }
        }
      }

      // Soot, in front of Landis and everything else. She is small and very
      // dark, and behind him she kept disappearing into his robe.
      PixelGrid {
        id: catSprite
        // Hidden while she is riding: the boat frame already has her in it.
        rows: (root.hasCat && !root.catAboard && !root.catOnHim)
          ? (root.catShape !== "" ? Sprites.SHAPES[root.catShape]
                                  : Sprites.CATS[root.catFrame]) : []
        unit: root.catUnit
        flip: root.catFacing < 0
        x: Math.round(root.catX)
        y: Math.round(root.catFootY - height + root.catPad)
        z: 2
        opacity: root.hasCat ? 1 : 0
      }

      PixelGrid {
        id: deathSprite
        rows: root.deathHere ? Sprites.FRAMES[root.deathFrame] : []
        unit: root.baseUnit
        flip: root.deathFacing < 0
        x: Math.round(root.deathX)
        y: Math.round(root.deathFootY - height
             + (Sprites.FRAME_PAD[root.deathFrame] || 0) * root.baseUnit)
        opacity: root.deathOpacity
      }

      SpeechBubble {
        id: deathBubble
        lines: root.deathLines
        unit: Math.max(2, Math.round(root.unit) - 1)
        inverted: true
        x: Math.max(0, Math.min(stage.width - width,
             Math.round(root.deathX + root.spriteW / 2 - width / 2)))
        y: Math.max(0, Math.round(root.deathFootY - root.spriteH) - height - root.unit)
        tailAt: root.deathX + root.spriteW / 2 - x
        opacity: (root.deathLines.length > 0 && root.deathOpacity > 0.5) ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 140
          }
        }
      }

      SpeechBubble {
        id: bubble
        lines: root.bubbleLines
        // One step finer than the wizard's own grid: still whole pixels, but
        // it keeps a chatty bubble from dwarfing the wizard under it.
        // Integer: glyphs at a fractional scale lose their legibility long
        // before he does.
        unit: Math.max(2, Math.round(root.unit) - 1)
        x: Math.max(0, Math.min(stage.width - width, Math.round(root.headX - width / 2)))
        y: Math.max(0, Math.round(root.fy) - height - root.unit)
        tailAt: root.headX - x
        // Driven by opacity rather than `visible`: a hidden Canvas drops the
        // paint request it is given, and then never repaints on the way back.
        opacity: root.bubbleLines.length > 0 && root.mood !== "away" ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 120
          }
        }
      }

      // What he is carrying, shown while you hover him.
      Row {
        id: packRow
        spacing: root.unit
        x: Math.max(0, Math.min(stage.width - width, Math.round(root.centerX - width / 2)))
        y: Math.round(root.fy) - height - root.unit
        opacity: root.showPack && root.inventory.length > 0 && root.bubbleLines.length === 0 ? 1 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 150
          }
        }

        Repeater {
          model: root.inventory

          PixelGrid {
            required property var modelData
            rows: Sprites.ITEMS[modelData]
            // Integer: glyphs at a fractional scale lose their legibility long
        // before he does.
        unit: Math.max(2, Math.round(root.unit) - 1)
          }
        }
      }

      Item {
        id: wizardBox
        // Whole device pixels. Snapping to multiples of `unit` made him read
        // as 8-bit while the scale was fixed, but now that it slides with
        // distance the same snap would judder him as the step size changed.
        x: Math.round(root.fx)
        y: Math.round(root.fy + root.framePad)
        width: root.spriteW
        height: root.spriteH

        PixelGrid {
          id: portalGrid
          rows: root.portalOpen > 0.01 ? Sprites.FRAMES[root.portalFrame] : []
          unit: root.unit
          z: -1
          opacity: root.portalOpen > 0.01 ? 1 : 0

          Behavior on opacity {
            NumberAnimation {
              duration: 150
            }
          }
        }

        PixelGrid {
          id: sprite
          // No anchors: PixelGrid derives its own width and height from the
          // grid it is given, and anchoring would fight those bindings.
          rows: Sprites.FRAMES[root.currentFrame]
          unit: root.unit
          flip: root.facing < 0
          opacity: root.bodyOpacity

          Behavior on opacity {
            // Driven frame by frame while he is stepping through, so the
            // fade must not lag behind the doorway opening.
            NumberAnimation {
              duration: (root.mood === "vanish" || root.mood === "arrive") ? 0 : 260
            }
          }
        }

        // His reflection, when there is water under him to cast one. Anchored
        // at the hull's waterline rather than the sprite's foot, so it hinges
        // where he actually meets the lake.
        PixelGrid {
          id: reflection
          rows: root.afloat ? Sprites.FRAMES[root.currentFrame] : []
          unit: root.unit
          flip: root.facing < 0
          flipV: true
          wave: root.unit * 0.75
          wavePhase: root.ripple
          y: root.unit * 27
          opacity: root.afloat && root.mood !== "away" ? 0.32 : 0

          Behavior on opacity {
            NumberAnimation {
              duration: 260
            }
          }
        }

        // The item he is holding up, tucked beside his hat on the free side.
        PixelGrid {
          id: heldItem
          rows: root.holding !== "" && Sprites.ITEMS[root.holding]
            ? Sprites.ITEMS[root.holding] : []
          unit: root.unit
          x: root.facing < 0 ? -width + root.unit * 3 : parent.width - root.unit * 3
          y: root.unit * 8
          opacity: root.holding !== "" && root.mood !== "away" ? 1 : 0

          Behavior on opacity {
            NumberAnimation {
              duration: 180
            }
          }
        }

        MouseArea {
          id: grab
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

          property bool dragging: false
          property real grabDX: 0
          property real grabDY: 0
          property real pressX: 0
          property real pressY: 0

          onEntered: root.showPack = true
          onExited: root.showPack = false

          onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton)
              return
            pressX = mouse.x
            pressY = mouse.y
            grabDX = mouse.x
            grabDY = mouse.y
            dragging = false
          }

          onPositionChanged: mouse => {
            if (!pressed) {
              root.notice(mouse.x)
              return
            }
            if (!dragging) {
              // A short wobble is a click, not a drag; without a threshold
              // every poke would pick him up by a pixel or two.
              if (Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) < root.unit * 2)
                return
              dragging = true
              root.pickUp()
            }
            const p = mapToItem(stage, mouse.x, mouse.y)
            root.fx = p.x - grabDX
            root.footY = p.y - grabDY + root.spriteH
            root.clampToStage()
          }

          onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton)
              return
            if (dragging) {
              dragging = false
              root.drop()
            } else {
              root.poke()
            }
          }

          onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
              // Middle-click rummages in the pack.
              if (root.inventory.length > 0)
                root.useItem(root.inventory[Math.floor(Math.random() * root.inventory.length)])
              else
                root.say("MY POCKETS ARE EMPTY.", 2.4)
            } else if (mouse.button === Qt.RightButton) {
              root.dismiss()
            }
          }
        }
      }
    }
  }

  // Drop him on the floor at a random spot the first time the surface has a
  // size, and keep him on the floor if the output is later resized.
  function place() {
    if (stage.width <= 0 || stage.height <= 0)
      return
    if (!placed) {
      placed = true
      fx = Brain.between(0.2, 0.8) * Math.max(1, maxX)
      footY = terrainAt(centerX)
      catX = Math.max(0, fx - spriteW * 0.75)
      catFootY = terrainAt(catX + catW / 2)
      enterWalk(Brain.between(2, 4))
      rescan("")
    } else if (mood !== "held" && mood !== "fall") {
      clampToStage()
      footY = terrainAt(centerX)
    }
  }

  // He stops and turns toward the pointer when you hover him -- the small
  // acknowledgement that makes him feel present rather than scripted.
  function notice(localX) {
    if (mood !== "walk" && mood !== "idle")
      return
    if (targetX >= 0)
      return
    // Dead zone across the middle third: without it, a pointer resting near
    // his centre line flips him back and forth on every pixel of jitter.
    const fromCentre = localX - spriteW / 2
    if (Math.abs(fromCentre) > spriteW * 0.17)
      turnAround(fromCentre > 0 ? 1 : -1)
    if (mood === "walk")
      enterIdle(Brain.between(0.9, 1.8))
  }
}
