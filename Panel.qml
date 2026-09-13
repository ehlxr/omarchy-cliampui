import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Strings.js" as Strings

Panel {
  id: root
  moduleName: "io.github.ehlxr.cliampui"
  ipcTarget: "cliampui"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool hideWhenStopped: Model.asBool(setting("hideWhenStopped", true), true)
  readonly property color barIconColor: cliamp.isPlaying
    ? root.barForeground
    : Qt.darker(root.barForeground, 1.55)

  readonly property real seekStepSec: 5

  property bool sheetOpen: false
  property bool libraryOpen: false
  property bool songListOpen: false
  property int phraseIndex: 0
  // Cursor rows only exist while the output sheet is open, so the arrows never land
  // on a control that is not currently on screen.
  property int cursorIndex: -1

  readonly property int phraseIntervalMs: 2800

  // interface language. Auto follows the desktop locale; ticking one language pins it.
  readonly property string languageSetting: String(setting("language", "Auto") || "Auto")
  readonly property string localeName: Qt.locale() ? Qt.locale().name : ""
  readonly property string languageKey: Strings.localeKey(localeName, languageSetting)
  // The row for the resolved key, English when the setting pins that or the display
  // locale is not a supported one. Localized strings reach every child through this
  // single object, and Service.verdict reads its phrase table from the same source.
  readonly property var strings: Strings.table(languageKey)

  // Ten, matching the stock panels. English is the fallback carried by Strings.js so
  // every saved setting still resolves here even before any localization ships.
  readonly property var activePhrases: (root.strings && root.strings.heroPhrases)
    ? root.strings.heroPhrases
    : [
      "Bits arriving intact",
      "Straight off your own shelf",
      "No middleman on this signal",
      "Clock locked to source",
      "Spinning up the platter",
      "Needle in the groove",
      "Nothing resampled here",
      "Self-hosted and loud",
      "Signal path is short",
      "Whipping the terminal"
    ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  // Leaves the bar entirely when there is nothing to say, rather than sitting empty.
  visible: cliamp.running || !hideWhenStopped
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function moveCursor(delta) {
    var count = root.songListOpen ? cliamp.browsedTracks.length
      : root.libraryOpen ? cliamp.results.length
      : cliamp.sinks.length
    if (count === 0) { cursorIndex = -1; return }
    // A first press from an empty cursor lands on the first row; later presses wrap.
    var base = cursorIndex < 0 ? (delta > 0 ? -1 : 0) : cursorIndex
    cursorIndex = (base + delta + count) % count
  }

  function activateCursor() {
    if (root.songListOpen) {
      // The song list's Enter is the same Play that a double click means.
      var rows = cliamp.browsedTracks
      if (cursorIndex < 0 || cursorIndex >= rows.length) return
      cliamp.playBrowsedTrack(rows[cursorIndex])
      return
    }
    var list = root.libraryOpen ? cliamp.results : cliamp.sinks
    if (cursorIndex < 0 || cursorIndex >= list.length) return
    if (root.libraryOpen) cliamp.playResult(list[cursorIndex])
    else cliamp.setDevice(String(list[cursorIndex].name || ""))
  }

  Service {
    id: cliamp
    settings: root.settings
    panelOpen: root.opened
    strings: root.strings

    // A keystroke narrows the search under the cursor, and an index past the end
    // highlights no row while enter quietly does nothing, so it goes back to the top.
    onResultsChanged: if (root.cursorIndex >= cliamp.results.length) root.cursorIndex = 0
    // Sinks and the browsed rows swap out as their pages land; a cursor past the new
    // end lands on the last row rather than pointing at empty space.
    onBrowsedTracksChanged: if (root.cursorIndex >= cliamp.browsedTracks.length) {
      root.cursorIndex = cliamp.browsedTracks.length - 1
    }
  }

  Timer {
    id: phraseTimer
    interval: root.phraseIntervalMs
    repeat: true
    running: root.opened && !cliamp.hasTrack
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function playpause(): string { cliamp.playPause(); return "ok" }
    function signal(): string { return cliamp.signalVerdict.text }
    function output(): string {
      root.sheetOpen = !root.sheetOpen
      root.libraryOpen = false
      root.songListOpen = false
      root.cursorIndex = -1
      return root.sheetOpen ? "open" : "closed"
    }
    function library(): string {
      root.libraryOpen = !root.libraryOpen
      root.sheetOpen = false
      root.songListOpen = false
      root.cursorIndex = -1
      return root.libraryOpen ? "open" : "closed"
    }
    function songlist(): string {
      root.songListOpen = !root.songListOpen
      root.sheetOpen = false
      root.libraryOpen = false
      root.cursorIndex = -1
      return root.songListOpen ? "open" : "closed"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        CliampIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) cliamp.playPause()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Every letter is forwarded to a focused editor as well as to onTextKey, so a
      // search for a track name would otherwise skip tracks and launch a terminal.
      // The dropdown's popup owns the arrow keys while it is open, so they must not
      // also drive the panel cursor.
      blocked: library.searchFocused || songList.searchFocused

      onMoveRequested: function (dx, dy) {
        if (dy !== 0 && (root.songListOpen || root.libraryOpen || root.sheetOpen)) {
          root.moveCursor(dy)
          return
        }
        if (dx !== 0) cliamp.seekBy(dx > 0 ? root.seekStepSec : -root.seekStepSec)
      }
      onActivateRequested: {
        if (root.songListOpen || root.libraryOpen || root.sheetOpen) root.activateCursor()
        else cliamp.playPause()
      }
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t).toLowerCase()
        // Not j, k, l, h or x: the catcher consumes those before this handler runs.
        if (key === "o") { root.sheetOpen = !root.sheetOpen; root.libraryOpen = false; root.songListOpen = false; root.cursorIndex = -1 }
        else if (key === "t") { root.songListOpen = !root.songListOpen; root.sheetOpen = false; root.libraryOpen = false; root.cursorIndex = -1 }
        else if (key === "/") { root.libraryOpen = !root.libraryOpen; root.sheetOpen = false; root.songListOpen = false; root.cursorIndex = -1 }
        else if (key === "f") cliamp.openPlayer()
        else if (!cliamp.running) return
        else if (key === "n") cliamp.next()
        else if (key === "b") cliamp.previous()
        else if (key === "s") cliamp.selectKey("shuffle")
        else if (key === "r") cliamp.selectKey("r")
        else if (key === "p") cliamp.followSourceRate ? cliamp.releaseRate() : cliamp.matchRate()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        // Indicator only: an interactive bar lays a hit strip over content the
        // keyboard already reaches, and the library list scrolls itself.
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; interactive: false }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          NowPlaying {
            width: parent.width
            bar: root.bar
            service: cliamp
            strings: root.strings
            phrase: root.heroPhraseText
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Transport {
            width: parent.width
            bar: root.bar
            service: cliamp
            strings: root.strings
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Library {
            id: library
            width: parent.width
            service: cliamp
            foreground: root.foreground
            fontFamily: root.fontFamily
            strings: root.strings
            expanded: root.libraryOpen
            cursorIndex: root.libraryOpen ? root.cursorIndex : -1
            onMoveRequested: function (delta) { root.moveCursor(delta) }
            onActivateRequested: root.activateCursor()
            onToggleRequested: { root.libraryOpen = !root.libraryOpen; root.sheetOpen = false; root.songListOpen = false; root.cursorIndex = -1 }
          }

          SongList {
            id: songList
            width: parent.width
            service: cliamp
            foreground: root.foreground
            fontFamily: root.fontFamily
            expanded: root.songListOpen
            cursorIndex: root.songListOpen ? root.cursorIndex : -1
            strings: root.strings
            onToggleRequested: { root.songListOpen = !root.songListOpen; root.sheetOpen = false; root.libraryOpen = false; root.cursorIndex = -1 }
            onCursorRequested: function (index) { root.cursorIndex = index }
            onMoveRequested: function (delta) { root.moveCursor(delta) }
            onActivateRequested: root.activateCursor()
          }

          OutputSheet {
            width: parent.width
            service: cliamp
            foreground: root.foreground
            fontFamily: root.fontFamily
            strings: root.strings
            expanded: root.sheetOpen
            cursorIndex: root.sheetOpen ? root.cursorIndex : -1
            onToggleRequested: { root.sheetOpen = !root.sheetOpen; root.libraryOpen = false; root.songListOpen = false; root.cursorIndex = -1 }
          }
        }
      }
    }
  }

  onOpenedChanged: {
    if (!opened) { sheetOpen = false; libraryOpen = false; songListOpen = false; return }
    if (panelFlick) panelFlick.contentY = 0
    cursorIndex = -1
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }
}
