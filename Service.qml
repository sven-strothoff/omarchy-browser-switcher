import QtQuick
import Quickshell
import Quickshell.Io

// Headless state for the browser switcher.
//
// The CLI owns every piece of truth — which targets exist, which one is
// active, what each one's icon resolves to — and this service is a thin
// cache of `browser-switcher list --json` in front of it. Keeping the logic
// on that side means the panel, the terminal, and a keybind all go through
// exactly one implementation and cannot disagree.
//
// Refreshes are driven by file watches rather than polling: the CLI writes
// its config and state files atomically, so a change from any source (this
// panel, a shell command, another machine syncing the config) shows up here
// without the panel having to be open.
Item {
  id: root

  property var settings: ({})

  readonly property string home: Quickshell.env("HOME")

  // Resolved relative to this file, so the CLI is found wherever the plugin
  // happens to live. `omarchy plugin add` only clones and enables — it never
  // runs an install script — so a plugin installed from the repository has
  // nothing on PATH and no ~/.local/bin symlink. The copy shipped inside the
  // plugin directory is the one thing guaranteed to be there.
  readonly property string bundledCli: {
    var url = String(Qt.resolvedUrl("bin/browser-switcher"))
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }
  readonly property string cli: setting("cliPath", bundledCli)

  property var targets: []
  // Ready-made {label, value} pairs for the add-client dropdown; only
  // browsers actually present on the system are offered.
  property var browserOptions: []
  // Installed browsers not yet in the switcher as themselves, for the
  // "add a system browser" row.
  property var addableBrowsers: []
  property string activeId: ""
  property bool routerInstalled: false
  property bool isDefaultBrowser: false
  property bool cliMissing: false
  property bool loading: false
  property string lastError: ""

  readonly property var activeTarget: {
    for (var i = 0; i < targets.length; i++) {
      if (targets[i].id === activeId) return targets[i]
    }
    return targets.length > 0 ? targets[0] : null
  }
  readonly property bool ready: !cliMissing && targets.length > 0

  signal actionFinished(string action, bool ok, string message)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (listProcess.running) return
    loading = true
    listProcess.command = [cli, "list", "--json"]
    listProcess.running = true
  }

  function applyList(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (e) {
      lastError = "Could not parse browser-switcher output"
      return
    }
    targets = Array.isArray(parsed.targets) ? parsed.targets : []

    var options = []
    var browsers = Array.isArray(parsed.browsers) ? parsed.browsers : []
    for (var i = 0; i < browsers.length; i++) {
      options.push({ label: String(browsers[i].name), value: String(browsers[i].id) })
    }
    browserOptions = options

    var taken = {}
    for (var j = 0; j < targets.length; j++) {
      if (String(targets[j].kind) === "browser") taken[String(targets[j].browser)] = true
    }
    var addable = []
    for (var k = 0; k < options.length; k++) {
      if (!taken[options[k].value]) addable.push(options[k])
    }
    addableBrowsers = addable

    activeId = parsed.active ? String(parsed.active) : ""
    routerInstalled = parsed.installed === true
    isDefaultBrowser = parsed.isDefault === true
    lastError = ""
  }

  // ------------------------------------------------------------ mutations
  //
  // Every mutation is the same shape: run the CLI, let the file watch below
  // notice the resulting config change, and refresh from that. We do not
  // optimistically patch local state — switching is fast enough that a
  // wrong-then-corrected UI would be more jarring than a brief wait.

  // Only for commands that exit on their own. Anything that execs into a
  // long-lived program (launch) must go out detached instead, or it holds the
  // queue for as long as that program lives.
  //
  // Actions queue rather than being dropped. Previously a second action
  // arriving while one was in flight was silently discarded, so clicking a
  // colour during a slower command simply did nothing — and the slower the
  // command, the wider that window. Nothing here is long-running enough to
  // want cancellation, so a plain FIFO is the whole story.
  property var _queue: []

  function run(args, label) {
    var job = { args: args, label: label || (args.length > 0 ? args[0] : "") }
    if (actionProcess.running) {
      var q = _queue.slice()
      q.push(job)
      _queue = q
      return
    }
    _start(job)
  }

  function _start(job) {
    _actionLabel = job.label
    currentAction = job.label
    _actionOut = ""
    actionProcess.command = [cli].concat(job.args)
    actionProcess.running = true
  }

  function _next() {
    if (_queue.length === 0) { currentAction = ""; return }
    var q = _queue.slice()
    var job = q.shift()
    _queue = q
    _start(job)
  }

  // Which command is in flight, so a caller can show progress for its own
  // action instead of for any action at all.
  property string currentAction: ""

  function use(targetId) {
    var args = ["use", targetId, "--quiet"]
    if (setting("notifyOnSwitch", true)) args.push("--notify")
    run(args, "use")
  }

  function cycle(step) {
    if (targets.length < 2) return
    var index = 0
    for (var i = 0; i < targets.length; i++) {
      if (targets[i].id === activeId) { index = i; break }
    }
    var next = (index + step + targets.length) % targets.length
    use(targets[next].id)
  }

  // Detached, and deliberately not through run(): `launch` ends in an execv,
  // so the process *becomes* the browser and does not exit until that browser
  // window is closed. Routed through the shared action process it pinned the
  // queue for the lifetime of the browser — every later action sat waiting,
  // then all landed at once the moment the window closed.
  function launch(targetId) {
    Quickshell.execDetached([cli, "launch", targetId])
  }
  function rename(targetId, name) { run(["rename", targetId, name], "rename") }
  function remove(targetId) { run(["remove", targetId], "remove") }
  function setColor(targetId, hex) { run(["set", targetId, "--color", hex], "set-color") }

  // The file dialog is a normal toplevel window, while the panel is a
  // layer-shell overlay: the dialog can never draw above it, and the panel's
  // fullscreen dismiss layer eats the first click aimed at the dialog. The
  // panel therefore closes itself before calling this and reopens afterwards,
  // and the picker gets its own process so a dialog left open somewhere
  // cannot block switching or renaming.
  function pickIcon(targetId) { runPicker(["pick-icon", targetId]) }

  function runPicker(args) {
    if (pickerProcess.running) return
    pickerProcess.command = [cli].concat(args)
    pickerProcess.running = true
  }
  function reorder(targetId, direction) { run(["reorder", targetId, direction], "reorder") }

  function addBrowser(browser) { run(["add-browser", browser], "add-browser") }

  // Registers the router and takes over link handling. Deliberately a button
  // the user presses rather than something the plugin does on load: taking
  // over the default browser is a system-wide change and should be consented
  // to, not discovered.
  function makeDefault() { run(["install", "--set-default"], "install") }

  readonly property bool busy: listProcess.running || actionProcess.running
                              || _queue.length > 0

  // Bar appearance lives in the widget's own shell.json entry, not in the
  // switcher's config, so this goes through omarchy rather than our CLI. The
  // shell reloads shell.json on write, which feeds `settings` straight back to
  // the panel — no restart, and no local copy of the value to keep in sync.
  function setBarIcon(value) {
    if (barIconProcess.running) return
    barIconProcess.command = ["omarchy", "bar", "set", "sven.browser-switcher",
                              "barIcon", String(value)]
    barIconProcess.running = true
  }

  function add(name, browser, color) {
    var args = ["add", "--name", name]
    if (browser) args = args.concat(["--browser", browser])
    if (color) args = args.concat(["--color", color])
    run(args, "add")
  }

  property string _actionLabel: ""
  property string _actionOut: ""

  Process {
    id: listProcess
    running: false
    command: []
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    stderr: StdioCollector { id: listErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) {
        root.cliMissing = false
        root.applyList(String(listOut.text || ""))
      } else {
        // Exit 127 / "No such file" is the one failure worth calling out
        // specially: it means the CLI was never installed, which the panel
        // turns into setup instructions instead of an error.
        var err = String(listErr.text || "")
        if (exitCode === 127 || err.indexOf("No such file") >= 0) {
          root.cliMissing = true
          root.lastError = ""
        } else {
          root.lastError = err.split("\n")[0] || "browser-switcher failed"
        }
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var err = String(actionErr.text || "").replace(/^browser-switcher: (error: )?/, "").split("\n")[0]
      root.actionFinished(root._actionLabel, exitCode === 0, exitCode === 0 ? "" : err)
      if (exitCode !== 0) root.lastError = err
      else root.lastError = ""
      refreshDebounce.restart()
      root._next()
    }
  }

  Process {
    id: barIconProcess
    running: false
    command: []
    stderr: StdioCollector { id: barIconErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = String(barIconErr.text || "").split("\n")[0] || "Could not save bar icon style"
      }
    }
  }

  Process {
    id: pickerProcess
    running: false
    command: []
    stderr: StdioCollector { id: pickerErr; waitForEnd: true }
    onExited: function(exitCode) {
      // A cancelled dialog exits non-zero with nothing to say; only surface a
      // failure that actually produced an error message.
      var err = String(pickerErr.text || "").replace(/^browser-switcher: (error: )?/, "").split("\n")[0]
      if (exitCode !== 0 && err.length > 0) root.lastError = err
      root.actionFinished("pick", exitCode === 0 || err.length === 0, exitCode === 0 ? "" : err)
      refreshDebounce.restart()
    }
  }

  // The CLI writes config and state within milliseconds of each other; one
  // short debounce collapses both watch events into a single re-read.
  Timer {
    id: refreshDebounce
    interval: 120
    repeat: false
    onTriggered: root.refresh()
  }

  FileView {
    path: root.home + "/.config/browser-switcher/config.json"
    watchChanges: true
    printErrors: false
    onFileChanged: refreshDebounce.restart()
    onLoaded: refreshDebounce.restart()
  }

  FileView {
    path: root.home + "/.local/state/browser-switcher/active"
    watchChanges: true
    printErrors: false
    onFileChanged: refreshDebounce.restart()
    onLoaded: refreshDebounce.restart()
  }

  Component.onCompleted: refresh()
}
