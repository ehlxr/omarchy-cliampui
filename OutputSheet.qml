import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false
  // -1 means the keyboard cursor is not on this section, so no row is highlighted.
  property int cursorIndex: -1
  property var strings: ({})

  signal toggleRequested()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property var verdict: service ? service.signalVerdict : ({ ok: false, text: "" })

  spacing: Style.space(8)

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  // The whole section head is one clickable row: label on the left, the current
  // sink on the right beside the folding arrow, matching the other collapsible rows.
  CursorSurface {
    id: summary
    width: parent.width
    foreground: root.foreground
    implicitHeight: Math.max(outputHeader.implicitHeight, summaryLabel.implicitHeight) + Style.spacing.rowPaddingX

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
        id: outputHeader
        text: String(root.strings.sectionOutput || "OUTPUT")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Item { Layout.fillWidth: true }

      Text {
        id: summaryLabel
        textFormat: Text.PlainText
        text: root.service && root.service.currentSinkLabel !== ""
          ? root.service.currentSinkLabel
          : String(root.strings.noOutput || "No output")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
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
    spacing: Style.space(2)
    visible: root.expanded

    Repeater {
      model: root.service ? root.service.sinks : []

      CursorSurface {
        id: deviceRow
        width: root.width
        foreground: root.foreground
        hasCursor: index === root.cursorIndex
        implicitHeight: deviceLabel.implicitHeight + Style.spacing.rowPaddingX

        readonly property bool isCurrent: !!(root.service
          && root.service.currentSink
          && root.service.currentSink.id === modelData.id)

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.service.setDevice(String(modelData.name || ""))
        }

        RowLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(8)

          Text {
            id: deviceLabel
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: String(modelData.description || modelData.nickname || modelData.name || "")
            color: deviceRow.isCurrent ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            text: deviceRow.isCurrent ? "✓" : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }

  // Signal names itself on the same row that carries the verdict, so every section
  // head reads as a single line: label left, value right.
  CursorSurface {
    width: parent.width
    foreground: root.foreground
    visible: root.verdict.text.length > 0
    implicitHeight: Math.max(signalHeader.implicitHeight, verdictLabel.implicitHeight) + Style.spacing.rowPaddingX

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      PanelSectionHeader {
        id: signalHeader
        text: String(root.strings.sectionSignal || "SIGNAL")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Item { Layout.fillWidth: true }

      Text {
        id: verdictLabel
        textFormat: Text.PlainText
        text: root.verdict.text
        color: root.verdict.ok ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignRight
        // Wrapped rather than elided: the whole value of this line is the sentence
        // explaining why a route is not bit-perfect, and a cut one says nothing.
        wrapMode: Text.WordWrap
        Layout.alignment: Qt.AlignRight
      }

      Text {
        textFormat: Text.PlainText
        text: String(root.strings.matchRate || "Match rate")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.underline: true
        // Only offered when following is off, since with it on any mismatch is transient.
        visible: !!(root.service
          && !root.verdict.ok
          && !root.service.followSourceRate
          && root.service.streamRate > 0)

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.service.matchRate()
        }
      }
    }
  }
}
