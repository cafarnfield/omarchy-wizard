import QtQuick
import QtQuick.Controls
import "Sprites.js" as Sprites

// The chat box itself, with no opinion about what kind of window it lives in.
//
// It is hosted either by ChatBox.qml, a Wayland layer surface that sits on the
// wallpaper or above every window, or by ChatWindow.qml, an ordinary window
// that behaves like any other application. The two want opposite things and
// neither belongs in here.
Item {
  id: panel

  // --- contract with the host ----------------------------------------------
  property var entries: []             // [{who, text, at}]
  property bool thinking: false
  property bool oracleReady: false
  property string oracleDetail: ""
  property bool canType: true          // false where the surface cannot focus

  signal submitted(string text)
  signal dismissed()

  // --- the wizard's own colours, so it reads as part of him ----------------
  readonly property color inkBright: Sprites.PALETTE["W"]   // #e9e3ff
  readonly property color inkDim: Sprites.PALETTE["G"]      // #a8a2cd
  readonly property color shell: Sprites.PALETTE["2"]       // #161320
  readonly property color panelBg: Sprites.PALETTE["X"]     // #26203a
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

  function focusInput() {
    if (canType)
      entry.forceActiveFocus()
  }

  Rectangle {
    anchors.fill: parent
    color: panel.shell
    border.color: panel.edge
    border.width: 2
    radius: 2

    // A second inset line, the way his speech bubble is drawn: border, gap,
    // content. It is the cheapest way to make a plain rectangle look like it
    // belongs to a pixel-art wizard.
    Rectangle {
      anchors.fill: parent
      anchors.margins: 3
      color: "transparent"
      border.color: Qt.rgba(panel.edge.r, panel.edge.g, panel.edge.b, 0.45)
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
        color: panel.oracleReady ? Sprites.PALETTE["V"] : Sprites.PALETTE["N"]

        // He is thinking: the lamp breathes rather than sitting there lit.
        SequentialAnimation on opacity {
          running: panel.thinking
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
        color: panel.inkBright
        font.pixelSize: 13
        font.letterSpacing: 2
        font.bold: true
      }

      Text {
        anchors { right: shut.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        color: panel.inkDim
        font.pixelSize: 11
        text: panel.thinking ? "thinking"
          : (!panel.oracleReady ? (panel.oracleDetail !== "" ? "no oracle" : "listening")
                              : (panel.canType ? "" : "read only"))
      }

      Text {
        id: shut
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: "×"
        color: shutArea.containsMouse ? panel.inkBright : panel.inkDim
        font.pixelSize: 20

        MouseArea {
          id: shutArea
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          onClicked: panel.dismissed()
        }
      }
    }

    Rectangle {
      id: rule
      anchors { top: header.bottom; left: parent.left; right: parent.right }
      anchors.margins: 8
      anchors.topMargin: 4
      height: 1
      color: panel.edge
    }

    // --- the transcript ------------------------------------------------------
    ListView {
      id: log
      anchors {
        top: rule.bottom
        left: parent.left
        right: parent.right
        bottom: panel.canType ? footer.top : parent.bottom
        margins: 10
      }
      clip: true
      spacing: 9
      boundsBehavior: Flickable.StopAtBounds

      // Laid out bottom to top, over a reversed list, so the newest line is at
      // index 0 and sits on the floor of the panel. Nothing has to scroll: a
      // new line simply appears where you are already looking, and short
      // conversations rest at the bottom instead of floating at the top.
      //
      // The previous version chased the end with positionViewAtEnd() and was
      // always a step behind, because these delegates word-wrap: their heights
      // are not known at the moment the count changes, so it scrolled to where
      // the content used to end. Laying it out this way removes the problem
      // rather than trying to time around it.
      verticalLayoutDirection: ListView.BottomToTop
      model: panel.entries.slice().reverse()

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
          implicitWidth: 4
          radius: 2
          color: panel.edge
        }
      }

      delegate: Column {
        required property var modelData
        width: log.width - 8
        spacing: 2

        Row {
          spacing: 6
          Text {
            text: panel.labelFor(modelData.who)
            color: panel.colorFor(modelData.who)
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1
          }
          Text {
            text: modelData.at
            color: Qt.rgba(panel.inkDim.r, panel.inkDim.g, panel.inkDim.b, 0.55)
            font.pixelSize: 10
          }
        }

        Text {
          width: parent.width
          text: modelData.text
          color: modelData.who === "you" ? panel.inkDim : panel.inkBright
          font.pixelSize: 14
          wrapMode: Text.WordWrap
          lineHeight: 1.25
        }
      }
    }

    // --- saying something back -----------------------------------------------
    Rectangle {
      id: footer
      visible: panel.canType
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      anchors.margins: 8
      height: 38
      color: panel.panelBg
      border.color: entry.activeFocus ? panel.him : panel.edge
      border.width: 1
      radius: 2

      TextField {
        id: entry
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        color: panel.inkBright
        font.pixelSize: 14
        placeholderText: panel.oracleReady ? "Ask him something…"
                                         : "No model running — he will not answer"
        placeholderTextColor: Qt.rgba(panel.inkDim.r, panel.inkDim.g, panel.inkDim.b, 0.5)
        enabled: panel.oracleReady && !panel.thinking
        background: null

        onAccepted: {
          const said = text.trim()
          if (said === "")
            return
          text = ""
          panel.submitted(said)
        }

        Keys.onEscapePressed: panel.dismissed()
      }
    }
  }
}
