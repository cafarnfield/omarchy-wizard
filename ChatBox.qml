import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "Sprites.js" as Sprites

// Somewhere for his words to stay.
//
// The speech bubble is a three-second thing on a sprite five characters wide.
// That is right for "MIND THE CABLES." and quite wrong for an answer to a
// question, which is gone before it has been read. This keeps every line he
// says, and gives you somewhere to type back.
//
// It is a second layer surface, separate from the wizard's own: his sits on
// `bottom` with no keyboard focus at all, because he is part of the wallpaper.
// This one has to be in front of your windows and has to accept typing, which
// are the two things that surface must never do.
PanelWindow {
  id: box

  // --- contract with the wizard --------------------------------------------
  property var entries: []             // [{who, text, at}]
  property bool thinking: false
  property bool oracleReady: false
  property string oracleDetail: ""

  // Which Wayland layer to sit on. `bottom` puts it on the wallpaper beside
  // the wizard, behind every window, out of the way of your work -- but a
  // bottom surface cannot be given keyboard focus, so there is nothing to type
  // into and the field is hidden. `top` and `overlay` float it in front and
  // can be typed at.
  property string layerName: "bottom"
  readonly property bool canType: layerName === "top" || layerName === "overlay"

  signal submitted(string text)
  signal dismissed()

  // --- the wizard's own colours, so it reads as part of him ----------------
  readonly property color inkBright: Sprites.PALETTE["W"]   // #e9e3ff
  readonly property color inkDim: Sprites.PALETTE["G"]      // #a8a2cd
  readonly property color shell: Sprites.PALETTE["2"]       // #161320
  readonly property color panel: Sprites.PALETTE["X"]       // #26203a
  readonly property color edge: Sprites.PALETTE["D"]        // #4a3a73
  readonly property color him: Sprites.PALETTE["C"]         // #bb9af7
  readonly property color you: Sprites.PALETTE["Y"]         // #ffd68a
  readonly property color reaper: Sprites.PALETTE["1"]      // #d8d4c0

  function colorFor(who) {
    if (who === "you")
      return you
    if (who === "death")
      return reaper
    return him
  }

  function labelFor(who) {
    if (who === "you")
      return "YOU"
    if (who === "death")
      return "DEATH"
    return "LANDIS"
  }

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "landis-wizard-chat"
  WlrLayershell.layer: box.layerName === "top" ? WlrLayer.Top
    : (box.layerName === "overlay" ? WlrLayer.Overlay : WlrLayer.Bottom)
  // OnDemand rather than Exclusive: it can be typed into when you click it,
  // but it never holds your keyboard hostage while it sits there. A transcript
  // you must close before you can use your editor again is worse than no
  // transcript. On `bottom` the compositor will not focus it at all, so it
  // does not ask.
  WlrLayershell.keyboardFocus: box.canType ? WlrKeyboardFocus.OnDemand
                                           : WlrKeyboardFocus.None

  anchors {
    right: true
    top: true
  }
  margins {
    right: 16
    top: 16
  }
  implicitWidth: 430
  implicitHeight: 560

  function focusInput() {
    if (canType)
      entry.forceActiveFocus()
  }

  Rectangle {
    anchors.fill: parent
    color: box.shell
    border.color: box.edge
    border.width: 2
    radius: 2

    // A second inset line, the way his speech bubble is drawn: border, gap,
    // content. It is the cheapest way to make a plain rectangle look like it
    // belongs to a pixel-art wizard.
    Rectangle {
      anchors.fill: parent
      anchors.margins: 3
      color: "transparent"
      border.color: Qt.rgba(box.edge.r, box.edge.g, box.edge.b, 0.45)
      border.width: 1
    }

    // --- header ------------------------------------------------------------
    Item {
      id: header
      anchors { top: parent.top; left: parent.left; right: parent.right }
      anchors.margins: 10
      height: 26

      Rectangle {
        id: lamp
        anchors.verticalCenter: parent.verticalCenter
        width: 8
        height: 8
        radius: 4
        color: box.oracleReady ? Sprites.PALETTE["V"] : Sprites.PALETTE["N"]

        // He is thinking: the lamp breathes rather than sitting there lit.
        SequentialAnimation on opacity {
          running: box.thinking
          loops: Animation.Infinite
          // An animation that stops mid-cycle leaves the lamp part-faded, so
          // it is put back to full brightness when he stops thinking.
          onStopped: lamp.opacity = 1
          NumberAnimation { to: 0.25; duration: 500 }
          NumberAnimation { to: 1.0; duration: 500 }
        }
      }

      Text {
        anchors { left: lamp.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
        text: "LANDIS"
        color: box.inkBright
        font.pixelSize: 13
        font.letterSpacing: 2
        font.bold: true
      }

      Text {
        anchors { right: shut.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        color: box.inkDim
        font.pixelSize: 11
        text: box.thinking ? "thinking"
          : (!box.oracleReady ? (box.oracleDetail !== "" ? "no oracle" : "listening")
                              : (box.canType ? "" : "read only"))
      }

      Text {
        id: shut
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: "×"
        color: shutArea.containsMouse ? box.inkBright : box.inkDim
        font.pixelSize: 20

        MouseArea {
          id: shutArea
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          onClicked: box.dismissed()
        }
      }
    }

    Rectangle {
      id: rule
      anchors { top: header.bottom; left: parent.left; right: parent.right }
      anchors.margins: 8
      anchors.topMargin: 4
      height: 1
      color: box.edge
    }

    // --- the transcript ------------------------------------------------------
    Item {
      id: logArea
      anchors {
        top: rule.bottom
        left: parent.left
        right: parent.right
        bottom: box.canType ? footer.top : parent.bottom
        margins: 10
      }

    ListView {
      id: log
      // Sit on the floor and grow upwards, the way a conversation does. A
      // plain fill would leave the first few lines stranded at the top with
      // half a panel of nothing under them. Not circular: contentHeight comes
      // from the delegates, which size on width.
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: Math.min(parent.height, contentHeight)
      clip: true
      spacing: 9
      model: box.entries
      boundsBehavior: Flickable.StopAtBounds

      // New lines arrive at the bottom, and the bottom is where you are
      // reading, so follow it -- unless you have scrolled up to read something
      // older, in which case leave you where you are.
      property bool pinned: true
      onContentYChanged: pinned = (contentHeight - contentY - height) < 40
      onCountChanged: if (pinned) positionViewAtEnd()
      Component.onCompleted: positionViewAtEnd()

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
          implicitWidth: 4
          radius: 2
          color: box.edge
        }
      }

      delegate: Column {
        required property var modelData
        width: log.width - 8
        spacing: 2

        Row {
          spacing: 6
          Text {
            text: box.labelFor(modelData.who)
            color: box.colorFor(modelData.who)
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
          }
          Text {
            text: modelData.at
            color: Qt.rgba(box.inkDim.r, box.inkDim.g, box.inkDim.b, 0.55)
            font.pixelSize: 10
          }
        }

        Text {
          width: parent.width
          text: modelData.text
          color: modelData.who === "you" ? box.inkDim : box.inkBright
          font.pixelSize: 14
          wrapMode: Text.WordWrap
          lineHeight: 1.25
        }
      }
    }

    }

    // --- saying something back -----------------------------------------------
    Rectangle {
      id: footer
      visible: box.canType
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      anchors.margins: 8
      height: 38
      color: box.panel
      border.color: entry.activeFocus ? box.him : box.edge
      border.width: 1
      radius: 2

      TextField {
        id: entry
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        color: box.inkBright
        font.pixelSize: 14
        placeholderText: box.oracleReady ? "Ask him something…"
                                         : "No model running — he will not answer"
        placeholderTextColor: Qt.rgba(box.inkDim.r, box.inkDim.g, box.inkDim.b, 0.5)
        enabled: box.oracleReady && !box.thinking
        background: null

        onAccepted: {
          const said = text.trim()
          if (said === "")
            return
          text = ""
          box.submitted(said)
        }

        Keys.onEscapePressed: box.dismissed()
      }
    }
  }
}
