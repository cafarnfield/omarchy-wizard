import QtQuick
import Quickshell

// The chat box as an ordinary window.
//
// Layer surfaces are either always in front of your windows or always behind
// them; there is no middle setting, and the middle is what you usually want.
// This is a normal toplevel instead: you click it and type into it, and it
// drops behind whatever you focus next, like any other application.
//
// The cost of being an ordinary window is being treated as one. On a tiling
// layout the compositor will tile it unless told otherwise, and it appears in
// the window list -- see the `landis-wizard-chat` rule in the README.
FloatingWindow {
  id: win

  property alias entries: panel.entries
  property alias thinking: panel.thinking
  property alias oracleReady: panel.oracleReady
  property alias oracleDetail: panel.oracleDetail

  signal submitted(string text)
  signal dismissed()

  function focusInput() {
    panel.focusInput()
  }

  title: "Landis"
  color: panel.shell
  implicitWidth: 430
  implicitHeight: 560
  minimumSize: Qt.size(300, 260)

  ChatPanel {
    id: panel
    anchors.fill: parent
    canType: true
    onSubmitted: (text) => win.submitted(text)
    onDismissed: win.dismissed()
  }
}
