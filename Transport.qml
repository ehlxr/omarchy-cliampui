import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Column {
  id: root

  property QtObject bar: null
  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var strings: ({})

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property bool live: !!(service && service.running)
  readonly property bool shuffling: !!(service && service.shuffle)
  readonly property bool repeating: !!(service && service.repeat !== "Off")
  readonly property bool onOne: !!(service && service.repeat === "One")
  readonly property bool onAll: !!(service && service.repeat === "All")
  readonly property bool onSequential: !!(service && !service.shuffle && service.repeat === "Off")

  spacing: Style.space(8)

  // One row, centred on the horizontal axis as a single control strip: the four play
  // modes flank the prev/play/next cluster on the two sides (they share one exclusive
  // group, so exactly one icon is bright and the rest are dim). Every icon is
  // vertically centred on the tallest one rather than hung from the row's top edge.
  RowLayout {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(10)

    TransportButton {
      glyph: "⇄"
      size: Style.space(20)
      enabled: root.live
      selected: root.shuffling
      color: root.shuffling ? root.foreground : root.dim
      onActivated: if (root.service) root.service.selectMode("shuffle")
      Layout.alignment: Qt.AlignVCenter
    }

    TransportButton {
      glyph: "↻"
      size: Style.space(20)
      enabled: root.live
      selected: root.onAll
      color: root.onAll ? root.foreground : root.dim
      onActivated: if (root.service) root.service.selectMode("repeatAll")
      Layout.alignment: Qt.AlignVCenter
    }

    Item {
      width: Style.space(14)
      height: 1
      Layout.alignment: Qt.AlignVCenter
    }

    TransportButton {
      shape: "prev"
      size: Style.space(22)
      enabled: root.live
      color: root.dim
      onActivated: root.service.previous()
      Layout.alignment: Qt.AlignVCenter
    }

    TransportButton {
      shape: root.service && root.service.showPlaying ? "pause" : "play"
      size: Style.space(34)
      enabled: root.live
      filled: true
      fillColor: Color.accent
      // The glyph sits on the accent disc, so it takes the background colour to read.
      color: Color.background
      onActivated: root.service.playPause()
      Layout.alignment: Qt.AlignVCenter
    }

    TransportButton {
      shape: "next"
      size: Style.space(22)
      enabled: root.live
      color: root.dim
      onActivated: root.service.next()
      Layout.alignment: Qt.AlignVCenter
    }

    Item {
      width: Style.space(14)
      height: 1
      Layout.alignment: Qt.AlignVCenter
    }

    TransportButton {
      glyph: "↻¹"
      size: Style.space(20)
      enabled: root.live
      selected: root.onOne
      color: root.onOne ? root.foreground : root.dim
      onActivated: if (root.service) root.service.selectMode("repeatOne")
      Layout.alignment: Qt.AlignVCenter
    }

    TransportButton {
      glyph: "≡"
      size: Style.space(20)
      enabled: root.live
      selected: root.onSequential
      color: root.onSequential ? root.foreground : root.dim
      onActivated: if (root.service) root.service.selectMode("sequential")
      Layout.alignment: Qt.AlignVCenter
    }
  }

  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    // MPRIS reports HasTrackList false and the IPC has no queue read, so a count is
    // the most this panel can honestly say about what is coming next.
    text: root.service && root.service.total > 0
        ? (root.strings && root.strings.inQueue
          ? root.strings.inQueue(root.service.total)
          : root.service.total + " in queue")
        : ""
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    visible: text.length > 0
  }

  // Volume lives on a single row like every other section: label on the left, the
  // track stretched between it and the percent on the right, so the whole control is
  // one padded, outlined surface. Percent, not dB, because this is the PipeWire
  // stream gain and not cliamp's own.
  CursorSurface {
    width: parent.width
    foreground: root.foreground
    outline: true
    visible: !!(root.service && root.service.hasStreamVolume)
    implicitHeight: Math.max(volumeHeader.implicitHeight, volumeValue.implicitHeight, volumeSlider.implicitHeight) + Style.spacing.rowPaddingX

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      PanelSectionHeader {
        id: volumeHeader
        text: String(root.strings.sectionVolume || "VOLUME")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      PanelSlider {
        id: volumeSlider
        bar: root.bar
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(22)
        minimum: 0
        maximum: 100
        step: 1
        value: root.service ? root.service.streamVolume * 100 : 0
        enabled: root.live

        onMoved: function (v) { if (root.service) root.service.setStreamVolume(v / 100) }
        // Right click returns the stream to unity and clears mute, which is the state
        // the verdict counts as untouched. cliamp's own gain is expected to stay at 0 dB.
        onRightClicked: if (root.service) root.service.setStreamVolume(1)
      }

      Text {
        id: volumeValue
        textFormat: Text.PlainText
        text: {
          if (!root.service) return ""
          if (volumeSlider.dragging) return Math.round(volumeSlider.liveValue) + "%"
          if (root.service.streamMuted) return String(root.strings.muted || "MUTED")
          return Math.round(root.service.streamVolume * 100) + "%"
        }
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }
}