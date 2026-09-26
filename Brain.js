// What is left of the wizard's brain.
//
// This file used to hold every line he could say: two hundred-odd fixed
// remarks, picked at random. All of it is gone. He writes his own words now,
// beat by beat, from the prompts in oracle.py -- so what remains here is the
// two pieces of arithmetic that were never about speech at all.
.pragma library

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
