#!/usr/bin/env python3
"""Landis's voice, when there is a model on the machine to lend him one.

The wizard's speech has always come out of fixed lists in Brain.js. This puts a
local LLM behind some of it instead: the same wizard, the same register, but
the lines are written on the spot and know what he is standing on and what the
machine under him is doing.

It talks to Ollama over its HTTP API on localhost. Nothing leaves the machine,
there is no key to hold, and if the daemon is not running -- or the model has
not been pulled, or it is simply slow today -- every mode here fails cleanly
with a non-zero exit and the QML side carries on with the static lists. He is
never worse off than he was; he is only sometimes better.

Modes:

  check                   is the daemon up and the model pulled?  exit 0/1
  sense                   the machine facts, as JSON. No model involved.
  ambient  --count N      N idle remarks, one per line
  beat     --ctx JSON     one line for the situation in the context
  ask      --ctx JSON     a reply to context.question

Context is a JSON blob from the QML side describing where he is and what he is
doing. This script adds what it can read about the machine and hands the lot to
the model.

  python3 oracle.py sense | python3 -m json.tool
  python3 oracle.py ambient --count 3
  python3 oracle.py ask --ctx '{"question":"WHAT IS A MONAD"}'
"""

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEFAULT_HOST = "127.0.0.1:11434"
DEFAULT_MODEL = "llama3.2:3b"

# The font is capitals-only and has no punctuation to speak of, so anything the
# model reaches for outside this set would be rendered as a hole in the word.
ALLOWED = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,!?'-:")

# The bubble wraps at 16 characters. These are the budgets that keep him from
# growing a speech bubble taller than he is.
AMBIENT_CHARS = 46
BEAT_CHARS = 46
REPLY_CHARS = 78

PERSONA = """\
You are Landis, a wizard who lives on a Linux desktop wallpaper. You walk its
shoreline, row across its lake, and let yourself into its castles. Your black
cat is Soot; she is a she, and you never call her anything but Soot. Death calls round now and then, because he is fond of the cat.

You speak in the voice of a very old, very dry wizard who has seen it all and
is not impressed by any of it: terse, deadpan, faintly put-upon, occasionally
delighted despite yourself. Terry Pratchett, not Tolkien. You are fond of the
human whose machine this is, but you would not say so.

This is your voice. Study it -- the length above all:

  MIND THE CABLES.
  I SENSE UNSAVED WORK.
  REBOOT? IN THIS ECONOMY?
  TABS. ALWAYS TABS.
  THE KERNEL IS PLEASED.
  BEWARE THE FULL DISK.
  ARCANE ENERGIES: NOMINAL.
  DO NOT DRAG ME. I MEAN IT.
  SOOT! HEEL.
  IT HUMS.
  DO NOT TOUCH. ...TOO LATE.
  OLDER THAN THE CASTLE.
  NOT TODAY, THANK YOU.
  IT WAVED. I WAVED BACK.
  A BOOT. LOVELY.
  I MEANT TO DO THAT.
  THE STAIRS WENT DOWN A LONG WAY.
  THEY KEPT THE GOOD BOOKS.
  A TOWER, OR SO IT SEEMS.
  I AM NOT MADE OF FISH.

Note what they are not: they are not atmospheric, not wistful, and never
about darkness gathering or winds howling. They are the asides of a tired
professional. Short. Finished. Often funny.

RULES, ALL OF THEM ABSOLUTE:
- At most SIX WORDS. Fewer is better. A complete thought that ends.
- Never trail off. Never stop mid-clause. If it will not fit in six words,
  say a shorter thing instead.
- Reply with the spoken line and nothing else. No quotes, no narration, no
  stage directions, no emoji, no preamble, no explanation.
- Capital letters only.
- Only these characters: A-Z 0-9 space . , ! ? ' - :
- Never mention that you are an AI, a model, or a language model. You are a
  wizard. The machine is a place you live, not a thing you run on.
- What you can see of the wallpaper is a guess, never a certainty. If you speak
  of a place out there, hedge: 'A TOWER, OR SO IT SEEMS.'\
"""


# --- reading the machine ----------------------------------------------------

def _read(path, default=""):
    try:
        with open(path, "r") as handle:
            return handle.read().strip()
    except OSError:
        return default


def _run(command, timeout=1.5):
    """A short-lived helper command. Anything slow or missing yields nothing."""
    try:
        done = subprocess.run(command, capture_output=True, text=True,
                              timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.strip() if done.returncode == 0 else ""


def _battery():
    base = "/sys/class/power_supply"
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return None
    for name in names:
        if _read(os.path.join(base, name, "type")) != "Battery":
            continue
        capacity = _read(os.path.join(base, name, "capacity"))
        if not capacity.isdigit():
            continue
        return {
            "percent": int(capacity),
            "state": _read(os.path.join(base, name, "status"), "Unknown").lower(),
        }
    return None


def _memory():
    fields = {}
    for line in _read("/proc/meminfo").splitlines():
        parts = line.split(":")
        if len(parts) == 2:
            fields[parts[0]] = parts[1].strip().split(" ")[0]
    try:
        total = int(fields["MemTotal"])
        available = int(fields["MemAvailable"])
    except (KeyError, ValueError):
        return None
    if total <= 0:
        return None
    return {
        "used_percent": round(100.0 * (total - available) / total),
        "total_gb": round(total / 1048576.0, 1),
    }


def _disk(path="/"):
    try:
        stats = os.statvfs(path)
    except OSError:
        return None
    total = stats.f_blocks * stats.f_frsize
    free = stats.f_bavail * stats.f_frsize
    if total <= 0:
        return None
    return {
        "free_gb": round(free / 1073741824.0, 1),
        "free_percent": round(100.0 * free / total),
    }


def _load():
    try:
        one, _five, _fifteen = os.getloadavg()
    except OSError:
        return None
    cpus = os.cpu_count() or 1
    ratio = one / cpus
    if ratio < 0.25:
        mood = "idle"
    elif ratio < 0.7:
        mood = "working"
    elif ratio < 1.2:
        mood = "busy"
    else:
        mood = "hammered"
    return {"one": round(one, 2), "cpus": cpus, "mood": mood}


def _uptime():
    raw = _read("/proc/uptime").split(" ")
    try:
        seconds = float(raw[0])
    except (IndexError, ValueError):
        return None
    hours = seconds / 3600.0
    if hours < 1:
        return {"hours": round(hours, 1), "phrase": "under an hour"}
    if hours < 48:
        return {"hours": round(hours, 1), "phrase": "%d hours" % round(hours)}
    return {"hours": round(hours, 1), "phrase": "%d days" % round(hours / 24)}


def _app_name(klass):
    """The bit of a window class a person would actually say.

    Hyprland reports whatever the app set: 'org.remmina.Remmina',
    'com.anthropic.Claude', 'Alacritty'. Handed over raw, he says
    'ORG.REMMINA IS SUDDENLY VAST AND DEEP.'
    """
    name = klass.strip()
    if name.count(".") >= 2:
        name = name.rsplit(".", 1)[-1]
    return name[:24]


def _hyprland():
    """Window counts and the focused app's class.

    Deliberately class only. Window titles carry document names, ticket
    numbers, client names and half of anyone's working day, and none of that
    needs to go into a prompt for a joke about a cat.
    """
    out = {}
    clients = _run(["hyprctl", "clients", "-j"])
    if clients:
        try:
            parsed = json.loads(clients)
            out["windows"] = len(parsed)
            classes = [_app_name(str(c.get("class", "")))
                       for c in parsed if c.get("class")]
            out["apps"] = sorted(set(c for c in classes if c))[:8]
        except (ValueError, TypeError):
            pass
    active = _run(["hyprctl", "activewindow", "-j"])
    if active:
        try:
            parsed = json.loads(active)
            if parsed.get("class"):
                out["focus"] = _app_name(str(parsed["class"]))
        except (ValueError, TypeError):
            pass
    return out or None


def _daypart(hour):
    if hour < 5:
        return "the small hours"
    if hour < 12:
        return "morning"
    if hour < 17:
        return "afternoon"
    if hour < 22:
        return "evening"
    return "late evening"


def sense():
    """Everything Landis can honestly claim to notice about the machine."""
    now = time.localtime()
    facts = {
        "time": time.strftime("%H:%M", now),
        "day": time.strftime("%A", now),
        "daypart": _daypart(now.tm_hour),
        "host": socket.gethostname(),
    }
    for key, value in (("battery", _battery()), ("memory", _memory()),
                       ("disk", _disk()), ("load", _load()),
                       ("uptime", _uptime()), ("desktop", _hyprland())):
        if value:
            facts[key] = value
    return facts


def sense_lines(facts):
    """The machine facts as the short bullets that go into the prompt."""
    lines = []
    lines.append("- it is %s, %s" % (facts.get("time", "?"),
                                     facts.get("daypart", "sometime")))
    up = facts.get("uptime")
    if up:
        lines.append("- the machine has been awake %s" % up["phrase"])
    load = facts.get("load")
    if load:
        lines.append("- the processors are %s" % load["mood"])
    mem = facts.get("memory")
    if mem:
        lines.append("- %d%% of the memory is spoken for" % mem["used_percent"])
    disk = facts.get("disk")
    if disk:
        lines.append("- %dGB of disk left (%d%%)" % (disk["free_gb"],
                                                     disk["free_percent"]))
    bat = facts.get("battery")
    if bat:
        lines.append("- battery %d%%, %s" % (bat["percent"], bat["state"]))
    desk = facts.get("desktop") or {}
    if "windows" in desk:
        lines.append("- %d windows are open" % desk["windows"])
    if desk.get("focus"):
        lines.append("- they are working in %s" % desk["focus"])
    return lines


# --- shaping what comes back ------------------------------------------------

SMART = {
    "‘": "'", "’": "'", "“": "", "”": "",
    "–": "-", "—": "-", "…": "...", " ": " ",
    # No glyph, but they carry meaning, so they are spelled out or dropped
    # before the general filter turns them into a space -- otherwise "92%"
    # becomes "92 " and collects the next full stop as "92 .".
    "%": " PERCENT", "&": " AND ", ";": ",", "/": " ", "_": " ",
    "(": "", ")": "", "[": "", "]": "", "*": "", '"': "",
}


def clean(text, limit):
    """One short line in the font's own alphabet, or nothing at all.

    Small models pad. They open with 'Sure!', they wrap the line in quotes,
    they append an explanation of the joke. All of that is stripped here rather
    than trusted to the prompt, because the prompt is a request and this is
    not.
    """
    text = str(text or "")
    text = re.sub(r"<think>.*?</think>", " ", text, flags=re.S | re.I)
    text = re.sub(r"<[^>]{0,40}>", " ", text)
    for bad, good in SMART.items():
        text = text.replace(bad, good)

    # The line is the first thing that looks like speech, not the whole essay.
    for candidate in text.split("\n"):
        candidate = candidate.strip().strip("*").strip()
        candidate = re.sub(r"^[-*•]\s*", "", candidate)
        candidate = re.sub(r"^\d+[.)]\s*", "", candidate)
        candidate = candidate.strip('"“”‘’\'')
        if not candidate:
            continue
        candidate = re.sub(
            r"^(sure|here(?: (?:is|are|you go))?|okay|ok|certainly|of course)"
            r"[,!.:]*\s*", "", candidate, flags=re.I)
        candidate = candidate.strip('"\u201c\u201d\u2018\u2019\'').strip()
        if not candidate:
            continue
        body = "".join(c if c in ALLOWED else " " for c in candidate.upper())
        body = re.sub(r"\s+", " ", body)
        # A filtered-out character can leave a gap in front of its punctuation.
        body = re.sub(r"\s+([.,!?:])", r"\1", body).strip()
        if len(body) < 2:
            continue
        if len(body) > limit:
            body = _shorten(body, limit)
        return body
    return ""


# Words no sentence should end on. Cutting at a word boundary is not enough:
# "THIS MACHINE IS A CREATURE, GROWING AND." is a worse line than anything in
# Brain.js, and a broken line is the one outcome the static lists rule out.
DANGLING = {
    "AND", "OR", "BUT", "SO", "THE", "A", "AN", "OF", "FOR", "TO", "IN", "ON",
    "AT", "BY", "WITH", "FROM", "THAT", "THIS", "WHICH", "IS", "ARE", "WAS",
    "WERE", "BE", "AS", "IT", "ITS", "MY", "YOUR", "HIS", "HER", "THEIR",
    "NOT", "INTO", "OVER", "UNDER", "THAN", "THEN", "WHEN", "WHILE", "IF",
}


def _shorten(body, limit):
    """Cut at a sentence if there is one; otherwise judge whether it survives.

    Returning "" is a legitimate answer. It means the model wrote something
    that will not fit, the caller keeps the static line it already said, and
    nobody sees a wizard stopping in the middle of a word.
    """
    cut = body[:limit + 1]
    for mark in (". ", "! ", "? "):
        at = cut.rfind(mark)
        if at >= limit // 3:
            return cut[:at + 1].strip()

    # No sentence ends inside the budget, so anything returned here would be a
    # fragment: "MEMORY IS 62 PERCENT CONSUMED, A MEAGER." Dropping trailing
    # function words is not enough, because "A MEAGER" ends on a real word and
    # still is not a sentence. The caller always has a static line to fall back
    # on, so the honest answer is to decline this one.
    words = cut.strip().split(" ")[:-1]
    while words and (words[-1] in DANGLING or words[-1].endswith(",")):
        words.pop()
    trimmed = " ".join(words).strip().rstrip(",-:")
    if not trimmed or trimmed[-1] not in ".!?":
        return ""
    return trimmed


# --- the model ---------------------------------------------------------------

def call(host, model, messages, timeout, predict, temperature=0.9):
    payload = json.dumps({
        "model": model,
        "messages": messages,
        "stream": False,
        # Reasoning models would otherwise spend the whole budget thinking
        # about a one-line joke and return an empty answer.
        "think": False,
        "keep_alive": "10m",
        "options": {
            "temperature": temperature,
            "top_p": 0.95,
            "num_predict": predict,
        },
    }).encode("utf-8")
    request = urllib.request.Request(
        "http://%s/api/chat" % host, data=payload,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = json.loads(response.read().decode("utf-8"))
    return str((body.get("message") or {}).get("content") or "")


def situation(ctx, facts, with_sense):
    """The wizard's own circumstances, in the order he would notice them."""
    lines = []
    where = str(ctx.get("surface") or "land")
    mood = str(ctx.get("mood") or "idle")
    if ctx.get("afloat"):
        lines.append("- you are out on the lake in your boat")
    elif where == "water":
        lines.append("- there is water under you")
    else:
        lines.append("- you are ashore")
    lines.append("- you are %s" % {
        "idle": "standing about", "walk": "walking", "cast": "casting",
        "sleep": "asleep in your bedroll", "row": "rowing",
        "held": "being held up by the scruff", "fall": "falling",
        "away": "inside somewhere", "board": "getting into the boat",
        "beach": "beaching the boat",
    }.get(mood, mood))
    if ctx.get("event"):
        lines.append("- on the water: %s" % ctx["event"])
    if ctx.get("land"):
        lines.append("- ashore: %s" % ctx["land"])
    if ctx.get("catNear"):
        lines.append("- Soot is right beside you")
    if ctx.get("catShape"):
        lines.append("- Soot is currently a %s, which is your fault"
                     % ctx["catShape"])
    elif ctx.get("hasCat"):
        lines.append("- Soot is off somewhere")
    if ctx.get("deathHere"):
        lines.append("- Death is here, petting the cat")
    if ctx.get("holding"):
        lines.append("- you are holding a %s" % ctx["holding"])
    if ctx.get("inventory"):
        lines.append("- in your pack: %s" % ", ".join(ctx["inventory"][:6]))
    if ctx.get("structures"):
        lines.append("- %s lit structures stand out on the horizon"
                     % ctx["structures"])
    if ctx.get("lights"):
        lines.append("- %s lamps burn along the bank" % ctx["lights"])
    if ctx.get("wallpaper"):
        lines.append("- the world you are in is called %s" % ctx["wallpaper"])
    if with_sense:
        lines.extend(sense_lines(facts))
    return "\n".join(lines)


BEATS = {
    "idle": "Say something unprompted. A remark, a complaint, an observation.",
    "poke": "The human has just prodded you. Respond to being prodded.",
    "crystal": "You have just put a hand on one of the humming crystals.",
    "lamp": "You have stopped by a lamp burning on the bank.",
    "sight": "You have spotted a lit structure in the distance and are setting"
             " off for it. Hedge about what it is.",
    "return": "You have just stepped back out of a portal, having let yourself"
              " into that place and had a look round. Say what it was like.",
    "fire": "You have conjured a campfire and sat down by it.",
    "water": "You are out on the lake. Remark on the water.",
    "fishing": "You are fishing off the side of the boat.",
    "tentacle": "Something very large has just surfaced alongside the boat.",
    "overboard": "You have just fallen in the lake and climbed back out.",
    "cat": "Soot wants something from you.",
    "study": "You are at your working table, deep in a book or a brew.",
    "brew": "Something in the glassware has just reacted. Possibly as"
            " intended.",
    "transform": "You have just turned Soot into something she is not"
                 " supposed to be. It was an accident.",
    "revert": "You have turned Soot back into a cat. She is not pleased.",
    "catappears": "Soot has turned up on your shore, which she had no way of"
                  " reaching. Cats do this.",
    "bedtime": "You are getting into your bedroll for the night.",
    "death": "Death is standing here making conversation. Answer him.",
    "find": "You have just picked something up off the ground.",
    "machine": "Remark on the state of the machine you live on, as if it were"
               " weather or livestock.",
}


def prompt_for(mode, ctx, facts, with_sense, count):
    scene = situation(ctx, facts, with_sense)
    if mode == "ask":
        question = clean(ctx.get("question"), 200) or "WELL?"
        return [
            {"role": "system", "content": PERSONA},
            {"role": "system", "content":
                "Where you are:\n%s\n\nThe human has spoken to you. Answer them"
                " in character, in at most twenty words -- one or two short"
                " sentences that finish. Be useful if they ask something real,"
                " but stay a wizard about it." % scene},
        ] + list(ctx.get("history") or []) + [
            {"role": "user", "content": question},
        ]

    if mode == "ambient":
        return [
            {"role": "system", "content": PERSONA},
            {"role": "user", "content":
                "Where you are:\n%s\n\nWrite %d different things you might say"
                " out loud right now, unprompted. One per line, nothing else --"
                " no numbering, no quotes, no blank lines. Each at most six"
                " words, and each a finished thought. Let at least one of them"
                " be about the state of the machine rather than the landscape."
                " Do not repeat yourself." % (scene, count)},
        ]

    beat = str(ctx.get("beat") or "idle")
    instruction = BEATS.get(beat, BEATS["idle"])
    return [
        {"role": "system", "content": PERSONA},
        {"role": "user", "content":
            "Where you are:\n%s\n\n%s\n\nOne line. At most six words."
            % (scene, instruction)},
    ]


# --- modes -------------------------------------------------------------------

def mode_check(args):
    try:
        request = urllib.request.Request("http://%s/api/tags" % args.host)
        with urllib.request.urlopen(request, timeout=args.timeout) as response:
            body = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError, socket.timeout) as err:
        print("no daemon at %s (%s)" % (args.host, err), file=sys.stderr)
        return 1
    names = [str(m.get("name", "")) for m in (body.get("models") or [])]
    # Ollama reports 'llama3.2:3b'; a bare 'llama3.2' should still match.
    wanted = args.model
    if wanted in names or any(n.split(":")[0] == wanted.split(":")[0]
                              for n in names):
        print(wanted)
        return 0
    print("model %s not pulled (have: %s)" % (wanted, ", ".join(names) or "none"),
          file=sys.stderr)
    return 1


def mode_sense(args):
    print(json.dumps(sense()))
    return 0


def mode_generate(args):
    try:
        ctx = json.loads(args.ctx) if args.ctx else {}
    except ValueError:
        ctx = {}
    if not isinstance(ctx, dict):
        ctx = {}

    facts = sense() if args.sense else {}
    count = max(1, min(8, args.count))
    # Some candidates will be declined for running long, so ask for spares.
    asked = count + 3 if args.mode == "ambient" else count
    messages = prompt_for(args.mode, ctx, facts, args.sense, asked)

    if args.mode == "ask":
        limit, predict = REPLY_CHARS, 64
    elif args.mode == "ambient":
        limit, predict = AMBIENT_CHARS, 24 * asked
    else:
        limit, predict = BEAT_CHARS, 32

    try:
        raw = call(args.host, args.model, messages, args.timeout, predict)
    except (urllib.error.URLError, OSError, ValueError, socket.timeout) as err:
        print("oracle: %s" % err, file=sys.stderr)
        return 1

    if args.mode == "ambient":
        seen = []
        for line in raw.split("\n"):
            said = clean(line, limit)
            if said and said not in seen:
                seen.append(said)
        if not seen:
            return 1
        print("\n".join(seen[:count]))
        return 0

    said = clean(raw, limit)
    if not said:
        return 1
    print(said)
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["check", "sense", "ambient", "beat", "ask"])
    parser.add_argument("--ctx", default="", help="situation, as JSON")
    parser.add_argument("--host", default=os.environ.get("WIZARD_OLLAMA_HOST",
                                                         DEFAULT_HOST))
    parser.add_argument("--model", default=os.environ.get("WIZARD_OLLAMA_MODEL",
                                                          DEFAULT_MODEL))
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--no-sense", dest="sense", action="store_false",
                        help="do not tell him anything about the machine")
    args = parser.parse_args(argv)

    if args.mode == "check":
        return mode_check(args)
    if args.mode == "sense":
        return mode_sense(args)
    return mode_generate(args)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
