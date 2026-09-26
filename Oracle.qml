import QtQuick
import Quickshell.Io

// The wizard's second voice.
//
// Brain.js is the first one and remains the floor: a fixed list of lines that
// is always there, costs nothing, and never fails. This sits on top of it and
// asks a local model on this machine for something better suited to the moment
// -- what he is standing on, what the wallpaper analysis found, what the
// machine itself is doing.
//
// Everything here is written so that a missing daemon, an unpulled model or a
// slow reply is a non-event. `ready` stays false, `take()` returns "", the
// beat signals never fire, and the caller uses the static line it already had.
// The wizard degrades to exactly the wizard he was before.
//
// Two shapes of request, because they want opposite things:
//
//   the pool   -- ambient lines fetched several at a time, well before they
//                 are needed. Speech triggered by a click has to be instant,
//                 and a local model is not instant, so the answer has to
//                 already be in hand when the click lands.
//   on demand  -- a line for one specific beat, or a reply to something the
//                 human said. Slower, and that is fine: the caller has already
//                 said the static line, and swaps it out if the better one
//                 arrives while the bubble is still up.
Item {
  id: oracle

  visible: false

  // --- configuration -------------------------------------------------------
  property bool active: true
  property string pluginDir: ""
  property string host: "127.0.0.1:11434"
  property string model: "llama3.2:3b"
  property bool senseMachine: true     // may he look at load, disk, battery
  property int timeoutSec: 20          // a single beat: he has already spoken
  property int askTimeoutSec: 45       // a question: worth waiting for
  property int poolTimeoutSec: 90      // several lines, entirely in background
  property int poolTarget: 6           // ambient lines kept in hand

  // --- state ---------------------------------------------------------------
  property bool ready: false           // daemon up, model pulled
  property string status: "off"        // off | probing | ready | unavailable
  property string detail: ""           // why, when unavailable
  property var pool: []
  property bool thinking: false        // a reply is being waited on
  property int served: 0               // lines he has actually spoken
  property int failures: 0

  // The situation, supplied by the wizard each time he asks for something.
  // A function rather than a property so it is always read fresh at the
  // moment of asking, never left over from the last beat.
  property var contextProvider: null

  signal beatReady(string beat, int serial, string text)
  signal deathReady(string text)
  signal replyReady(string text)
  signal replyFailed()

  property int beatSerial: 0
  property string pendingBeat: ""
  property int pendingSerial: 0
  property int beatGapMs: 2000         // shortest gap between generated beats
  property real lastBeatAt: 0

  readonly property var baseArgs: [
    "python3", pluginDir + "oracle.py"
  ]

  function argsFor(mode, extra) {
    const seconds = mode === "ask" ? askTimeoutSec
      : (mode === "ambient" ? poolTimeoutSec : timeoutSec)
    let args = baseArgs.concat([mode, "--host", host, "--model", model,
                                "--timeout", String(seconds)])
    if (!senseMachine)
      args.push("--no-sense")
    return extra ? args.concat(extra) : args
  }

  function contextJson(overrides) {
    let ctx = {}
    if (contextProvider) {
      const supplied = contextProvider()
      if (supplied)
        ctx = supplied
    }
    if (overrides)
      for (const key in overrides)
        ctx[key] = overrides[key]
    return JSON.stringify(ctx)
  }

  // --- probing -------------------------------------------------------------

  function probe() {
    if (!active) {
      status = "off"
      ready = false
      return
    }
    if (probeProc.running)
      return
    status = "probing"
    probeProc.command = argsFor("check", null)
    probeProc.running = true
  }

  Process {
    id: probeProc
    stderr: StdioCollector {
      onStreamFinished: oracle.detail = String(text || "").trim().split("\n")[0]
    }
    onExited: (code) => {
      oracle.ready = (code === 0)
      oracle.status = oracle.ready ? "ready" : "unavailable"
      if (oracle.ready) {
        oracle.detail = ""
        oracle.failures = 0
        oracle.probeMisses = 0
        oracle.refill()
      } else {
        oracle.probeMisses += 1
      }
    }
  }

  // The daemon may be started, or the model pulled, long after he was
  // summoned, so he keeps looking: found once, he picks his voice up without
  // needing to be dismissed and summoned again.
  //
  // On a machine with no Ollama on it that would otherwise be a process spawned
  // every forty seconds until the end of time, so the gap doubles each time he
  // finds nothing, out to ten minutes.
  property int probeMisses: 0

  Timer {
    interval: oracle.ready
      ? 300000
      : Math.min(600000, 30000 * Math.pow(2, Math.min(oracle.probeMisses, 5)))
    repeat: true
    running: oracle.active
    triggeredOnStart: true
    onTriggered: oracle.probe()
  }

  // --- the ambient pool ----------------------------------------------------

  function refill() {
    if (!active || !ready || poolProc.running)
      return
    if (pool.length >= poolTarget)
      return
    const want = Math.max(2, poolTarget - pool.length + 1)
    poolProc.command = argsFor("ambient", ["--count", String(want),
                                           "--ctx", contextJson(null)])
    poolProc.running = true
  }

  // An ambient line, or "" if there are none in hand. Never blocks and never
  // waits: an empty string means the caller should use its static list.
  function take() {
    if (pool.length === 0) {
      refill()
      return ""
    }
    const lines = pool.slice()
    const line = lines.shift()
    pool = lines
    served += 1
    if (pool.length <= 1)
      refill()
    return line
  }

  Process {
    id: poolProc
    stderr: StdioCollector {
      onStreamFinished: oracle.noteError("pool", text)
    }
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = String(text || "").split("\n")
        let next = oracle.pool.slice()
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i].trim()
          if (line !== "" && next.indexOf(line) < 0)
            next.push(line)
        }
        oracle.pool = next.slice(0, oracle.poolTarget + 2)
      }
    }
    onExited: (code) => {
      if (code !== 0)
        oracle.noteFailure()
    }
  }

  // Refill in the background whenever he is running low, so the pool is
  // topped up between remarks rather than at the moment one is wanted.
  Timer {
    interval: 30000
    repeat: true
    running: oracle.active && oracle.ready
    onTriggered: oracle.refill()
  }

  // --- one line, for one beat ----------------------------------------------

  // Ask for a line suited to something that is happening right now. The caller
  // has already spoken its static line; if this arrives in time and the moment
  // has not moved on, `beatReady` lets it swap the words out.
  //
  // Returns the serial the answer will carry, or -1 if nothing was asked.
  function requestBeat(beat, extra) {
    if (!active || !ready || beatProc.running)
      return -1
    // A wizard who remarks on everything would have the machine generating
    // text more or less continuously. He is allowed one considered thought at
    // a time, and a breath between them; anything that happens inside that
    // window keeps the line it already said.
    const now = Date.now()
    if (now - lastBeatAt < beatGapMs)
      return -1
    lastBeatAt = now
    beatSerial += 1
    pendingBeat = beat
    pendingSerial = beatSerial
    let ctx = { beat: beat }
    if (extra)
      for (const key in extra)
        ctx[key] = extra[key]
    beatProc.command = argsFor("beat", ["--ctx", contextJson(ctx)])
    beatProc.running = true
    return beatSerial
  }

  // Death speaks in his own voice, from his own prompt, so he gets his own
  // process rather than queueing behind whatever Landis is thinking about.
  function requestDeath(heard) {
    if (!active || !ready || deathProc.running)
      return false
    deathProc.command = argsFor("beat", ["--ctx",
      contextJson({ beat: "deathsays",
                    heard: String(heard || ""),
                    heardFrom: "LANDIS" })])
    deathProc.running = true
    return true
  }

  Process {
    id: deathProc
    stderr: StdioCollector {
      onStreamFinished: oracle.noteError("death", text)
    }
    stdout: StdioCollector {
      onStreamFinished: {
        const line = String(text || "").trim()
        if (line === "")
          return
        oracle.served += 1
        oracle.deathReady(line)
      }
    }
    onExited: (code) => {
      if (code !== 0)
        oracle.noteFailure()
    }
  }

  // The answer is dispatched from the stream, where the text is certainly
  // there, and failure is counted off the exit code, which is certainly right.
  // Quickshell promises no order between `streamFinished` and `exited`, so
  // neither handler is allowed to need the other to have run first. A failed
  // run prints nothing on stdout, so the two can never both fire.
  Process {
    id: beatProc
    stderr: StdioCollector {
      onStreamFinished: oracle.noteError("beat", text)
    }
    stdout: StdioCollector {
      onStreamFinished: {
        const line = String(text || "").trim()
        if (line === "")
          return
        oracle.served += 1
        oracle.beatReady(oracle.pendingBeat, oracle.pendingSerial, line)
      }
    }
    onExited: (code) => {
      if (code !== 0)
        oracle.noteFailure()
    }
  }

  // --- conversation --------------------------------------------------------

  property int turns: 0                // exchanges this summoning
  property int sinceReflect: 0         // exchanges since he last took stock

  function converse(question) {
    if (!active || !ready)
      return false
    if (askProc.running)
      return false
    thinking = true
    askProc.question = question
    askProc.command = argsFor("ask", ["--ctx", contextJson({
      question: question
    })])
    askProc.running = true
    return true
  }

  Process {
    id: askProc
    property string question: ""
    stderr: StdioCollector {
      onStreamFinished: oracle.noteError("ask", text)
    }
    stdout: StdioCollector {
      onStreamFinished: {
        const line = String(text || "").trim()
        if (line === "")
          return
        oracle.thinking = false
        // oracle.py has already written this exchange to the memory file; all
        // that is kept here is the count, for `oracle ""`.
        oracle.turns += 1
        oracle.sinceReflect += 1
        oracle.served += 1
        oracle.replyReady(line)
      }
    }
    onExited: (code) => {
      oracle.thinking = false
      if (code !== 0) {
        oracle.noteFailure()
        oracle.replyFailed()
      }
    }
  }

  // --- what he keeps between summonings ------------------------------------

  // Record something that happened. Queued, because several things can happen
  // in the same second and each one of these is a process.
  property var pending: []

  function remember(text) {
    const body = String(text || "").trim()
    if (!active || body === "")
      return
    pending = pending.concat([body])
    drainMemory()
  }

  function drainMemory() {
    if (rememberProc.running || pending.length === 0)
      return
    const queue = pending.slice()
    const next = queue.shift()
    pending = queue
    rememberProc.command = baseArgs.concat(["remember", "--journal", next])
    rememberProc.running = true
  }

  Process {
    id: rememberProc
    onExited: oracle.drainMemory()
  }

  // Ask him what he has noticed about the human. Slow and occasional: it is
  // the only part of memory a model writes, so the less often it runs, the
  // less often it can be wrong.
  property string learned: ""          // the last thing he worked out

  // Off unless you ask for it. The journal and the conversation are facts --
  // events the plugin saw, words that were actually typed. This is the one
  // part a model writes, and a 3b model asked what it has noticed about you
  // will make something up to be helpful: it offered "THEY TYPE WITH THEIR
  // LEFT HAND", which it cannot possibly know. Requiring it to quote its
  // evidence rejects most of that, but not the case where it quotes a real
  // line and draws an invented conclusion from it. So: opt in, knowing that.
  property bool learnAboutYou: false

  function reflect() {
    if (!active || !ready || !learnAboutYou || reflectProc.running
        || sinceReflect < 2)
      return
    sinceReflect = 0
    reflectProc.command = argsFor("reflect", null)
    reflectProc.running = true
  }

  Process {
    id: reflectProc
    stdout: StdioCollector {
      onStreamFinished: {
        const noticed = String(text || "").trim()
        if (noticed !== "")
          oracle.learned = noticed
      }
    }
  }

  Timer {
    interval: 240000
    repeat: true
    running: oracle.active && oracle.ready && oracle.learnAboutYou
    onTriggered: oracle.reflect()
  }

  function forget() {
    turns = 0
    forgetProc.command = baseArgs.concat(["forget", "--what", "talk"])
    forgetProc.running = true
    return "ok"
  }

  function forgetEverything() {
    turns = 0
    forgetProc.command = baseArgs.concat(["forget", "--what", "all"])
    forgetProc.running = true
    return "ok"
  }

  Process { id: forgetProc }

  // --- giving up gracefully ------------------------------------------------

  // A daemon that has gone away mid-session looks exactly like one that was
  // never there, so after a few refusals he stops asking and lets the probe
  // timer decide when it is worth trying again.
  // Keep the last thing that went wrong, so `oracle ""` can say why he is
  // speaking off the list instead of leaving you to guess.
  property string lastError: ""

  function noteError(where, text) {
    const body = String(text || "").trim().split("\n")[0]
    if (body === "")
      return
    lastError = where + ": " + body
    detail = lastError
  }

  function noteFailure() {
    failures += 1
    if (failures >= 3) {
      ready = false
      status = "unavailable"
      failures = 0
    }
  }

  function describe() {
    return {
      active: active,
      status: status,
      ready: ready,
      model: model,
      host: host,
      sense: senseMachine,
      pooled: pool.length,
      thinking: thinking,
      spoken: served,
      turns: turns,
      learned: learned,
      learnAboutYou: learnAboutYou,
      detail: detail,
      lastError: lastError
    }
  }
}
