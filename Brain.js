// What the wizard knows how to say, and how long he is willing to stand still.
.pragma library

var PHRASES = [
  "MIND THE CABLES.",
  "I SENSE UNSAVED WORK.",
  "A WIZARD IS NEVER LATE.",
  "THE ORB SAYS: MAYBE.",
  "MORE RAM, YOU SAY?",
  "I HAVE READ YOUR LOGS.",
  "SEGFAULTS FEAR ME.",
  "REBOOT? IN THIS ECONOMY?",
  "TABS. ALWAYS TABS.",
  "GIT COMMIT, MORTAL.",
  "THE KERNEL IS PLEASED.",
  "SOMETHING STIRS IN DMESG.",
  "BEWARE THE FULL DISK.",
  "YOUR PATH IS CURSED.",
  "ARCANE ENERGIES: NOMINAL.",
  "I LIVE IN THE LAYER SHELL.",
  "I CONJURED A COFFEE.",
  "SPEAK, FRIEND, AND TYPE.",
  "ALL GLORY TO THE COMPOSITOR.",
  "MY STAFF IS 2.5 GIGABITS.",
  "DO NOT DRAG ME. I MEAN IT.",
  "PURPLE IS LOAD-BEARING.",
  "SOOT! HEEL.",
  "THE CAT KNOWS THE WAY.",
  "MY NAME IS LANDIS, SINCE YOU ASK."
]

// At the working table.
var STUDY = [
  "THE THIRD LAW IS WRONG.",
  "MORE SULPHUR.",
  "IT SHOULD NOT BE GREEN.",
  "AH. A FOOTNOTE.",
  "WHO WROTE THIS? ...I DID.",
  "TWO PARTS MOONLIGHT.",
  "THE MARGIN IS ALL ARGUMENT."
]

var BREW_LUCK = [
  "IT WORKED. I AM AS SURPRISED AS YOU.",
  "THAT IS NOT THE COLOUR.",
  "ONE DAY. NOT TODAY.",
  "HARMLESS. PROBABLY."
]

var TRANSFORM = [
  "HOLD STILL, SOOT.",
  "HM. NOT QUITE.",
  "A DUCK. WHY A DUCK?",
  "I CAN FIX THIS.",
  "THAT WAS NOT THE PLAN.",
  "DO NOT LOOK AT ME LIKE THAT."
]

var REVERT = [
  "THERE. GOOD AS NEW.",
  "SHE IS NOT SPEAKING TO ME.",
  "NO HARM DONE.",
  "WE SHALL NEVER MENTION IT."
]

// Things that happen ashore.
var CRYSTAL = [
  "IT HUMS.",
  "STILL WARM.",
  "THE LAKE GREW THESE.",
  "DO NOT TOUCH. ...TOO LATE.",
  "OLDER THAN THE CASTLE.",
  "IT ANSWERED."
]

var FIRESIDE = [
  "THAT IS BETTER.",
  "SIT, SOOT.",
  "MIND THE SPARKS.",
  "NO STORIES TONIGHT.",
  "JUST FIVE MINUTES."
]

var CAT_WANTS = [
  "YES, YES. HELLO.",
  "SHE WANTS SOMETHING.",
  "ALL RIGHT. ONE SCRATCH.",
  "YOU ARE STANDING ON MY FOOT.",
  "I AM NOT MADE OF FISH."
]

var CAT_APPEARS = [
  "HOW DO YOU DO THAT?",
  "THERE YOU ARE.",
  "I DID NOT SEE YOU FOLLOW.",
  "YOU WERE ON THE OTHER SIDE.",
  "I SHALL STOP ASKING."
]

var BEDTIME = ["GOODNIGHT, SOOT.", "FIVE MINUTES.", "MIND MY HAT."]

// Things that happen out on the lake.
var TENTACLE = [
  "SOMETHING IS DOWN THERE.",
  "NOT TODAY, THANK YOU.",
  "IT WAVED. I WAVED BACK.",
  "WE HAVE AN ARRANGEMENT.",
  "ROW FASTER."
]

var FISHING = [
  "PATIENCE.",
  "THEY ARE BITING.",
  "ONE MORE CAST.",
  "THIS IS THE SPOT."
]

var FISHING_LUCK = ["GOT ONE!", "NOTHING. AS USUAL.", "IT WAS THIS BIG.", "A BOOT. LOVELY."]

var OVERBOARD = [
  "I MEANT TO DO THAT.",
  "COLD! COLD!",
  "MY HAT! ...OH. GOOD.",
  "NOBODY SAW THAT.",
  "THE LAKE STARTED IT."
]

var LAKE_ODD = ["SHOW OFF.", "THAT WAS LARGE.", "DID YOU SEE IT?", "HMM."]

var GREETINGS = ["I AM SUMMONED.", "AT LAST.", "YOU RANG?", "LANDIS, AT YOUR SERVICE."]

// Death, who in the usual way of things speaks in small capitals. The font
// only has capitals, so his bubble is inverted instead -- pale on dark.
var DEATH_LINES = [
  "HELLO LANDIS.",
  "SOOT. YOU ARE LOOKING SLEEK.",
  "I LIKE CATS.",
  "NO. NOT TODAY. NOT FOR EITHER OF YOU.",
  "I CANNOT STOP. THERE IS A LIST.",
  "DO NOT GET UP.",
  "A GOOD EVENING FOR IT.",
  "SHE REMEMBERS ME.",
  "CATS ARE THE ONLY THING I ENVY.",
  "THE FISH WAS A KIND THOUGHT."
]

var LANDIS_TO_DEATH = [
  "AH. YOU AGAIN.",
  "SHE HAS MISSED YOU.",
  "TEA? NO. OF COURSE NOT.",
  "YOU SPOIL THAT CAT.",
  "NOT TODAY, I HOPE?"
]
var FAREWELLS = ["FAREWELL!", "POOF.", "UNTIL NEXT TIME."]
var GRUMBLES = ["PUT ME DOWN!", "UNHAND ME!", "WHEE!"]

// What he says about a place he has read off the wallpaper. The analysis
// knows a cluster of lights and its rough shape -- never that it is a castle --
// so every one of these hedges. He is guessing, and says so.
var SIGHTS = {
  "tower": ["A TOWER, OR SO IT SEEMS.", "SOMETHING TALL AND LIT.", "A SPIRE. PROBABLY."],
  "keep": ["A KEEP, I THINK.", "WALLS AND WINDOWS.", "SOMEONE IS HOME."],
  "hall": ["LIGHTS ON THE HORIZON.", "A HALL, OR A SUNSET.", "SOMETHING GLOWS THERE."]
}

var RETURNS = [
  "THE STAIRS WENT DOWN A LONG WAY.",
  "NOBODY ANSWERED THE DOOR.",
  "I LET MYSELF IN.",
  "DUSTY. VERY DUSTY.",
  "THEY KEPT THE GOOD BOOKS.",
  "I SHALL NOT GO BACK."
]

var WATER = [
  "THE WATER IS COLD.",
  "ROW, ROW.",
  "DEEP HERE.",
  "SOMETHING MOVED BELOW.",
  "I NEVER LEARNED TO SWIM."
]

var LAMPS = [
  "A LIGHT. HOW CIVIL.",
  "STILL BURNING.",
  "WHO LIT THIS?",
  "WARM."
]

var USES = {
  "fish": "SUPPER.",
  "mushroom": "PROBABLY EDIBLE.",
  "lantern": "LET THERE BE LIGHT.",
  "book": "IT IS MOSTLY FOOTNOTES.",
  "key": "IT FITS NOTHING YET.",
  "crystal": "STILL HUMMING."
}

var FINDS = {
  "fish": "A FISH!",
  "mushroom": "MUSHROOM. MINE NOW.",
  "crystal": "A SHARD. IT SINGS.",
  "key": "A KEY. TO WHAT?",
  "book": "A BOOK. UNREAD.",
  "lantern": "A LANTERN, STILL LIT."
}

function sightFor(shape) {
  var list = SIGHTS[shape] || SIGHTS["keep"]
  return list[Math.floor(Math.random() * list.length)]
}

function pick(list, avoid) {
  if (list.length === 0)
    return ""
  if (list.length === 1)
    return list[0]
  var choice = avoid
  while (choice === avoid)
    choice = list[Math.floor(Math.random() * list.length)]
  return choice
}

// Greedy wrap on whole words. A word longer than the limit gets its own line
// rather than being cut in half, which keeps the bubble honest about its width.
function wrap(text, maxChars) {
  var words = String(text || "").split(" ")
  var lines = []
  var line = ""
  for (var i = 0; i < words.length; i++) {
    var next = line === "" ? words[i] : line + " " + words[i]
    if (next.length <= maxChars) {
      line = next
    } else {
      if (line !== "")
        lines.push(line)
      line = words[i]
    }
  }
  if (line !== "")
    lines.push(line)
  return lines
}

function between(min, max) {
  return min + Math.random() * (max - min)
}
