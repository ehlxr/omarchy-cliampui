import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The lyric sheet, made the visual centre of the panel. cliamp serves the whole
// track's lines with timestamps (LRC), so this draws a window of lines around the
// line being sung: the current one large and bright, the neighbours fading by
// distance, and the whole list gliding to keep the active line centred, the way a
// real player scrolls. No background blob, no borders, no scrollbar, and it takes
// no room at all on a track that has no lyrics.
Item {
  id: root

  property QtObject bar: null
  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property bool active: !!(root.service && root.service.hasLyrics)
  readonly property var lines: root.active ? root.service.lyrics : []
  readonly property int activeIndex: root.service ? root.service.activeLyricIndex : -1
  readonly property string track: root.service ? root.service.lyricsTrackPath : ""
  readonly property int windowRows: 7
  readonly property real slot: Style.space(28)

  visible: root.active
  width: parent.width
  height: root.slot * root.windowRows

  // The list is not interactive; a single soft slide moves the rows so the active
  // line settles dead centre. A new track snaps instead of gliding, because the
  // contents changed under it.
  ListView {
    id: list
    anchors.fill: parent
    clip: true
    interactive: false
    model: root.lines.length

    delegate: listDelegate
  }

  function centerActive(withGlide) {
    if (!root.active || root.activeIndex < 0) return
    var mid = list.height / 2
    var target = root.activeIndex * root.slot + root.slot / 2 - mid
    var maxY = Math.max(0, list.contentHeight - list.height)
    target = Math.max(0, Math.min(target, maxY))
    if (!withGlide || Math.abs(list.contentY - target) < 2) {
      slide.stop()
      list.contentY = target
      return
    }
    slide.from = list.contentY
    slide.to = target
    slide.restart()
  }

  NumberAnimation {
    id: slide
    target: list
    property: "contentY"
    duration: 420
    easing.type: Easing.OutCubic
  }

  property bool newLinesPending: false

  onLinesChanged: {
    newLinesPending = true
    slide.stop()
    list.contentY = 0
  }

  onActiveIndexChanged: {
    // When the track just changed, the rows exist but the position arrives behind
    // the lyrics, so snap to its first line rather than glide to it.
    if (newLinesPending) {
      newLinesPending = false
      root.centerActive(false)
      return
    }
    root.centerActive(true)
  }

  Component {
    id: listDelegate

    Item {
      id: row
      required property int index

      readonly property var entry: index < root.lines.length ? root.lines[index] : null
      readonly property bool currentRow: index === root.activeIndex
      readonly property int distance: root.activeIndex >= 0 ? Math.abs(index - root.activeIndex) : 3
      readonly property real emphasis: !root.active || root.activeIndex < 0
        ? 0.15
        : index === root.activeIndex ? 1
        : distance === 1 ? 0.78
        : distance === 2 ? 0.5
        : 0.28

      width: list.width
      height: root.slot
      visible: index < root.lines.length

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        text: row.entry ? String(row.entry.text || "") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: row.currentRow ? Style.space(15) : Style.space(11)
        font.bold: row.currentRow
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        opacity: row.emphasis
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Behavior on font.pixelSize { NumberAnimation { duration: 250 } }
      }

      // Click a past or future line to jump the playing position to it.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function () {
          if (!row.entry || !root.service) return
          root.service.seekTo(Number(row.entry.start) || 0)
        }
      }
    }
  }
}