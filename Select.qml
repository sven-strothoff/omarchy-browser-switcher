import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Single-select dropdown, styled to match qs.Ui.Dropdown but built so it
// cannot drift while you point at it.
//
// The shipped Dropdown budgets `Style.spacing.xxs` (2px) of vertical padding
// in its popup's implicitHeight while actually applying
// `Border.top + hairline` twice (4px). Its ListView viewport is therefore two
// pixels shorter than its own content, so it is always fractionally
// scrollable — and because the row delegate assigns `currentIndex` on hover,
// ListView scrolls to keep the current item visible. Pointing at the first or
// last row nudges the list by those two pixels. The deficit is constant, so it
// happens with any number of options, however much room the popup has.
//
// Rather than re-do the arithmetic and hope, this lays the rows out in a plain
// Column: nothing here tracks a current index for the view to chase, so there
// is no mechanism left to scroll. The Flickable only becomes interactive if
// the list genuinely outgrows the cap.
Item {
  id: root

  property string value: ""
  property var options: []

  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec(
    "popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)

  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property int maxVisibleRows: 8
  property bool hasCursor: false

  // When the popup is open, a press on the trigger is an *outside* press as
  // far as the popup is concerned, so its close-on-press-outside fires on the
  // press and the release then reaches the trigger with the popup already
  // closed. Reopening at that point makes clicking the control look inert.
  // Remember when a close happened and swallow exactly the click that caused
  // it — zeroing the mark straight after, so the very next click still opens.
  property double _closedAt: 0
  readonly property int _reopenGuardMs: 400

  readonly property bool popupOpen: popup.opened
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  signal changed(string value)
  signal hovered(bool isHovered)

  function optionValue(o) { return (o && typeof o === "object") ? String(o.value) : String(o) }
  function optionLabel(o) { return (o && typeof o === "object") ? String(o.label) : String(o) }
  function currentLabel() {
    for (var i = 0; i < options.length; i++) {
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    }
    return value
  }
  function select(v) {
    root.value = v
    root.changed(v)
    popup.close()
  }

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: rowHeight

  BorderSurface {
    id: trigger
    width: parent.width
    height: root.rowHeight
    radius: Style.cornerRadius
    activeFocusOnTab: true

    readonly property bool _focused: trigger.activeFocus
    readonly property bool _hot: triggerHover.hovered || root.hasCursor
    readonly property var _borderSpec: Border.controlSpec(
      trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"),
      root.foreground, root.accent)

    color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
    borderSpec: _borderSpec

    HoverHandler {
      id: triggerHover
      onHoveredChanged: root.hovered(hovered)
    }

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
          || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
        popup.opened ? popup.close() : popup.open()
        event.accepted = true
      } else if (event.key === Qt.Key_Escape && popup.opened) {
        popup.close()
        event.accepted = true
      }
    }

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: chevron.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.md
      text: root.currentLabel()
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    Text {
      id: chevron
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.rightMargin: Style.spacing.controlGap
      text: "\u{f0140}"
      color: Qt.darker(root.foreground, 1.2)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        trigger.forceActiveFocus()
        if (popup.opened) {
          popup.close()
          return
        }
        if (Date.now() - root._closedAt < root._reopenGuardMs) {
          root._closedAt = 0
          return
        }
        popup.open()
      }
    }

    Popup {
      id: popup
      x: 0
      y: trigger.height + Style.spacing.xxs
      width: trigger.width
      padding: Style.spacing.hairline
      leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
      rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
      topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
      bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
      focus: true

      // Derived from the real content and the padding actually applied, so the
      // viewport is never short of its own rows.
      readonly property int rowsHeight: root.options.length * root.popupRowHeight
      readonly property int capHeight: root.maxVisibleRows * root.popupRowHeight
      implicitHeight: Math.min(rowsHeight, capHeight) + topPadding + bottomPadding

      onClosed: root._closedAt = Date.now()

      background: BorderSurface {
        color: root.background
        borderSpec: root.popupBorderSpec
        radius: Style.cornerRadius
      }

      contentItem: Flickable {
        id: flick
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Only ever scrollable when the rows genuinely do not fit.
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width

          Repeater {
            model: root.options

            Rectangle {
              id: row
              required property var modelData
              readonly property bool selected: root.optionValue(row.modelData) === root.value

              width: column.width
              height: root.popupRowHeight
              color: rowHover.containsMouse || row.selected
                ? Style.hoverFillFor(root.foreground, root.accent)
                : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                text: root.optionLabel(row.modelData)
                color: rowHover.containsMouse || row.selected
                  ? Style.hoverStateColor(root.foreground, root.accent)
                  : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.select(root.optionValue(row.modelData))
              }
            }
          }
        }
      }
    }
  }
}
