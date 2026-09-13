import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The track list of the browsed playlist. Browsing is strictly read-only: the list is
// driven by the playlist the Library picks (or the one already loaded on open), and
// switching never touches the queue; double-clicking a song either points the existing
// queue at it or loads the playlist and jumps. The current song stays in library order
// and the list scrolls to it, instead of being pinned to the top.
Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false
  // The panel cursor is a real browsed-track index, so filtering maps it into the list.
  // -1 means the keyboard cursor is not on this section, so no row is highlighted.
  property int cursorIndex: -1
  property var strings: ({})
  property string filterQuery: ""

  signal toggleRequested()
  signal cursorRequested(int index)
  signal moveRequested(int delta)
  signal activateRequested()

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property int listMaxHeight: Style.space(300)
  readonly property var tracks: service ? service.browsedTracks : []

  // PanelKeyCatcher runs at Keys.BeforeItem, so the panel must stand down while this
  // field has the keyboard or every letter typed also fires a panel action.
  readonly property bool searchFocused: search.activeFocus

  // Filtered rows carry their real browsed index, so interactive rows, the panel cursor
  // and the scroll target all keep talking in playlist numbers the whole time.
  readonly property var filteredRows: root.visibleRows()

  // The playlist rows came from the section above, so naming it again here would be
  // noise: the summary shows how many rows the linked playlist holds instead.
  readonly property string summaryText: {
    if (!root.service) return ""
    if (String(root.service.browsedPlaylist || "").length === 0)
      return String(root.strings.pickPlaylist || "Pick a playlist")
    if (root.service.browsedTotal <= 0) return ""
    var shown = root.filteredRows.length
    var total = root.service.browsedTotal
    if (shown !== total)
      return root.strings.tracksCount
        ? shown + " / " + root.strings.tracksCount(total)
        : shown + " / " + total + " tracks"
    return root.strings.tracksCount
      ? root.strings.tracksCount(total)
      : total + " tracks"
  }

  readonly property string stringsHead: String(root.strings.sectionPlaylists || "PLAYLISTS")

  // Keeps the cursor row on screen without ListView owning the cursor.
  onCursorIndexChanged: if (cursorIndex >= 0) revealReal(cursorIndex)

  onExpandedChanged: if (root.expanded) root.scrollToCurrent()
  // Closed while open? no. The panel reopens over the same list, so visibility is when
  // the scroll is wanted again: the section is already expanded, nothing else changes.
  onVisibleChanged: if (root.visible) root.scrollToCurrent()

  function visibleRows() {
    var rows = root.tracks
    var needle = String(root.filterQuery || "").toLowerCase()
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var t = rows[i] || {}
      var title = String(t.title || "").toLowerCase()
      var artist = String(t.artist || "").toLowerCase()
      if (needle.length > 0 && title.indexOf(needle) === -1 && artist.indexOf(needle) === -1) continue
      out.push({ row: t, real: i })
    }
    return out
  }

  function realIndexOfCurrent() {
    var rows = root.tracks
    if (!root.service) return -1
    for (var i = 0; i < rows.length; i++) {
      if (Model.sameTrack(rows[i], root.service.status)) return i
    }
    return -1
  }

  function filteredIndexForReal(real) {
    if (real < 0) return -1
    for (var i = 0; i < root.filteredRows.length; i++) {
      if (root.filteredRows[i].real === real) return i
    }
    return -1
  }

  function revealReal(real) {
    var fi = root.filteredIndexForReal(real)
    if (fi >= 0) trackList.positionViewAtIndex(fi, ListView.Contain)
  }

  // The current song sits where the playlist put it; this brings it into view at its
  // natural number rather than moving the row. The position lands a beat later, after
  // the panel's open is laid out, so a view that had no size yet gets another pass.
  property int _pendingReal: -1
  function scrollToCurrent() {
    if (!root.expanded || root.filteredRows.length === 0) return
    var real = root.realIndexOfCurrent()
    if (real < 0) return
    root._pendingReal = real
    scrollTimer.restart()
  }

  Timer {
    id: scrollTimer
    interval: 110
    repeat: false
    onTriggered: root.applyScroll()
  }

  function applyScroll() {
    var fi = root.filteredIndexForReal(root._pendingReal)
    if (fi >= 0) trackList.positionViewAtIndex(fi, ListView.Center)
  }

  onFilterQueryChanged: root.scrollToCurrent()

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

    // Filter the list down to a name: rows collapse out entirely rather than the queue
    // churning, and the live track scrolls to its filtered place when it is one of them.
    TextField {
      id: search
      width: parent.width
      placeholderText: String(root.strings.songSearchPlaceholder || "Filter songs")
      foreground: root.foreground
      font.family: root.fontFamily

      // The catcher is standing down, so these are the panel keys worth keeping here.
      Keys.onEscapePressed: root.focus = true
      Keys.onUpPressed: root.moveRequested(-1)
      Keys.onDownPressed: root.moveRequested(1)
      Keys.onReturnPressed: root.activateRequested()
      Keys.onEnterPressed: root.activateRequested()

      onTextChanged: root.filterQuery = text
    }

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
      model: root.filteredRows
      keyNavigationEnabled: false
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      // The browsed rows land page by page; once the whole playlist is in, the panel
      // cursor is clamped and the current song is brought into view.
      onModelChanged: {
        if (root.cursorIndex >= 0) root.revealReal(root.cursorIndex)
        root.scrollToCurrent()
      }
      onAtYEndChanged: if (atYEnd && root.service) root.service.readMoreBrowsedTracks()

      delegate: CursorSurface {
        id: row
        required property var modelData
        required property int index

        width: trackList.width
        foreground: root.foreground
        hasCursor: modelData.real === root.cursorIndex
        implicitHeight: Math.max(titleLabel.implicitHeight, metaLabel.implicitHeight) + Style.spacing.rowPaddingX

        readonly property bool current: root.service && Model.sameTrack(modelData.row, root.service.status)

        // A click parks the panel cursor on the row; a double click plays it.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cursorRequested(modelData.real)
          onDoubleClicked: if (root.service) root.service.playBrowsedTrack(modelData.row)
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
            text: String(typeof modelData.row.index === "number" ? modelData.row.index + 1 : modelData.real + 1)
            color: row.current ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            id: titleLabel
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: (row.current ? "♪ " : "") + String(modelData.row.title || "")
            color: row.current ? root.foreground : (modelData.real === root.cursorIndex ? root.foreground : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            id: metaLabel
            textFormat: Text.PlainText
            text: {
              var parts = []
              if (modelData.row.artist) parts.push(String(modelData.row.artist))
              if (modelData.row.durationSecs > 0) parts.push(Model.formatTime(modelData.row.durationSecs))
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

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: String(root.strings.nothingMatched || "Nothing matched")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      visible: root.filteredRows.length === 0
    }
  }
}