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
  moduleName: "sven-strothoff.browser-switcher"
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
  // Opt-in, and reset every time a confirm opens or closes: deleting browsing
  // data is the one irreversible thing this panel can do, so it must never be
  // carried over from a previous row or a previous decision.
  property bool pendingPurge: false
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

  // How the bar widget presents the active client, from least to most
  // conspicuous. The badged icon is the clearest signal of which client is
  // live, but it is full-colour artwork sitting in a row of monochrome glyphs.
  //   plain  — a glyph, and nothing else: no indication of state at all
  //   dot    — bar-coloured glyph with a small client-colour dot
  //   tinted — the glyph itself in the client's colour
  //   icon   — the full-colour badged icon
  readonly property var barIconOptions: [
    "No indicator", "Colour dot", "Coloured glyph", "Profile icon"
  ]
  readonly property string barIconSetting: String(root.setting("barIcon", "Colour dot"))

  // Matched loosely, and deliberately: the stored value is a display label, so
  // this has to keep honouring the labels earlier versions wrote
  // ("Theme", "Client colour", "Full colour") as well as the current ones.
  readonly property string barIconMode: root.barIconModeFor(root.barIconSetting)

  // Catppuccin Latte accents, which Omarchy already ships as a theme, so the
  // palette reads as part of the desktop rather than invented for this panel.
  // Latte rather than Mocha because its accents are darker and stay visible as
  // a thin border on light and dark themes alike.
  //
  // Eleven of the fourteen: flamingo, maroon and sapphire are dropped because
  // they sit too close to rosewater, red and teal to tell apart at border
  // width. Measured as CIE76 ΔE in Lab, the full set has a closest pair of
  // 10.1 and this subset 21.3 — a colour nobody can distinguish is no use as
  // an identity. Plus one neutral (overlay1) for a profile that wants no
  // strong colour. The hex field beside the grid covers anything not here.
  readonly property var palette: [
    "#D20F39", "#FE640B", "#DF8E1D", "#40A02B", "#179299", "#04A5E5",
    "#1E66F5", "#7287FD", "#8839EF", "#EA76CB", "#DC8A78", "#8C8FA1"
  ]

  readonly property var targets: switcher.targets
  readonly property var profileTargets: targets.filter(function(t) { return isProfile(t) })
  readonly property var systemTargets: targets.filter(function(t) { return !isProfile(t) })
  readonly property var active: switcher.activeTarget

  // Label -> mode, so the preview cells and the live bar agree on what each
  // option means without duplicating the matching rules.
  function barIconModeFor(label) {
    var v = String(label || "").toLowerCase()
    if (v.indexOf("dot") >= 0 || v.indexOf("theme") >= 0) return "dot"
    if (v.indexOf("no indicator") >= 0 || v.indexOf("plain") >= 0) return "plain"
    if (v.indexOf("glyph") >= 0 || v.indexOf("tint") >= 0
        || v.indexOf("accent") >= 0 || v.indexOf("client colour") >= 0
        || v.indexOf("client color") >= 0) return "tinted"
    if (v.indexOf("icon") >= 0 || v.indexOf("full") >= 0) return "icon"
    return "dot"
  }

  // Previews need a profile to draw, otherwise three of the four options would
  // look identical whenever a system browser happens to be active.
  readonly property var previewTarget: {
    if (isProfile(active)) return active
    for (var i = 0; i < targets.length; i++) {
      if (isProfile(targets[i])) return targets[i]
    }
    return active
  }
  readonly property color previewColor: {
    return isProfile(previewTarget) ? targetColor(previewTarget) : Color.accent
  }

  // This widget's own setting, so it is written the way first-party widgets
  // write theirs: applied locally for an immediate redraw, then persisted into
  // our shell.json entry through the shell. No subprocess, and it degrades to
  // a session-only preference if the widget is not in the layout — which also
  // removes the last place the plugin id was hardcoded twice.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) {
      if (existing !== "id") entry[existing] = root.settings[existing]
    }
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  function targetColor(target) {
    return target && target.color ? Qt.color(String(target.color)) : root.dim
  }

  function iconUrl(target) {
    if (!target) return ""
    var path = String(target.iconPath || "")
    return path.length > 0 ? "file://" + path : ""
  }

  // Anything not explicitly a system browser is a profile — which also keeps
  // configs written before the rename (kind: "client") reading correctly.
  function isProfile(target) {
    return !target || String(target.kind || "profile") !== "browser"
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
    pendingPurge = false
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
      pendingPurge = false
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
    function cliPath(): string { return switcher.cli }
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

            // Full-colour badged artwork.
            TargetIcon {
              anchors.fill: parent
              visible: root.barIconMode === "icon"
              target: root.active
              plain: true
            }

            // Bar-native glyph. Tinted with the client colour, or left in the
            // bar's own foreground with the colour carried by the dot below.
            Text {
              id: barGlyph
              anchors.centerIn: parent
              visible: root.barIconMode !== "icon"
              text: "󰖟"
              // A system browser has no colour of its own, so "tinted" falls
              // back to the bar's own foreground rather than to targetColor's
              // grey placeholder — which just read as a slightly different grey.
              color: root.barIconMode === "tinted" && root.isProfile(root.active)
                ? root.targetColor(root.active)
                : root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.bar.iconFont
            }

            Rectangle {
              visible: root.barIconMode === "dot" && root.active !== null
                && root.isProfile(root.active)
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              width: Style.space(6)
              height: width
              radius: width / 2
              color: root.active ? root.targetColor(root.active) : "transparent"
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
      // Right-click opens a window of whatever is selected — the common follow
      // -up to switching, and the one action worth having without a menu.
      // Cycling moves to middle-click; it is also on the `next` IPC method for
      // anyone who would rather bind it to a key.
      if (buttonCode === Qt.RightButton) { if (root.active) switcher.launch(root.active.id) }
      else if (buttonCode === Qt.MiddleButton) switcher.cycle(1)
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
              TargetIcon {
                target: root.active
                size: Style.font.display
                plain: root.active === null
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

          // --------------------------------------------- errors and setup
          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            color: root.urgent
            text: {
              if (switcher.cliMissing)
                return "browser-switcher could not be found inside the plugin directory."
              if (root.statusMessage !== "") return root.statusMessage
              if (switcher.lastError !== "") return switcher.lastError
              return ""
            }
          }

          // Until the router is the system's link handler the switcher decides
          // nothing, so this is the one piece of setup worth interrupting for —
          // and worth being a button rather than a copyable command, since a
          // plugin installed from the repository never ran an install script.
          Column {
            visible: !switcher.cliMissing && !switcher.isDefaultBrowser
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Links don't come here yet. Until Browser Switcher handles them, "
                + "choosing an entry changes nothing."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Button {
              // Progress for *this* action only: a colour change elsewhere in
              // the panel should not make this button claim to be setting up.
              readonly property bool working: switcher.currentAction === "install"
              text: working ? "Setting up…" : "Make this the default browser"
              fontFamily: root.fontFamily
              foreground: root.foreground
              bordered: true
              enabled: !working
              width: parent.width
              onClicked: switcher.makeDefault()
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
              visible: root.profileTargets.length > 0
              text: "PROFILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: manageColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.profileTargets
                ProfileRow {
                  required property var modelData
                  width: manageColumn.width
                  target: modelData
                }
              }
            }

            PanelSectionHeader {
              visible: root.systemTargets.length > 0
              text: "SYSTEM BROWSERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: systemColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.systemTargets
                SystemRow {
                  required property var modelData
                  width: systemColumn.width
                  target: modelData
                }
              }
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "ADD A PROFILE"
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
                placeholderText: "Profile name"
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onAccepted: addButton.commit()
              }

              Select {
                id: addBrowser
                Layout.preferredWidth: Style.space(110)
                Layout.preferredHeight: root.controlH
                Layout.alignment: Qt.AlignVCenter
                rowHeight: root.controlH
                fontFamily: root.fontFamily
                options: switcher.browserOptions
                value: switcher.browserOptions.length > 0 ? switcher.browserOptions[0].value : "chromium"
              }

              PanelActionButton {
                id: addButton
                iconText: "󰐕"
                tooltipText: "Add profile"
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
              text: "A profile gets its own browser data directory — separate logins and history — plus a badged icon and a coloured window border."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // A plain browser, in its own default profile, as a switch
            // destination. Nothing is generated for it — no profile, no icon,
            // no window rule — so it needs no name, colour or logo either.
            Column {
              width: parent.width
              spacing: Style.space(10)
              visible: switcher.addableBrowsers.length > 0

              PanelSeparator { foreground: root.foreground }

              PanelSectionHeader {
                text: "ADD A SYSTEM BROWSER"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Select {
                  id: systemBrowser
                  Layout.fillWidth: true
                  Layout.preferredHeight: root.controlH
                  Layout.alignment: Qt.AlignVCenter
                  rowHeight: root.controlH
                  fontFamily: root.fontFamily
                  options: switcher.addableBrowsers
                  value: switcher.addableBrowsers.length > 0
                    ? switcher.addableBrowsers[0].value : ""
                }

                PanelActionButton {
                  iconText: "󰐕"
                  tooltipText: "Add system browser"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  size: root.controlH
                  Layout.alignment: Qt.AlignVCenter
                  enabled: systemBrowser.value !== ""
                  onClicked: if (systemBrowser.value !== "") switcher.addBrowser(systemBrowser.value)
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Opens in the browser's normal profile, with its own icon and no window colouring."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "BAR ICON"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // A visual setting deserves a visual control: each cell renders
            // exactly what the bar will look like, so the choice is made by
            // looking rather than by reading four labels.
            Row {
              id: barIconRow
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.barIconOptions

                CursorSurface {
                  id: previewCell
                  required property string modelData
                  required property int index

                  readonly property string mode: root.barIconModeFor(modelData)
                  readonly property bool chosen: root.barIconMode === mode

                  width: (barIconRow.width - Style.space(6) * 3) / 4
                  implicitHeight: Style.space(34)
                  current: chosen
                  bordered: true
                  foreground: root.foreground

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!previewCell.chosen) root.persistSettings({ barIcon: previewCell.modelData })

                    PanelToolTip {
                      visible: parent.containsMouse
                      text: previewCell.modelData
                      fontFamily: root.fontFamily
                    }
                  }

                  Item {
                    anchors.centerIn: parent
                    width: Style.space(18)
                    height: Style.space(18)

                    TargetIcon {
                      anchors.fill: parent
                      visible: previewCell.mode === "icon"
                      target: root.previewTarget
                      plain: true
                    }

                    Text {
                      anchors.centerIn: parent
                      visible: previewCell.mode !== "icon"
                      text: "󰖟"
                      color: previewCell.mode === "tinted"
                        ? root.previewColor : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                    }

                    Rectangle {
                      visible: previewCell.mode === "dot"
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      width: Style.space(7)
                      height: width
                      radius: width / 2
                      color: root.previewColor
                    }
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.barIconSetting + " — how the bar shows which entry is active. "
                + "Later options are clearer at a glance; earlier ones sit more quietly "
                + "beside the other bar icons."
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
          // A system browser's name is already the browser's name, so
          // repeating it underneath said nothing. A profile's subtitle earns
          // its place: it is the only thing saying which browser it runs.
          text: {
            if (!switchRow.target) return ""
            if (switchRow.target.available === false) return "not installed"
            return root.isProfile(switchRow.target)
              ? String(switchRow.target.browser || "") : ""
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
      text: "Nothing to switch between yet."
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
          text: "Add your first profile"
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
    // `plain` drops the coloured-initial fallback, for the bar where a blank
    // slot is better than a stand-in.
    property bool plain: false

    // The badged PNG keeps one filename for its whole life, so re-colouring a
    // client rewrites the file without changing the URL and Qt happily serves
    // the pixmap it already cached — the icon only caught up on a shell
    // restart. Reload it by hand whenever the version the CLI reports moves.
    readonly property int version: target ? Number(target.iconVersion || 0) : 0
    readonly property string url: root.iconUrl(target)

    onVersionChanged: reload()
    onUrlChanged: reload()
    Component.onCompleted: reload()

    function reload() {
      image.source = ""
      image.source = targetIcon.url
    }

    implicitWidth: size
    implicitHeight: size

    Image {
      id: image
      anchors.fill: parent
      cache: false
      sourceSize.width: 64
      sourceSize.height: 64
      fillMode: Image.PreserveAspectFit
      smooth: true
      visible: status === Image.Ready

      // Removing a target deletes its icon while the panel may still be
      // holding the pre-refresh copy of that target, so the load fails and
      // every Image instance logs it. Drop the source on error: the fallback
      // renders, and the shell log stays readable.
      onStatusChanged: if (status === Image.Error) source = ""
    }

    // Coloured initial as the stand-in, so every row reads the same shape
    // whether or not a logo has been set.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      visible: !image.visible && !targetIcon.plain
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
  // Profiles and system browsers get different rows on purpose. A profile is
  // ours to configure — rename, colour, logo. A system browser is just a
  // pointer at an existing install, so its name is the browser's name and is
  // not ours to change; showing an edit box for it invited a rename that would
  // only ever make the list less accurate.
  component ProfileRow: Column {
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

      DeleteButton { target: manageRow.target; confirming: manageRow.confirming }
    }

    // Colour editor, expanded in place under its own row.
    Column {
      visible: manageRow.editingColor
      width: manageRow.width
      spacing: Style.space(6)
      topPadding: Style.space(2)
      bottomPadding: Style.space(4)

      Grid {
        columns: 6
        spacing: Style.space(5)

        Repeater {
          model: root.palette

          Rectangle {
            id: swatchCell
            required property string modelData
            readonly property bool chosen:
              manageRow.target
              && String(manageRow.target.color).toUpperCase()
                 === swatchCell.modelData.toUpperCase()

            width: Style.space(22)
            height: Style.space(22)
            radius: Style.space(3)
            color: swatchCell.modelData
            border.width: swatchCell.chosen ? 2 : 0
            border.color: root.foreground

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              // Reached through the delegate's own id rather than `parent`:
              // the required property lives on the delegate, and going via
              // `parent` from a nested item is the fragile way to ask for it.
              onClicked: {
                if (!manageRow.target) return
                switcher.setColor(manageRow.target.id, swatchCell.modelData)
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
          bordered: true
          Layout.preferredHeight: root.controlH
          Layout.alignment: Qt.AlignVCenter
          onClicked: hexField.applyHex()
        }
      }
    }

    DeleteConfirm {
      width: manageRow.width
      target: manageRow.target
      visible: manageRow.confirming
      note: "Its browsing data is kept unless you say otherwise."
    }
  }

  component SystemRow: Column {
    id: systemRow
    property var target: null
    readonly property bool confirming: systemRow.target && root.pendingDeleteId === systemRow.target.id

    spacing: Style.space(4)

    RowLayout {
      width: systemRow.width
      spacing: Style.space(6)

      TargetIcon {
        target: systemRow.target
        size: Style.space(18)
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        Layout.preferredHeight: root.controlH
        Layout.alignment: Qt.AlignVCenter
        verticalAlignment: Text.AlignVCenter
        text: systemRow.target ? String(systemRow.target.name) : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      DeleteButton { target: systemRow.target; confirming: systemRow.confirming }
    }

    DeleteConfirm {
      width: systemRow.width
      target: systemRow.target
      visible: systemRow.confirming
      note: "The browser itself is untouched."
    }
  }

  component DeleteButton: PanelActionButton {
    property var target: null
    property bool confirming: false

    iconText: "󰩹"
    tooltipText: "Remove"
    foreground: confirming ? root.urgent : root.foreground
    fontFamily: root.fontFamily
    size: root.controlH
    Layout.alignment: Qt.AlignVCenter
    onClicked: {
      if (!target) return
      root.pendingPurge = false
      root.pendingDeleteId = confirming ? "" : target.id
    }
  }

  // Inline confirm rather than a modal: it keeps the destructive step one
  // deliberate click away without covering the list it refers to.
  component DeleteConfirm: Column {
    id: confirmBox
    property var target: null
    property string note: ""
    // Only a profile owns browsing data; a system browser has nothing of ours
    // to delete, so it never offers the option.
    readonly property bool canPurge: root.isProfile(confirmBox.target)

    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      width: confirmBox.width
      text: confirmBox.target
        ? "Remove " + confirmBox.target.name + "? " + confirmBox.note : ""
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    // A toggle rather than a second button: an irreversible action should take
    // a deliberate opt-in, not sit one misclick away from the safe one.
    Toggle {
      visible: confirmBox.canPurge
      width: confirmBox.width
      label: "Delete browsing data too"
      description: "Logins, cookies and history for this profile. Cannot be undone."
      checked: root.pendingPurge
      foreground: root.foreground
      accent: root.urgent
      fontFamily: root.fontFamily
      titleSize: Style.font.bodySmall
      onClicked: root.pendingPurge = !root.pendingPurge
    }

    RowLayout {
      width: confirmBox.width
      spacing: Style.space(6)

      Item { Layout.fillWidth: true }

      Button {
        text: root.pendingPurge && confirmBox.canPurge ? "Remove and delete data" : "Remove"
        fontFamily: root.fontFamily
        foreground: root.urgent
        bordered: true
        onClicked: {
          if (!confirmBox.target) return
          switcher.remove(confirmBox.target.id,
                          root.pendingPurge && confirmBox.canPurge)
        }
      }

      Button {
        text: "Cancel"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: { root.pendingPurge = false; root.pendingDeleteId = "" }
      }
    }
  }
}
