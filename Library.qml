import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The library, browsed straight off the Subsonic server with the token cliamp already
// published. Choosing an album replaces the queue in place, so the daemon never stops
// and the terminal player is never needed to change what is playing.
Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false
  property int cursorIndex: -1
  property var strings: ({})

  signal toggleRequested()
  signal moveRequested(int delta)
  signal activateRequested()

  // PanelKeyCatcher runs at Keys.BeforeItem, so the panel must stand down while this
  // field has the keyboard or every letter typed also fires a panel action.
  readonly property bool searchFocused: search.activeFocus

  onExpandedChanged: expanded ? search.forceActiveFocus() : root.forceActiveFocus()

  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property var results: service ? service.results : []
  readonly property bool cliampRunning: !!(service && service.running)

  // A search can return a hundred rows, which is taller than the whole panel. Capping
  // the list keeps the hero and transport on screen while browsing.
  readonly property int listMaxHeight: Style.space(240)

  // Keeps the cursor row on screen without ListView owning the cursor.
  onCursorIndexChanged: if (cursorIndex >= 0) albumList.positionViewAtIndex(cursorIndex, ListView.Contain)

  spacing: Style.space(8)

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  // The whole section head is one clickable row: label on the left, the browsed
  // playlist on the right beside the folding arrow, matching the song list below.
  CursorSurface {
    width: parent.width
    foreground: root.foreground
    implicitHeight: Math.max(libraryHeader.implicitHeight, summaryLabel.implicitHeight, resultCount.implicitHeight) + Style.spacing.rowPaddingX

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
        id: libraryHeader
        text: String(root.strings.sectionLibrary || "LIBRARY")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Item { Layout.fillWidth: true }

      // The row names the playlist the song list below is showing, since the two
      // sections are one linked pair; the browse strings only stand in until a pick.
      Text {
        id: summaryLabel
        textFormat: Text.PlainText
        text: {
          var picked = root.service ? String(root.service.browsedPlaylist || "") : ""
          if (picked.length > 0) return picked
          return root.expanded
            ? String(root.strings.browseIcon || "Browse")
            : String(root.strings.browseLibrary || "Browse the library")
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      // How many rows the list below holds, the same caption the song list uses.
      Text {
        id: resultCount
        textFormat: Text.PlainText
        text: root.results.length > 0
          ? (root.strings && root.strings.results
            ? root.strings.results(root.results.length)
            : root.results.length + " RESULTS")
          : ""
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        visible: text.length > 0
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

    // search3 matches album, artist and song names, and saved playlists are matched
    // locally, so one field reaches everything that can be played.
    TextField {
      id: search
      width: parent.width
      placeholderText: String(root.strings.searchPlaceholder || "Search songs, albums and playlists")
      foreground: root.foreground
      font.family: root.fontFamily

      // The catcher is standing down, so these are the panel keys worth keeping here.
      Keys.onEscapePressed: root.focus = true
      Keys.onUpPressed: root.moveRequested(-1)
      Keys.onDownPressed: root.moveRequested(1)
      Keys.onReturnPressed: root.activateRequested()
      Keys.onEnterPressed: root.activateRequested()

      onTextChanged: searchDebounce.restart()
    }

    Timer {
      id: searchDebounce
      interval: 260
      repeat: false
      onTriggered: if (root.service) root.service.search(search.text)
    }

    // The list scrolls inside its own bounds, so the wheel over it moves rows rather
    // than the whole panel. ListView is used over a Repeater for positionViewAtIndex,
    // which is what keeps the j/k cursor on screen in a list this long.
    ListView {
      id: albumList
      width: parent.width
      height: Math.min(contentHeight, root.listMaxHeight)
      clip: true
      spacing: Style.space(2)
      model: root.results
      keyNavigationEnabled: false
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      // currentIndex is deliberately not bound to the panel's cursor. ListView writes
      // that property itself on every model swap, which breaks a QML binding for good
      // and would strand the highlight on row 0 while the panel still held its cursor.
      onCountChanged: if (root.cursorIndex >= 0) positionViewAtIndex(root.cursorIndex, ListView.Contain)

      delegate: CursorSurface {
        id: row
        required property var modelData
        required property int index

        width: albumList.width
        foreground: root.foreground
        hasCursor: index === root.cursorIndex
        current: row.isBrowsed
        implicitHeight: albumLabel.implicitHeight + Style.spacing.rowPaddingX

        // The playlist the song list is currently showing reads as the picked row,
        // so a search returning it lands on something that already looks selected.
        readonly property bool isBrowsed: !!modelData
          && String(modelData.kind || "") === "playlist"
          && root.service
          && String(modelData.name || "") === String(root.service.browsedPlaylist || "")

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.service.playResult(modelData)
        }

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)

          Text {
            id: albumLabel
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: (row.isBrowsed ? "♪ " : "") + (modelData.artist ? modelData.artist + " · " : "") + modelData.name
            color: row.isBrowsed ? root.foreground : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            font.bold: row.isBrowsed
          }

          // The kind is the load-bearing detail once one list mixes three of them.
          Text {
            textFormat: Text.PlainText
            text: row.isBrowsed
              ? String(root.strings.playingNow || "PLAYING") 
              : String(modelData.kind || "").toUpperCase()
            color: row.isBrowsed ? Color.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.2
            font.bold: row.isBrowsed
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
      visible: root.results.length === 0
    }
  }

  // Only offered when nothing holds the socket. cliamp allows one instance per user, so
  // waking it while the daemon runs would start a second, IPC-less copy that this
  // panel cannot see. The row wakes the headless daemon in the background — no terminal.
  CursorSurface {
    width: parent.width
    foreground: root.foreground
    visible: !root.cliampRunning
    implicitHeight: startLabel.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.service.wakeDaemon()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        id: startLabel
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: String(root.strings.startCliamp || "Start cliamp")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: "f  ›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
