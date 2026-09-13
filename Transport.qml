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

  // The line being sung, where the volume row used to be. cliamp resolves lyrics
  // itself, so this draws what it already has rather than fetching anything, and it
  // takes no room at all on a track that has none. Multi-line: long lines wrap
  // instead of scrolling like a marquee, capped at three lines so the panel cannot
  // grow without bound, and folded to spaces so embedded line breaks read as pauses.
  Text {
    id: lyric
    width: parent.width
    visible: root.service
        && root.service.hasTrack
        && String(root.service.activeLyric || "").length > 0
    text: root.service ? String(root.service.activeLyric || "").replace(/[\r\n]+/g, " ") : ""
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.Wrap
    maximumLineCount: 3
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
  }
}