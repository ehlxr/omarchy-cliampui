import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The track list of the browsed playlist. Browsing is strictly read-only: the list is
// driven by the playlist the Library picks (or the one already loaded on open), and
// switching never touches the queue; double-clicking a song either points the existing
// queue at it or loads the playlist and jumps.
Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false
  property int cursorIndex: -1
  property var strings: ({})

  signal toggleRequested()
  signal cursorRequested(int index)

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property int listMaxHeight: Style.space(300)
  readonly property var tracks: service ? service.browsedTracks : []

  // The playlist rows came from the section above, so naming it again here would be
  // noise: the summary shows how many rows the linked playlist holds instead.
  readonly property string summaryText: {
    if (!root.service) return ""
    if (String(root.service.browsedPlaylist || "").length === 0)
      return String(root.strings.pickPlaylist || "Pick a playlist")
    if (root.service.browsedTotal <= 0) return ""
    return root.strings.tracksCount
      ? root.strings.tracksCount(root.service.browsedTotal)
      : root.service.browsedTotal + " tracks"
  }

  readonly property string stringsHead: String(root.strings.sectionPlaylists || "PLAYLISTS")

  // Keeps the cursor row on screen without ListView owning the cursor.
  onCursorIndexChanged: if (cursorIndex >= 0) trackList.positionViewAtIndex(cursorIndex, ListView.Contain)

  spacing: Style.space(8)

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  // The whole section head is one clickable row: label on the left, the linked
  // playlist's track count on the right beside the folding arrow.
  CursorSurface {
    width: parent.width
    foreground: root.foreground
    implicitHeight: Math.max(head.implicitHeight, summaryValue.implicitHeight) + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleRequested()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      PanelSectionHeader {
        id: head
        text: root.stringsHead
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Item { Layout.fillWidth: true }

      // Not the playlist name: the row above already names it, and this section is the
      // list that follows the pick, so the only news here is how many rows it holds.
      Text {
        id: summaryValue
        textFormat: Text.PlainText
        text: root.summaryText
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: root.expanded ? "⌄" : "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.expanded

    // The playlist is chosen in the Library; this section only shows what it points at,
    // so the hint stands in for a picker when nothing has been browsed yet on this open.
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: String(root.strings.pickPlaylist || "Pick a playlist")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      visible: root.service && root.service.browsedPlaylist === ""
    }

    ListView {
      id: trackList
      width: parent.width
      height: Math.min(contentHeight, root.listMaxHeight)
      clip: true
      spacing: Style.space(2)
      model: root.tracks
      keyNavigationEnabled: false
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      // currentIndex is deliberately not bound to the panel's cursor: ListView writes
      // that property itself on every model swap, which breaks the binding for good.
      onCountChanged: if (root.cursorIndex >= 0) positionViewAtIndex(root.cursorIndex, ListView.Contain)
      onAtYEndChanged: if (atYEnd && root.service) root.service.readMoreBrowsedTracks()

      delegate: CursorSurface {
        id: row
        required property var modelData
        required property int index

        width: trackList.width
        foreground: root.foreground
        hasCursor: index === root.cursorIndex
        implicitHeight: Math.max(titleLabel.implicitHeight, metaLabel.implicitHeight) + Style.spacing.rowPaddingX

        readonly property bool current: root.service && Model.sameTrack(modelData, root.service.status)

        // A click parks the panel cursor on the row; a double click plays it.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cursorRequested(index)
          onDoubleClicked: if (root.service) root.service.playBrowsedTrack(modelData)
        }

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)

          // The global queue index plus one, so the row reads as a numbered track list.
          Text {
            id: numberLabel
            textFormat: Text.PlainText
            text: String(typeof modelData.index === "number" ? modelData.index + 1 : index + 1)
            color: row.current ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            id: titleLabel
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: (row.current ? "♪ " : "") + String(modelData.title || "")
            color: row.current ? root.foreground : (index === root.cursorIndex ? root.foreground : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            id: metaLabel
            textFormat: Text.PlainText
            text: {
              var parts = []
              if (modelData.artist) parts.push(String(modelData.artist))
              if (modelData.durationSecs > 0) parts.push(Model.formatTime(modelData.durationSecs))
              return parts.join(" · ")
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}