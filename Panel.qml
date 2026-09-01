import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget + popup for choosing where links open.
//
// Two views share one popup. The switch view is the everyday one and is
// deliberately one click deep: open, click a client, done. The manage view
// is behind a "Configure" row because adding and deleting clients is rare
// next to switching between them.
Panel {
  id: root
  moduleName: "sven.browser-switcher"
  ipcTarget: "browser-switcher"
  manageIpc: false

  // ------------------------------------------------------------- appearance
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ------------------------------------------------------------- panel state
  property bool manageMode: false
  property int cursorIndex: 0
  property bool cursorActive: false
  property string pendingDeleteId: ""
  property string editingColorId: ""
  property string statusMessage: ""
  // Set while an external file dialog is up, so the panel knows to come back
  // to the manage view once the dialog is done.
  property bool resumeManageAfterPick: false

  // One shared control height for every field, dropdown and button in the
  // manage view. TextField sizes itself from font + padding (30px) while
  // Dropdown uses controlHeight (28px), so left alone they sit a couple of
  // pixels apart and the row reads as misaligned.
  readonly property int controlH: Style.spacing.controlHeight

  // Border colours, chosen to stay distinguishable from each other as a thin
  // window border on both light and dark themes. The hex field below covers
  // any exact brand colour that isn't here.
  readonly property var palette: [
    "#D20F39", "#E2571A", "#DF8E1D", "#7A9A01", "#2E9E4F", "#179299", "#1F7AB8",
    "#3F5FCF", "#7A5CD0", "#8839EF", "#C2455F", "#7A6A5C", "#5B6B72", "#9AA5AB"
  ]

  readonly property var targets: switcher.targets
  readonly property var active: switcher.activeTarget

  function targetColor(target) {
    return target && target.color ? Qt.color(String(target.color)) : root.dim
  }

  function iconUrl(target) {
    if (!target) return ""
    var path = String(target.iconPath || "")
    return path.length > 0 ? "file://" + path : ""
  }

  function initials(target) {
    var name = target ? String(target.name || "?") : "?"
    return name.substring(0, 1).toUpperCase()
  }

  function switchTo(target) {
    if (!target) return
    switcher.use(target.id)
    root.close()
  }

  function setManageMode(on) {
    manageMode = on
    pendingDeleteId = ""
    editingColorId = ""
    statusMessage = ""
    cursorIndex = 0
    if (panelFlick) panelFlick.contentY = 0
  }

  // --------------------------------------------------------- keyboard cursor
  function moveCursor(dy) {
    cursorActive = true
    if (manageMode || targets.length === 0) return
    cursorIndex = Math.max(0, Math.min(targets.length - 1, cursorIndex + dy))
  }

  function activateCursor() {
    if (manageMode) return
    // With nothing configured, Enter does the only useful thing.
    if (targets.length === 0) { setManageMode(true); return }
    if (cursorIndex >= 0 && cursorIndex < targets.length) switchTo(targets[cursorIndex])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      setManageMode(false)
      switcher.refresh()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      pendingDeleteId = ""
      editingColorId = ""
    }
  }

  // Hand off to an external dialog cleanly. The panel is a layer-shell overlay
  // with a fullscreen click-catcher under it, so a normal window like the file
  // dialog opens *behind* it and the first click meant for the dialog hits the
  // catcher instead — which is what made this feel broken. Closing first means
  // there is nothing left to fight over, and we reopen where the user was.
  function chooseIcon(targetId) {
    resumeManageAfterPick = manageMode
    close()
    switcher.pickIcon(targetId)
  }

  Service {
    id: switcher
    settings: root.settings
  }

  Connections {
    target: switcher
    function onActionFinished(action, ok, message) {
      if (!ok) {
        root.statusMessage = message
        if (action === "pick" && root.resumeManageAfterPick) {
          root.resumeManageAfterPick = false
          root.open()
          root.manageMode = true
        }
        return
      }
      root.statusMessage = ""
      if (action === "pick" && root.resumeManageAfterPick) {
        root.resumeManageAfterPick = false
        root.open()
        root.manageMode = true
        return
      }
      if (action === "add") {
        addName.text = ""
        addName.forceActiveFocus()
      }
      root.pendingDeleteId = ""
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function configure(): string {
      root.open()
      root.manageMode = true
      return "ok"
    }
    function next(): string { switcher.cycle(1); return "ok" }
    function previous(): string { switcher.cycle(-1); return "ok" }
    function use(id: string): string { switcher.use(id); return "ok" }
    function active(): string { return switcher.activeTarget ? switcher.activeTarget.id : "" }
  }

  // ------------------------------------------------------------- bar button
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)

          Item {
            width: Style.space(16)
            height: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter

            Image {
              id: barIcon
              anchors.fill: parent
              source: root.iconUrl(root.active)
              sourceSize.width: 32
              sourceSize.height: 32
              fillMode: Image.PreserveAspectFit
              smooth: true
              visible: status === Image.Ready
            }

            // Fall back to a colour chip when no icon resolves — a target with
            // no logo yet should still be identifiable in the bar.
            Rectangle {
              anchors.centerIn: parent
              width: Style.space(11)
              height: width
              radius: width / 2
              visible: !barIcon.visible
              color: root.active ? root.targetColor(root.active) : "transparent"
              border.width: root.active ? 0 : 1
              border.color: root.barForeground
              opacity: root.active ? 1.0 : 0.6
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.setting("showLabel", false) && root.active && !(root.bar && root.bar.vertical)
            anchors.verticalCenter: parent.verticalCenter
            text: root.active ? String(root.active.name) : ""
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
            elide: Text.ElideRight
          }
        }
      }
    }

    onPressed: function(buttonCode) {
      // Right-click cycles without opening anything: the "pop over to the
      // other client for two minutes" case should not cost a menu.
      if (buttonCode === Qt.RightButton) switcher.cycle(1)
      else if (buttonCode === Qt.MiddleButton) { if (root.active) switcher.launch(root.active.id) }
      else root.toggle()
    }
  }

  // ----------------------------------------------------------------- popup
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
      // Typing in the manage view's fields must not be eaten by the panel's
      // own single-key shortcuts.
      blocked: root.manageMode
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.manageMode) root.setManageMode(false)
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "c" || t === "C") root.setManageMode(!root.manageMode)
        else if (t === "r" || t === "R") switcher.refresh()
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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ------------------------------------------------------- hero
          PanelHero {
            width: parent.width
            title: "Links open in"
            meta: root.active ? String(root.active.name) : "Nothing configured"
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display

                Image {
                  id: heroIcon
                  anchors.fill: parent
                  source: root.iconUrl(root.active)
                  sourceSize.width: 64
                  sourceSize.height: 64
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                  visible: status === Image.Ready
                }

                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  visible: !heroIcon.visible
                  color: root.active ? root.targetColor(root.active) : "transparent"
                  border.width: root.active ? 0 : 1
                  border.color: root.foreground
                }
              }
            }

            trailingControl: Component {
              PanelActionButton {
                // Both states need a real glyph: an empty string here rendered
                // an invisible-but-clickable button in the manage view.
                iconText: root.manageMode ? "󰅁" : "󰒓"
                tooltipText: root.manageMode ? "Back" : "Configure"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.setManageMode(!root.manageMode)
              }
            }
          }

          // --------------------------------------------- setup / problems
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: switcher.cliMissing || root.statusMessage !== "" || switcher.lastError !== ""
              || (!switcher.cliMissing && !switcher.routerInstalled)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.statusMessage !== "" || switcher.lastError !== "" ? root.urgent : root.dim
              text: {
                if (switcher.cliMissing)
                  return "browser-switcher is not installed. Run ./install.sh from the plugin repo."
                if (root.statusMessage !== "") return root.statusMessage
                if (switcher.lastError !== "") return switcher.lastError
                if (!switcher.routerInstalled)
                  return "Not registered as your link handler yet — run: browser-switcher install --set-default"
                return ""
              }
            }
          }

          // ------------------------------------------------- switch view
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: !root.manageMode && !switcher.cliMissing

            PanelSectionHeader {
              // Nothing to label when the list is empty; the empty state
              // speaks for itself.
              visible: root.targets.length > 0
              text: "BROWSERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // First run has nothing to switch between, so the one thing worth
            // doing gets a real button. Once clients exist this disappears and
            // the gear in the header is the only way in — configuring is rare
            // next to switching, and shouldn't take up a row forever.
            EmptyState { visible: root.targets.length === 0; width: parent.width }

            Column {
              id: targetColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.targets
                SwitchRow {
                  required property var modelData
                  required property int index
                  width: targetColumn.width
                  target: modelData
                  rowIndex: index
                }
              }
            }

          }

          // ------------------------------------------------- manage view
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.manageMode && !switcher.cliMissing

            PanelSectionHeader {
              text: "CONFIGURE CLIENTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: manageColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.targets
                ManageRow {
                  required property var modelData
                  width: manageColumn.width
                  target: modelData
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "ADD A CLIENT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // Only name and browser here. Colour and logo are set from the
            // row once the client exists, which keeps this form to one line
            // and means the pickers always have a target to write to.
            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: addName
                Layout.fillWidth: true
                Layout.preferredHeight: root.controlH
                Layout.alignment: Qt.AlignVCenter
                verticalPadding: 0
                verticalAlignment: TextInput.AlignVCenter
                placeholderText: "Client name"
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onAccepted: addButton.commit()
              }

              Dropdown {
                id: addBrowser
                Layout.preferredWidth: Style.space(110)
                Layout.preferredHeight: root.controlH
                Layout.alignment: Qt.AlignVCenter
                rowHeight: root.controlH
                showLabel: false
                fontFamily: root.fontFamily
                options: switcher.browserOptions
                value: switcher.browserOptions.length > 0 ? switcher.browserOptions[0].value : "chromium"
              }

              PanelActionButton {
                id: addButton
                iconText: "󰐕"
                tooltipText: "Add client"
                foreground: root.foreground
                fontFamily: root.fontFamily
                size: root.controlH
                Layout.alignment: Qt.AlignVCenter
                enabled: addName.text.trim().length > 0
                function commit() {
                  var name = addName.text.trim()
                  if (name.length === 0) return
                  switcher.add(name, addBrowser.value, "")
                }
                onClicked: commit()
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Each client gets its own browser data directory, a badged icon and a coloured window border."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- components

  component SwitchRow: CursorSurface {
    id: switchRow
    property var target: null
    property int rowIndex: 0
    readonly property bool isActive: switchRow.target && switcher.activeId === switchRow.target.id

    hasCursor: root.cursorActive && !root.manageMode && root.cursorIndex === rowIndex
    current: isActive
    foreground: root.foreground
    implicitHeight: switchContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.cursorIndex = switchRow.rowIndex }
      onClicked: root.switchTo(switchRow.target)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(9)

      TargetIcon {
        target: switchRow.target
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: switchContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: switchRow.target ? String(switchRow.target.name) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: {
            if (!switchRow.target) return ""
            var parts = [String(switchRow.target.browser || "")]
            if (switchRow.target.available === false) parts.push("not installed")
            return parts.join(" · ")
          }
          color: switchRow.target && switchRow.target.available === false ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: switchRow.isActive
        text: "󰄬"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component EmptyState: Column {
    id: emptyState
    spacing: Style.space(10)

    Text {
      textFormat: Text.PlainText
      width: emptyState.width
      text: "No clients yet."
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
    }

    CursorSurface {
      width: emptyState.width
      hasCursor: root.cursorActive && !root.manageMode
      foreground: root.foreground
      bordered: true
      implicitHeight: emptyLabel.implicitHeight + Style.spacing.rowPaddingX

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.cursorActive = true
        onClicked: root.setManageMode(true)
      }

      Row {
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "󰐕"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        Text {
          id: emptyLabel
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: "Add your first client"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
  component TargetIcon: Item {
    id: targetIcon
    property var target: null
    property real size: Style.space(20)

    implicitWidth: size
    implicitHeight: size

    Image {
      id: image
      anchors.fill: parent
      source: root.iconUrl(targetIcon.target)
      sourceSize.width: 64
      sourceSize.height: 64
      fillMode: Image.PreserveAspectFit
      smooth: true
      visible: status === Image.Ready
    }

    // Coloured initial as the stand-in, so every row reads the same shape
    // whether or not a logo has been set.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      visible: !image.visible
      color: root.targetColor(targetIcon.target)

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.initials(targetIcon.target)
        color: Color.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  component ManageRow: Column {
    id: manageRow
    property var target: null
    readonly property bool confirming: manageRow.target && root.pendingDeleteId === manageRow.target.id
    readonly property bool editingColor: manageRow.target && root.editingColorId === manageRow.target.id

    spacing: Style.space(4)

    RowLayout {
      width: manageRow.width
      spacing: Style.space(6)

      TargetIcon {
        target: manageRow.target
        size: Style.space(18)
        Layout.alignment: Qt.AlignVCenter
      }

      // Renaming happens in place: the field is the name, and committing it
      // with Enter or by clicking away is the rename.
      TextField {
        id: nameField
        Layout.fillWidth: true
        Layout.preferredHeight: root.controlH
        Layout.alignment: Qt.AlignVCenter
        verticalPadding: 0
        verticalAlignment: TextInput.AlignVCenter
        text: manageRow.target ? String(manageRow.target.name) : ""
        foreground: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        onAccepted: commit()
        onActiveFocusChanged: if (!activeFocus) commit()

        function commit() {
          if (!manageRow.target) return
          var value = text.trim()
          if (value.length === 0) { text = String(manageRow.target.name); return }
          if (value === String(manageRow.target.name)) return
          switcher.rename(manageRow.target.id, value)
        }
      }

      // The swatch is the button, and it opens the picker *inside* the panel.
      // A colour chooser is a dozen swatches and a hex field; spawning a
      // separate window for that meant the panel dismissed itself, the dialog
      // opened underneath it, and the first click went nowhere.
      Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: root.controlH
        implicitHeight: root.controlH

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(18)
          height: Style.space(18)
          radius: Style.space(3)
          color: root.targetColor(manageRow.target)
          border.width: manageRow.editingColor ? 2 : 1
          border.color: manageRow.editingColor
            ? root.foreground
            : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
        }

        MouseArea {
          id: swatchMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!manageRow.target) return
            if (manageRow.editingColor) {
              root.editingColorId = ""
            } else {
              hexField.text = String(manageRow.target.color)
              root.editingColorId = manageRow.target.id
            }
          }

          PanelToolTip {
            visible: swatchMouse.containsMouse && !manageRow.editingColor
            text: "Border colour"
            fontFamily: root.fontFamily
          }
        }
      }

      PanelActionButton {
        iconText: "󰋩"
        tooltipText: "Choose logo"
        foreground: root.foreground
        fontFamily: root.fontFamily
        size: root.controlH
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (manageRow.target) root.chooseIcon(manageRow.target.id)
      }

      PanelActionButton {
        iconText: "󰩹"
        tooltipText: "Delete"
        foreground: manageRow.confirming ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        size: root.controlH
        Layout.alignment: Qt.AlignVCenter
        onClicked: {
          if (!manageRow.target) return
          root.pendingDeleteId = manageRow.confirming ? "" : manageRow.target.id
        }
      }
    }

    // Colour editor, expanded in place under its own row. Everything here is
    // in-panel, so picking a colour never costs the panel its focus.
    Column {
      visible: manageRow.editingColor
      width: manageRow.width
      spacing: Style.space(6)
      topPadding: Style.space(2)
      bottomPadding: Style.space(4)

      Grid {
        columns: 7
        spacing: Style.space(5)

        Repeater {
          model: root.palette

          Rectangle {
            required property string modelData
            readonly property bool chosen:
              manageRow.target
              && String(manageRow.target.color).toUpperCase() === modelData.toUpperCase()

            width: Style.space(22)
            height: Style.space(22)
            radius: Style.space(3)
            color: modelData
            border.width: chosen ? 2 : 0
            border.color: root.foreground

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!manageRow.target) return
                switcher.setColor(manageRow.target.id, parent.modelData)
                root.editingColorId = ""
              }
            }
          }
        }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        TextField {
          id: hexField
          Layout.fillWidth: true
          Layout.preferredHeight: root.controlH
          Layout.alignment: Qt.AlignVCenter
          verticalPadding: 0
          verticalAlignment: TextInput.AlignVCenter
          placeholderText: "#RRGGBB"
          text: manageRow.target ? String(manageRow.target.color) : ""
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          onAccepted: applyHex()

          // Accept what someone would actually paste: with or without the
          // leading hash, in either case. The CLI normalises it again.
          function applyHex() {
            if (!manageRow.target) return
            var v = text.trim().replace(/^#/, "")
            if (!/^[0-9A-Fa-f]{6}$/.test(v)) {
              text = String(manageRow.target.color)
              return
            }
            switcher.setColor(manageRow.target.id, "#" + v.toUpperCase())
            root.editingColorId = ""
          }
        }

        Button {
          text: "Set"
          fontFamily: root.fontFamily
          foreground: root.foreground
          // Bordered so it reads as the commit action for the field beside it
          // rather than as a stray label.
          bordered: true
          Layout.preferredHeight: root.controlH
          Layout.alignment: Qt.AlignVCenter
          onClicked: hexField.applyHex()
        }
      }
    }

    // Inline confirm rather than a modal: it keeps the destructive step one
    // deliberate click away without covering the list it refers to.
    RowLayout {
      width: manageRow.width
      visible: manageRow.confirming
      spacing: Style.space(6)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: manageRow.target
          ? "Delete " + manageRow.target.name + "? Browsing data is kept."
          : ""
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Button {
        text: "Delete"
        fontFamily: root.fontFamily
        foreground: root.urgent
        onClicked: if (manageRow.target) switcher.remove(manageRow.target.id)
      }

      Button {
        text: "Cancel"
        fontFamily: root.fontFamily
        foreground: root.foreground
        onClicked: root.pendingDeleteId = ""
      }
    }
  }
}
