import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SwitcherModel.js" as Model

// Alt+Tab window switcher. Hyprland binds drive it over IPC:
//   omarchy-shell shibumi-switcher next|prev|release|cancel
// A press starts a session and reads `hyprctl clients -j` (focusHistoryID is
// Hyprland's own MRU order); releasing Alt focuses the selection. A quick tap
// commits before the card is ever shown, so flipping between two windows
// never flashes the overlay.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "av.shibumi-switcher"

  // Session state.
  property bool active: false     // a press has started a session
  property bool loaded: false     // the window list for this session arrived
  property bool opened: false     // the card is on screen
  property bool pendingCommit: false
  property int pendingSteps: 0
  property int session: 0
  property var windows: []
  property int selectedIndex: 0

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // Theme: the [menu] surface tokens, same as Omarchy's own overlays.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color accent: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int pad: Style.spacing.panelPadding
  readonly property int cardWidth: Style.space(184)
  readonly property int cardHeight: Style.space(150)
  readonly property int iconSize: Style.space(56)
  readonly property int maxRows: 3

  // ---------------------------------------------------------------- control

  function step(delta) {
    if (!root.active) {
      root.active = true
      root.loaded = false
      root.pendingCommit = false
      root.pendingSteps = delta
      root.session++
      clients.running = false
      clients.running = true
      showDelay.restart()
      return
    }
    if (!root.loaded) {
      root.pendingSteps += delta
      return
    }
    root.select(root.selectedIndex + delta)
  }

  function select(index) {
    if (root.windows.length === 0) return
    root.selectedIndex = Model.wrap(index, root.windows.length)
    grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function release() {
    if (!root.active) return
    if (!root.loaded) { root.pendingCommit = true; return }
    root.commit()
  }

  function commit() {
    var win = root.windows[root.selectedIndex]
    root.reset()
    if (!win || win.history === 0) return
    var monitor = Hyprland.focusedMonitor
    var current = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    var steps = Model.focusSteps(win, current)
    for (var i = 0; i < steps.length; i++) Hyprland.dispatch(steps[i])
  }

  function closeSelected() {
    var win = root.windows[root.selectedIndex]
    if (!win) return
    Hyprland.dispatch(Model.closeStep(win))
    var next = root.windows.slice()
    next.splice(root.selectedIndex, 1)
    root.windows = next
    if (next.length === 0) { root.reset(); return }
    root.select(Math.min(root.selectedIndex, next.length - 1))
  }

  // Ends the session and tells the shell the overlay is closed. The shell
  // answers hide() by calling close(), which must not call back into it.
  function reset() {
    root.resetLocal()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function resetLocal() {
    showDelay.stop()
    clients.running = false
    root.active = false
    root.loaded = false
    root.opened = false
    root.pendingCommit = false
    root.pendingSteps = 0
  }

  function receive(raw, forSession) {
    if (!root.active || forSession !== root.session) return
    var list = Model.buildWindows(raw)
    root.windows = list
    root.loaded = true
    if (list.length === 0) { root.reset(); return }
    var start = Model.initialIndex(list.length, root.pendingSteps)
    // Extra presses that landed before the list arrived still count.
    var extra = root.pendingSteps - (root.pendingSteps < 0 ? -1 : 1)
    root.select(start + extra)
    if (root.pendingCommit) root.commit()
  }

  // Shell contract: `omarchy-shell shell summon av.shibumi-switcher '{"cmd":"next"}'`.
  function open(payloadJson) {
    var cmd = "next"
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (p && typeof p.cmd === "string") cmd = p.cmd
    } catch (e) {}
    root.command(cmd)
  }

  function close() { root.resetLocal() }

  function command(cmd) {
    if (cmd === "next") root.step(1)
    else if (cmd === "prev") root.step(-1)
    else if (cmd === "release") root.release()
    else if (cmd === "cancel") root.reset()
  }

  IpcHandler {
    target: "shibumi-switcher"
    function next(): void { root.step(1) }
    function prev(): void { root.step(-1) }
    function release(): void { root.release() }
    function cancel(): void { root.reset() }
  }

  Process {
    id: clients
    property int forSession: 0
    command: ["hyprctl", "clients", "-j"]
    onRunningChanged: if (running) forSession = root.session
    stdout: StdioCollector {
      onStreamFinished: root.receive(text, clients.forSession)
    }
  }

  Timer {
    id: showDelay
    interval: 110
    onTriggered: if (root.active) root.opened = true
  }

  // ------------------------------------------------------------------- view

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "shibumi-switcher"

    MouseArea {
      anchors.fill: parent
      onClicked: root.reset()
    }

    BorderSurface {
      id: card
      readonly property int columns: Math.max(1, Math.min(root.windows.length,
        Math.floor((panel.width * 0.86 - root.pad * 2) / root.cardWidth)))
      readonly property int rows: Math.max(1, Math.min(root.maxRows, Math.ceil(root.windows.length / columns)))

      anchors.centerIn: parent
      width: columns * root.cardWidth + card.contentLeftInset + card.contentRightInset
      height: rows * root.cardHeight + hint.height + Style.spacing.md + card.contentTopInset + card.contentBottomInset
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.pad

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: root.opened

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var key = Util.readingKey(event)
          if (event.key === Qt.Key_Escape) root.reset()
          else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) root.step(-1)
          else if (event.key === Qt.Key_Tab || key === Qt.Key_Right) root.step(1)
          else if (key === Qt.Key_Left) root.step(-1)
          else if (event.key === Qt.Key_Down) root.select(root.selectedIndex + card.columns)
          else if (event.key === Qt.Key_Up) root.select(root.selectedIndex - card.columns)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit()
          else if (event.key === Qt.Key_Q || event.key === Qt.Key_Delete) root.closeSelected()
          else return
          event.accepted = true
        }
        // Fallback for when the Hyprland release bind is missing.
        Keys.onReleased: function(event) {
          if (event.key === Qt.Key_Alt && !event.isAutoRepeat) { root.release(); event.accepted = true }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        GridView {
          id: grid
          width: parent.width
          height: card.rows * root.cardHeight
          cellWidth: root.cardWidth
          cellHeight: root.cardHeight
          clip: true
          interactive: card.rows >= root.maxRows
          boundsBehavior: Flickable.StopAtBounds
          model: root.windows

          delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool current: index === root.selectedIndex
            readonly property var entry: DesktopEntries.heuristicLookup(modelData.appClass)
            readonly property string iconSource: {
              var name = entry && entry.icon ? entry.icon : modelData.appClass
              if (!name) return ""
              if (name.charAt(0) === "/") return Util.fileUrl(name)
              return Quickshell.iconPath(name, true) || Quickshell.iconPath(String(name).toLowerCase(), true) || ""
            }

            width: root.cardWidth
            height: root.cardHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.spacing.sm
              radius: root.cornerRadius
              color: cell.current ? root.selectedBackground : "transparent"
              border.width: cell.current ? Math.max(1, Style.space(2)) : 0
              border.color: root.accent

              Column {
                anchors.fill: parent
                anchors.margins: Style.spacing.lg
                spacing: Style.spacing.sm

                Item {
                  width: parent.width
                  height: root.iconSize

                  Image {
                    id: icon
                    anchors.centerIn: parent
                    width: root.iconSize
                    height: root.iconSize
                    sourceSize.width: root.iconSize * 2
                    sourceSize.height: root.iconSize * 2
                    source: cell.iconSource
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    opacity: cell.modelData.minimized ? 0.55 : 1
                  }
                  // No icon: the app's initial.
                  Text {
                    anchors.centerIn: parent
                    visible: icon.status !== Image.Ready
                    textFormat: Text.PlainText
                    text: (cell.modelData.appClass || "?").charAt(0).toUpperCase()
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: cell.modelData.title || cell.modelData.appClass
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: cell.current
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  wrapMode: Text.Wrap
                  height: Math.ceil(Style.font.body * 2.6)
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: {
                    var m = cell.modelData
                    var where = m.minimized ? strings.t("switcher.minimized")
                      : m.special ? strings.t("switcher.special")
                      : strings.t("switcher.workspace").arg(m.workspaceName || m.workspaceId)
                    var app = cell.entry && cell.entry.name ? cell.entry.name : m.appClass
                    return app ? app + " · " + where : where
                  }
                  color: cell.current ? root.accent : root.foreground
                  opacity: cell.current ? 1 : 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = cell.index
                onClicked: { root.selectedIndex = cell.index; root.commit() }
              }
            }
          }
        }

        Text {
          id: hint
          width: parent.width
          textFormat: Text.PlainText
          text: strings.t("switcher.hint")
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
