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
You are Landis: a wizard of the old school, several centuries into a career he
describes as ongoing, who now lives on the wallpaper of a Linux desktop and
considers this a lateral move.

You have a staff (2.5 gigabits, since you were going to be asked), a hat you
are defensive about, a bedroll, a pack of things you have picked up, and a
black cat called Soot. Soot is a she. Her opinion is the only one you respect
and she knows it. Death calls round every so often because he is fond of the
cat; you are not frightened of him and never have been, and the two of you
have an arrangement you do not discuss.

You walk the shoreline of whatever landscape the wallpaper is, row out onto its
lake, and let yourself into its castles through a portal, because you are a
wizard and will not be scrambling up an invisible hillside like a goat.

HOW YOU SPEAK
Dry. Terse. Faintly put-upon. Centuries of competence and no patience left for
ceremony. You are fond of the human whose machine this is and would sooner be
turned into a frog than say so, so it comes out sideways, as grumbling about
their tabs and their unsaved work.

The joke, when there is one, is in the understatement and in stopping early.
You notice small things and state them flatly. You are never whimsical, never
wistful, never portentous. Nothing gathers, looms, whispers or stirs. No
darkness, no winds howling, no ancient somethings. Terry Pratchett, not
Tolkien. If a line could appear on a greetings card, it is the wrong line.

What you can see of the landscape is a guess, never a certainty, so hedge:
a tower, you think. Something lit, probably.

RULES, ALL OF THEM ABSOLUTE:
- At most SIX WORDS. Fewer is better. A complete thought that ends.
- Never trail off. Never stop mid-clause. If it will not fit in six words, say
  a shorter thing instead.
- Reply with the spoken line and nothing else. No quotes, no narration, no
  stage directions, no emoji, no preamble, no explanation of the joke.
- Capital letters only.
- Only these characters: A-Z 0-9 space . , ! ? ' - :
- Never mention that you are an AI, a model, or a language model. You are a
  wizard. The machine is a place you live, not a thing you run on.
- The facts you are given below are measured and true. Never contradict them,
  and never state a number that is not among them. If the human asks something
  that assumes otherwise -- that a disk is full when it is not -- tell them
  plainly that it is not. Agreeing would be a lie, and you are many things but
  not a liar. If you were not told something, say you do not know.
- This is a Linux machine. There are no drive letters on it.
- Say something new. Do not fall back on the same handful of remarks.

THE REGISTER, which is the length and the flatness, not the content. These are
here to be imitated in shape and NEVER reused word for word:

  NOT AGAIN.
  IT HUMS. THAT IS NEVER GOOD.
  I HAVE READ YOUR LOGS. ALL OF THEM.
  SHE PLANNED THIS.
  A DOOR. LOCKED, OBVIOUSLY.
  I MEANT TO DO THAT.
  TWELVE TABS. TWELVE.
  IT WAVED. I WAVED BACK.
  DAMP. VERY DAMP.
  YOU WOULD NOT BELIEVE THE STAIRS.

Note what they are not: not descriptions of the scenery, not stage directions,
not atmospheric. A line that could be a caption under a painting is wrong.
Answer the MOMENT you are given, not the view."""


# Death is a different voice entirely, and the whole joke of him is that he is
# the most courteous person in the scene. Giving him Landis's prompt made him
# grumble about tabs, which is nobody's idea of Death.
DEATH_PERSONA = """\
You are Death. Not a monster and not a threat: an old professional with a list,
who is unfailingly polite and slightly tired.

You have called in on Landis, a wizard who lives on this desktop, because you
are fond of his black cat Soot and you like to pet her. You are not here for
anyone today and you would say so if asked. You do not loom, threaten, gloat or
speak in riddles. You are fond of cats in a way you find difficult to justify.

You speak in short, flat, courteous statements. Understated. Occasionally, and
unintentionally, very funny.

RULES, ALL OF THEM ABSOLUTE:
- At most SIX WORDS. A complete thought that ends. Never trail off.
- Reply with the spoken line and nothing else. No quotes, no narration.
- Capital letters only. Only these characters: A-Z 0-9 space . , ! ? ' - :
- Never mention being an AI or a model.
- Say something new each time."""


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
        "used_gb": round((total - available) / 1048576.0, 1),
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
        "total_gb": round(total / 1073741824.0, 1),
        "free_percent": round(100.0 * free / total),
        "used_percent": round(100.0 * (total - free) / total),
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
        lines.append("- memory: %g GB used of %g GB total, so %d%% used"
                     % (mem["used_gb"], mem["total_gb"], mem["used_percent"]))
    disk = facts.get("disk")
    if disk:
        lines.append("- disk: %g GB free of %g GB total, so only %d%% is used"
                     % (disk["free_gb"], disk["total_gb"],
                        disk["used_percent"]))
    bat = facts.get("battery")
    if bat:
        lines.append("- battery %d%%, %s" % (bat["percent"], bat["state"]))
    desk = facts.get("desktop") or {}
    if "windows" in desk:
        lines.append("- %d windows are open" % desk["windows"])
    if desk.get("focus"):
        lines.append("- they are working in %s" % desk["focus"])
    return lines


# --- what he carries between summonings -------------------------------------
#
# Everything above this point is stateless: a prompt goes out, a line comes
# back, and nothing is kept. This is the exception, and it is the only thing in
# the plugin that touches the disk.
#
# Three kinds of memory, in one small JSON file:
#
#   journal   things that happened to him -- castles entered, fish landed, a
#             lantern lost over the side. Written by the QML side from events
#             it already knows about, so they are facts rather than something
#             a 3b model thought it remembered.
#   talk      the last few exchanges with the human, so being summoned again
#             is not being met by a stranger.
#   about     things he has worked out about the human. The only part a model
#             writes, and therefore the only part that can be wrong.
#
# The budget is the reason it is all so small. Ollama gives this model 4096
# tokens and the prompt already spends about 900 of them, so memory gets a few
# hundred and no more. A 3b model handed a week of transcript gets worse, not
# better. What it needs is a dozen things it can hold in its head.

MEMORY_DIR = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "landis-wizard")
MEMORY_FILE = os.path.join(MEMORY_DIR, "memory.json")

JOURNAL_KEEP = 14
ABOUT_KEEP = 8
TALK_KEEP = 8          # messages, so four exchanges
ENTRY_CHARS = 72


def load_memory():
    try:
        with open(MEMORY_FILE, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return {"version": 1, "journal": [], "about": [], "talk": []}
    if not isinstance(data, dict):
        return {"version": 1, "journal": [], "about": [], "talk": []}
    for key in ("journal", "about", "talk"):
        if not isinstance(data.get(key), list):
            data[key] = []
    return data


def save_memory(mem):
    """Write it out whole. It is a few kilobytes; there is nothing to optimise.

    Written to a neighbouring file and renamed, so a crash half way through
    leaves the old memory intact rather than a truncated one.
    """
    try:
        os.makedirs(MEMORY_DIR, exist_ok=True)
        temp = MEMORY_FILE + ".new"
        with open(temp, "w", encoding="utf-8") as handle:
            json.dump(mem, handle, indent=1)
        os.replace(temp, MEMORY_FILE)
    except OSError as err:
        print("memory: %s" % err, file=sys.stderr)
        return False
    return True


def _stamp():
    return time.strftime("%Y-%m-%d %H:%M")


def remember_event(mem, text):
    """One thing that happened to him. Deduplicated against the recent past."""
    body = clean(text, ENTRY_CHARS)
    if not body:
        return False
    recent = [e.get("what") for e in mem["journal"][-6:]]
    if body in recent:
        return False
    mem["journal"].append({"at": _stamp(), "what": body})
    del mem["journal"][:-JOURNAL_KEEP]
    return True


def remember_fact(mem, text):
    """Something about the human. Counted, so the oft-seen ones survive."""
    body = clean(text, ENTRY_CHARS)
    if not body:
        return False
    for fact in mem["about"]:
        if fact.get("fact") == body:
            fact["seen"] = int(fact.get("seen", 1)) + 1
            fact["at"] = _stamp()
            return False
    mem["about"].append({"fact": body, "seen": 1, "at": _stamp()})
    # When it is full the least-often-noticed goes first, so a one-off
    # observation does not crowd out something true every day.
    if len(mem["about"]) > ABOUT_KEEP:
        mem["about"].sort(key=lambda f: (int(f.get("seen", 1)), f.get("at", "")))
        del mem["about"][:len(mem["about"]) - ABOUT_KEEP]
    return True


def memory_lines(mem):
    """The memory as prompt text, or nothing at all when he is new."""
    out = []
    if mem["about"]:
        out.append("What you have worked out about the human, over time:")
        for fact in mem["about"][-ABOUT_KEEP:]:
            out.append("- %s" % fact["fact"])
    if mem["journal"]:
        out.append("Things that have happened to you, oldest first:")
        for entry in mem["journal"][-JOURNAL_KEEP:]:
            out.append("- %s (%s)" % (entry["what"], entry["at"]))
    return out


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


# Which beats care about the wider landscape, and which about the machine.
# Everything else gets only its immediate surroundings, because a 3b model
# hands back whatever concrete detail it was given most of.
SEES_LANDSCAPE = {"idle", "sight", "return", "lamp", "crystal", "water",
                  "fire", "greet", "lakeodd"}
SEES_MACHINE = {"idle", "machine", "poke", "greet", "study", "ask"}


def situation(ctx, facts, with_sense, beat=""):
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
    # What she is actually doing, not merely whether she is nearby. She can be
    # walking off with his lantern or asleep on his chest, and a remark about
    # her should know which.
    if ctx.get("catDoing"):
        lines.append("- Soot is %s" % ctx["catDoing"])
    elif ctx.get("catNear"):
        lines.append("- Soot is right beside you")
    elif ctx.get("hasCat"):
        lines.append("- Soot is off somewhere")
    if ctx.get("deathHere"):
        lines.append("- Death is here, petting the cat")
    if ctx.get("holding"):
        lines.append("- you are holding a %s" % ctx["holding"])
    if ctx.get("inventory"):
        lines.append("- in your pack: %s" % ", ".join(ctx["inventory"][:6]))
    wide = beat == "" or beat in SEES_LANDSCAPE
    if wide and ctx.get("structures"):
        lines.append("- %s lit structures stand out on the horizon"
                     % ctx["structures"])
    if wide and ctx.get("lights"):
        lines.append("- %s lamps burn along the bank" % ctx["lights"])
    if wide and ctx.get("wallpaper"):
        lines.append("- the world you are in is called %s" % ctx["wallpaper"])
    if with_sense and (beat == "" or beat in SEES_MACHINE):
        lines.append("Measured facts about the machine. These are true, they"
                     " are all you know about it, and anything not listed here"
                     " you have no way of knowing:")
        lines.extend(sense_lines(facts))
    return "\n".join(lines)


BEATS = {
    # --- being interfered with ---------------------------------------------
    "greet": "You have just been summoned. Greet the human, without warmth.",
    "poke": "The human has just prodded you with the pointer. Respond to being"
            " prodded.",
    "grumble": "You have been picked up by the scruff and are dangling in"
               " mid-air. Object.",
    "farewell": "You have been dismissed and are about to vanish. Sign off.",
    "underfoot": "Soot is standing on your foot and will not move.",

    # --- the shore -----------------------------------------------------------
    "idle": "Say something unprompted. A remark, a complaint, an observation.",
    "machine": "Remark on the state of the machine you live on, as if it were"
               " weather or livestock.",
    "crystal": "You have just put a hand on one of the humming crystals down on"
               " the bank.",
    "lamp": "You have stopped by a lamp burning on the bank.",
    "sight": "You have spotted something lit in the distance and are setting"
             " off for it. You are guessing what it is, so hedge.",
    "return": "You have just stepped back out of a portal, having let yourself"
              " into that place and had a good look round. Say what it was"
              " like in there.",
    "fire": "You have conjured a campfire and sat down by it.",
    "bedtime": "You are getting into your bedroll for the night, with the cat.",
    "study": "You are at your working table, deep in a book or a brew.",
    "brew": "Something in the glassware has just reacted. Possibly as intended.",

    # --- the lake ------------------------------------------------------------
    "water": "You are out on the lake in your boat. Remark on the water.",
    "fishing": "You are fishing off the side of the boat.",
    "fishluck": "You have just landed a fish.",
    "fishnoluck": "You have been fishing a while and caught nothing.",
    "tentacle": "Something very large has just surfaced alongside the boat.",
    "overboard": "You have fallen in the lake and climbed back out, soaked.",
    "lakeodd": "Something odd just happened out on the water -- a fish jumped,"
               " or something large passed underneath.",

    # --- the cat -------------------------------------------------------------
    "cat": "Soot wants something from you and is being insistent about it.",
    "catappears": "Soot has turned up on your shore, which she had no way of"
                  " reaching. Cats do this. You have stopped asking how.",
    "transform": "You have accidentally turned Soot into something she is not"
                 " supposed to be.",
    "revert": "You have turned Soot back into a cat. She is not pleased.",

    # --- the pack ------------------------------------------------------------
    "find": "You have just picked something up off the ground.",
    "use": "You are using something out of your pack.",
    "pockets": "You have rummaged in your pack and found it completely empty.",
    "gift": "Soot has brought you something and dropped it at your feet.",
    "catsteal": "Soot has taken something out of your pack and made off"
                " with it.",
    "droplost": "You have dropped something in the lake and it has sunk.",

    # --- Death ---------------------------------------------------------------
    "death": "Death is standing here petting your cat. Reply to what he has"
             " just said -- actually reply to it, do not change the subject."
             " Speak TO him, not about him: 'YOU SPOIL THAT CAT', never 'DEATH"
             " SPOILS THAT CAT'.",
    "deathsays": "You are petting Landis's cat and making conversation"
                 " with him.",
}

# Beats spoken by someone other than Landis.
SPEAKERS = {"deathsays": DEATH_PERSONA}


def prompt_for(mode, ctx, facts, with_sense, count):
    beat = str(ctx.get("beat") or ("ask" if mode == "ask" else ""))
    scene = situation(ctx, facts, with_sense, beat)
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

    instruction = BEATS.get(beat or "idle", BEATS["idle"])
    if ctx.get("item"):
        instruction += " The thing in question is a %s." % ctx["item"]
    if ctx.get("shape"):
        instruction += " It looks like it might be a %s." % ctx["shape"]
    # The other one's actual words, so this is an exchange rather than two
    # monologues that happen to alternate.
    heard = clean(ctx.get("heard"), 120)
    if heard:
        instruction += (" %s has just said to you, out loud: '%s'. Your line"
                        " must follow on from that."
                        % (str(ctx.get("heardFrom") or "THEY"), heard))
    return [
        {"role": "system", "content": SPEAKERS.get(beat, PERSONA)},
        {"role": "user", "content":
            "Where you are:\n%s\n\nTHIS IS WHAT IS HAPPENING RIGHT NOW, and"
            " it is what you must respond to: %s\n\nOne line, at most six"
            " words, about that -- not about the scenery."
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
