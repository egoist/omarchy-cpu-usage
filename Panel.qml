import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "dev.egoist.cpu-usage"
  ipcTarget: "dev.egoist.cpu-usage"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool processLoading: false
  property bool processHasSnapshot: false
  property string processError: ""
  property var processRows: []

  readonly property var barIdentity: hostWidget || root
  readonly property var snapshot: hostWidget && hostWidget.cpuSnapshot
    ? hostWidget.cpuSnapshot
    : ({})
  readonly property var history: hostWidget && hostWidget.cpuHistory
    ? hostWidget.cpuHistory
    : []
  readonly property string cpuError: hostWidget ? String(hostWidget.cpuError || "") : ""
  readonly property int processRosterSize: {
    var value = Number(setting("processCount", 5))
    return isFinite(value) ? Math.max(1, Math.min(10, Math.round(value))) : 5
  }
  readonly property string processScript: localPath(Qt.resolvedUrl("scripts/process-cpu"))

  readonly property real cpuPercent: Math.max(0, Math.min(100, Number(snapshot.cpuPercent || 0)))
  readonly property real userPercent: Math.max(0, Math.min(100, Number(snapshot.userPercent || 0)))
  readonly property real systemPercent: Math.max(0, Math.min(100, Number(snapshot.systemPercent || 0)))
  readonly property real temperatureC: Number(snapshot.temperatureC || -1)
  readonly property color userColor: "#168cfa"
  readonly property color systemColor: "#f05a9d"
  readonly property color gridColor: Qt.rgba(barForeground.r, barForeground.g, barForeground.b, 0.14)

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function open() {
    processError = ""
    processLoading = !processHasSnapshot
    root.controller.show()
    Qt.callLater(root.refreshProcesses)
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refreshProcesses() {
    if (!processCpu.running) processCpu.running = true
  }

  function updateProcesses(raw) {
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      processRows = Array.isArray(parsed) ? parsed : []
      processError = ""
      processHasSnapshot = true
      processLoading = false
    } catch (error) {
      if (!processHasSnapshot) {
        processRows = []
        processError = "Could not read process CPU"
        processHasSnapshot = true
      }
      processLoading = false
    }
  }

  function normalizedAppName(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
  }

  function desktopEntryForProcess(processName) {
    var needle = normalizedAppName(processName)
    if (needle.length < 2) return null

    var entries = DesktopEntries.applications.values || []
    var bestEntry = null
    var bestScore = 0
    for (var index = 0; index < entries.length; index++) {
      var entry = entries[index]
      if (!entry) continue
      var id = normalizedAppName(entry.id).replace(/desktop$/, "")
      var name = normalizedAppName(entry.name)
      var icon = normalizedAppName(entry.icon)
      var score = 0
      if (needle === id || needle === name || needle === icon) score = 100
      else if (needle.length >= 4
          && (id.indexOf(needle) >= 0 || name.indexOf(needle) >= 0 || icon.indexOf(needle) >= 0)) score = 80
      else if (id.length >= 4 && needle.indexOf(id) >= 0) score = 70
      if (score > bestScore) {
        bestScore = score
        bestEntry = entry
      }
    }
    return bestEntry
  }

  function processDisplayName(processName) {
    var entry = desktopEntryForProcess(processName)
    return entry && entry.name ? String(entry.name) : String(processName || "Unknown")
  }

  function processIconSource(processName) {
    var entry = desktopEntryForProcess(processName)
    var appLibrary = root.bar && root.bar.shell ? root.bar.shell.appLibrary : null
    if (entry && appLibrary && typeof appLibrary.iconSource === "function")
      return appLibrary.iconSource(entry.icon)
    if (entry && entry.icon) {
      var entryIcon = Quickshell.iconPath(String(entry.icon), true)
      if (entryIcon) return entryIcon
    }
    var processIcon = Quickshell.iconPath(String(processName || ""), true)
    if (processIcon) return processIcon
    return Quickshell.iconPath("application-x-executable", true)
  }

  function formatTemperature() {
    return temperatureC >= 0 ? Math.round(temperatureC) + "°C" : "--"
  }

  function formatLoad() {
    return Number(snapshot.load1 || 0).toFixed(2) + "  ·  "
      + Number(snapshot.load5 || 0).toFixed(2) + "  ·  "
      + Number(snapshot.load15 || 0).toFixed(2)
  }

  function formatUptime() {
    var seconds = Math.max(0, Math.floor(Number(snapshot.uptimeSeconds || 0)))
    var days = Math.floor(seconds / 86400)
    var hours = Math.floor((seconds % 86400) / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + minutes + "m"
    return minutes + "m"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refreshProcesses()
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: Style.space(26)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "CPU"
            color: root.userColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.formatTemperature() + "  ·  " + Math.round(root.cpuPercent) + "%"
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        Canvas {
          id: cpuGraph
          width: parent.width
          height: Style.space(132)
          property var samples: root.history
          property color userGraphColor: root.userColor
          property color systemGraphColor: root.systemColor
          property color graphGridColor: root.gridColor

          onSamplesChanged: requestPaint()
          onUserGraphColorChanged: requestPaint()
          onSystemGraphColorChanged: requestPaint()
          onGraphGridColorChanged: requestPaint()
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onPaint: {
            var context = getContext("2d")
            context.clearRect(0, 0, width, height)
            context.lineWidth = Math.max(1, Style.spaceReal(1))
            context.strokeStyle = graphGridColor

            for (var line = 1; line < 4; line++) {
              var y = height * line / 4
              context.beginPath()
              context.moveTo(0, y)
              context.lineTo(width, y)
              context.stroke()
            }

            var values = samples || []
            if (values.length === 0) return
            var slots = 60
            var step = width / slots
            var startX = width - values.length * step
            for (var index = 0; index < values.length; index++) {
              var sample = values[index] || ({})
              var userHeight = Math.max(0, Math.min(height, Number(sample.user || 0) * height / 100))
              var systemHeight = Math.max(0, Math.min(height - userHeight,
                Number(sample.system || 0) * height / 100))
              var x = startX + index * step
              context.fillStyle = userGraphColor
              context.fillRect(x, height - userHeight, Math.max(1, step), userHeight)
              context.fillStyle = systemGraphColor
              context.fillRect(x, height - userHeight - systemHeight, Math.max(1, step), systemHeight)
            }
          }
        }

        Row {
          width: parent.width
          height: Style.space(22)
          spacing: Style.space(18)

          Row {
            height: parent.height
            spacing: Style.space(6)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(8)
              height: width
              radius: width / 2
              color: root.userColor
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "User  " + root.userPercent.toFixed(1) + "%"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          Row {
            height: parent.height
            spacing: Style.space(6)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(8)
              height: width
              radius: width / 2
              color: root.systemColor
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "System  " + root.systemPercent.toFixed(1) + "%"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.barForeground
          opacity: 0.12
        }

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "TOP PROCESSES"
            color: root.userColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(7)
            height: width
            radius: width / 2
            color: root.userColor
            opacity: root.processLoading ? 0.45 : 0.9

            SequentialAnimation on opacity {
              running: root.opened && root.processLoading
              loops: Animation.Infinite
              NumberAnimation { to: 0.25; duration: 450 }
              NumberAnimation { to: 0.9; duration: 450 }
            }
          }
        }

        Text {
          visible: root.processRows.length === 0
          width: parent.width
          height: Style.space(46)
          text: root.processError !== ""
            ? root.processError
            : (root.processLoading ? "Sampling process CPU…" : "No active process CPU")
          color: Qt.darker(root.barForeground, 1.35)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Repeater {
          model: root.processRows.slice(0, root.processRosterSize)

          delegate: Item {
            required property var modelData
            width: contentColumn.width
            height: Style.space(27)

            Item {
              id: processIconSlot
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              height: parent.height

              Image {
                id: processIcon
                anchors.centerIn: parent
                width: Style.space(18)
                height: width
                fillMode: Image.PreserveAspectFit
                source: root.processIconSource(modelData.name)
                asynchronous: true
              }

              Text {
                anchors.centerIn: parent
                visible: processIcon.status !== Image.Ready
                text: "󰣆"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Text {
              anchors.left: processIconSlot.right
              anchors.leftMargin: Style.space(7)
              anchors.right: processCpuLabel.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.processDisplayName(modelData.name)
                + (Number(modelData.processCount || 0) > 1 ? "  ·  " + modelData.processCount : "")
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              id: processCpuLabel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(78)
              text: Number(modelData.cpuPercent || 0).toFixed(1) + "%"
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              horizontalAlignment: Text.AlignRight
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.barForeground
          opacity: 0.12
        }

        Repeater {
          model: [
            { label: "LOAD  1 · 5 · 15 MIN", value: root.formatLoad() },
            { label: "UPTIME", value: root.formatUptime() },
            { label: "LOGICAL CPUS", value: String(Number(root.snapshot.cpuCount || 0)) }
          ]

          delegate: Item {
            required property var modelData
            width: contentColumn.width
            height: Style.space(22)

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: root.userColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.value
              color: root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }
        }

        Text {
          width: parent.width
          text: root.cpuError !== "" ? root.cpuError : "Per-process usage is sampled live · R to refresh"
          color: Qt.darker(root.barForeground, 1.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }
  }

  Process {
    id: processCpu
    command: [root.processScript]

    onRunningChanged: {
      if (running) root.processLoading = !root.processHasSnapshot
      else root.processLoading = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.processHasSnapshot) {
        root.processRows = []
        root.processError = "Could not read process CPU"
        root.processHasSnapshot = true
      }
      root.processLoading = false
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateProcesses(text)
    }
  }

  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshProcesses()
  }
}
