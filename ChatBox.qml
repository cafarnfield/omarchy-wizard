import QtQuick
import Quickshell
import Quickshell.Wayland

// The chat box as a Wayland layer surface.
//
// `bottom` puts it on the wallpaper beside the wizard, behind every window and
// out of the way of your work -- but a bottom surface cannot be given keyboard
// focus, so there is nothing to type into and the field hides itself. `top`
// and `overlay` float it in front of everything and can be typed at.
//
// Layer shell has four layers and no notion of ordinary stacking, so there is
// no setting here that means "behave like a window". That is ChatWindow.qml.
PanelWindow {
  id: box

  property alias entries: panel.entries
  property alias thinking: panel.thinking
  property alias oracleReady: panel.oracleReady
  property alias oracleDetail: panel.oracleDetail

  property string layerName: "bottom"
  readonly property bool canType: layerName === "top" || layerName === "overlay"

  signal submitted(string text)
  signal dismissed()

  function focusInput() {
    panel.focusInput()
  }

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "landis-wizard-chat"
  WlrLayershell.layer: box.layerName === "top" ? WlrLayer.Top
    : (box.layerName === "overlay" ? WlrLayer.Overlay : WlrLayer.Bottom)
  // OnDemand rather than Exclusive: it can be typed into when you click it,
  // but it never holds your keyboard hostage while it sits there. On `bottom`
  // the compositor will not focus it at all, so it does not ask.
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

  ChatPanel {
    id: panel
    anchors.fill: parent
    canType: box.canType
    onSubmitted: (text) => box.submitted(text)
    onDismissed: box.dismissed()
  }
}
