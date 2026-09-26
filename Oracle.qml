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
  property int timeoutSec: 20
  property int poolTarget: 4           // ambient lines kept in hand

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
  signal replyReady(string text)
  signal replyFailed()

  property int beatSerial: 0
  property string pendingBeat: ""
  property int pendingSerial: 0
  property int beatGapMs: 6000         // shortest gap between generated beats
  property real lastBeatAt: 0

  readonly property var baseArgs: [
    "python3", pluginDir + "oracle.py"
  ]

  function argsFor(mode, extra) {
    let args = baseArgs.concat([mode, "--host", host, "--model", model,
                                "--timeout", String(timeoutSec)])
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
  function requestBeat(beat) {
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
    beatProc.command = argsFor("beat", ["--ctx", contextJson({ beat: beat })])
    beatProc.running = true
    return beatSerial
  }

  // The answer is dispatched from the stream, where the text is certainly
  // there, and failure is counted off the exit code, which is certainly right.
  // Quickshell promises no order between `streamFinished` and `exited`, so
  // neither handler is allowed to need the other to have run first. A failed
  // run prints nothing on stdout, so the two can never both fire.
  Process {
    id: beatProc
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

  property var history: []             // the last few exchanges, as messages

  function converse(question) {
    if (!active || !ready)
      return false
    if (askProc.running)
      return false
    thinking = true
    askProc.question = question
    askProc.command = argsFor("ask", ["--ctx", contextJson({
      question: question,
      history: history
    })])
    askProc.running = true
    return true
  }

  Process {
    id: askProc
    property string question: ""
    stdout: StdioCollector {
      onStreamFinished: {
        const line = String(text || "").trim()
        if (line === "")
          return
        oracle.thinking = false
        // Four exchanges is enough for him to follow a thread without the
        // prompt growing until a small model loses the plot.
        let next = oracle.history.concat([
          { role: "user", content: askProc.question },
          { role: "assistant", content: line }
        ])
        while (next.length > 8)
          next.shift()
        oracle.history = next
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

  function forget() {
    history = []
    return "ok"
  }

  // --- giving up gracefully ------------------------------------------------

  // A daemon that has gone away mid-session looks exactly like one that was
  // never there, so after a few refusals he stops asking and lets the probe
  // timer decide when it is worth trying again.
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
      turns: history.length / 2,
      detail: detail
    }
  }
}
