import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "dev.egoist.cpu-usage"

  property var cpuSnapshot: ({})
  property var cpuHistory: []
  property string cpuError: ""

  readonly property real configuredWidth: {
    var value = Number(setting("width", Style.bar.iconSlot))
    return isFinite(value) && value > 0
      ? Math.max(Style.bar.iconSlot, Math.min(100, value))
      : Style.bar.iconSlot
  }
  readonly property string cpuScript: localPath(Qt.resolvedUrl("scripts/cpu-stats"))
  readonly property real cpuPercent: Number(cpuSnapshot.cpuPercent || 0)
  readonly property real userPercent: Number(cpuSnapshot.userPercent || 0)
  readonly property real systemPercent: Number(cpuSnapshot.systemPercent || 0)
  readonly property real temperatureC: Number(cpuSnapshot.temperatureC || -1)
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function refresh() {
    if (!cpuProcess.running) cpuProcess.running = true
  }

  function updateCpu(raw) {
    try {
      var next = JSON.parse(String(raw || "{}"))
      if (!next || Number(next.totalTicks || 0) <= 0)
        throw new Error("Missing CPU counters")

      var previous = cpuSnapshot || ({})
      var totalDelta = Number(next.totalTicks || 0) - Number(previous.totalTicks || 0)
      var userDelta = Number(next.userTicks || 0) - Number(previous.userTicks || 0)
      var systemDelta = Number(next.systemTicks || 0) - Number(previous.systemTicks || 0)

      if (Number(previous.totalTicks || 0) > 0 && totalDelta > 0
          && userDelta >= 0 && systemDelta >= 0) {
        next.userPercent = Math.max(0, Math.min(100, userDelta * 100 / totalDelta))
        next.systemPercent = Math.max(0, Math.min(100 - next.userPercent, systemDelta * 100 / totalDelta))
        next.cpuPercent = Math.max(0, Math.min(100, next.userPercent + next.systemPercent))

        var nextHistory = cpuHistory.slice(Math.max(0, cpuHistory.length - 59))
        nextHistory.push({
          user: next.userPercent,
          system: next.systemPercent,
          total: next.cpuPercent
        })
        cpuHistory = nextHistory
      } else {
        next.userPercent = Number(previous.userPercent || 0)
        next.systemPercent = Number(previous.systemPercent || 0)
        next.cpuPercent = Number(previous.cpuPercent || 0)
      }

      cpuSnapshot = next
      cpuError = ""
    } catch (error) {
      cpuError = "Could not read CPU statistics"
    }
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: refresh()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fixedWidth: root.vertical ? -1 : root.configuredWidth
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    horizontalMargin: 0
    verticalPadding: 0
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.cpuSnapshot.totalTicks
      ? "CPU: " + Math.round(root.cpuPercent) + "% · user "
        + Math.round(root.userPercent) + "% · system " + Math.round(root.systemPercent) + "%"
        + (root.temperatureC >= 0 ? " · " + Math.round(root.temperatureC) + "°C" : "")
      : (root.cpuError !== "" ? root.cpuError : "Reading CPU usage…")

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }

    Row {
      anchors.centerIn: parent
      height: Style.bar.iconCanvas
      spacing: Style.spaceReal(3)

      Item {
        width: Style.spaceReal(8)
        height: parent.height

        Text {
          anchors.centerIn: parent
          text: "C\nP\nU"
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: 7
          font.bold: true
          lineHeight: 0.72
          lineHeightMode: Text.ProportionalHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          renderType: Text.NativeRendering

          Behavior on color {
            enabled: !root.bar || root.bar.foregroundAnimationEnabled
            ColorAnimation { duration: 160 }
          }
        }
      }

      Item {
        id: cpuMeter
        width: Style.spaceReal(7)
        height: parent.height
        clip: true

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.12)
        }

        Rectangle {
          id: userFill
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: parent.height * root.userPercent / 100
          color: "#168cfa"

          Behavior on height {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.bottomMargin: userFill.height
          height: parent.height * root.systemPercent / 100
          color: "#f05a9d"

          Behavior on height {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
          }
          Behavior on anchors.bottomMargin {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
          }
        }
      }
    }
  }

  Process {
    id: cpuProcess
    command: [root.cpuScript]

    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.cpuSnapshot.totalTicks)
        root.cpuError = "Could not read CPU statistics"
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateCpu(text)
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
}
