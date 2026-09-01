# Browser Switcher

An Omarchy shell plugin that puts a browser picker in the bar. Click it, pick a
client, and every link you open from that point on lands in that browser's
isolated session.

Built for the case where "which browser" really means "whose work am I doing
right now" — a work Chromium, a personal Chromium, one per client, each with
its own cookies, logins and history.

## How it works

One indirection makes the whole thing cheap. A generated router entry,
`browser-switcher.desktop`, is registered **once** as your default web browser.
Every `http(s)` link therefore arrives at `browser-switcher open`, which reads a
one-line state file and re-launches the URL in whichever target is currently
selected.

```
link → xdg-open → browser-switcher.desktop → browser-switcher open
                                                    ↓
                                          reads ~/.local/state/…/active
                                                    ↓
                              chromium --user-data-dir=…/acme --class=chromium-acme
```

Switching is then a single small write, not a rewrite of `mimeapps.list`. It
takes effect instantly, for every app, with nothing to restart and no cache to
race against.

Isolation is by **data directory**, not Chromium profile. Profiles share far too
much to serve as a boundary between clients; a separate `--user-data-dir` is a
genuine separation — separate cookies, separate keyring entries, separate
process.

## Self-contained by design

The plugin assumes nothing about your machine beyond a stock Omarchy install.
It creates its own browser data directories, generates its own desktop entries
and icons, and installs its own launcher. There is no setup step you have to do
by hand first, and no file of yours it needs you to have written.

In particular it **edits no existing config file**. Window rules are covered
below; everything else it owns outright, under `browser-switcher`-prefixed
names carrying a "Do not edit" banner. Nothing it did not create is ever
written or deleted, and `add` refuses outright to create a target whose window
class would collide with a desktop entry it didn't write.

## What a client gets

Adding a client called `acme` creates:

| Thing | Where |
|---|---|
| Isolated browser data directory | `~/.local/share/browser-switcher/profiles/acme` |
| Desktop entry | `~/.local/share/applications/browser-switcher-acme.desktop` |
| Badged icon (7 sizes) | `~/.local/share/icons/hicolor/*/apps/browser-switcher-acme.png` |
| Hyprland border rule | `~/.local/state/omarchy/toggles/hypr/browser-switcher.lua` |
| An entry in the bar panel | — |

### Icons are generated, not supplied

You give it a logo — any PNG, JPG, SVG or WebP — and it does the compositing.
The client logo is placed on a filled disc in the client's colour and composited
onto the browser's own icon, rendered at all seven hicolor sizes. A client with
no logo yet still gets the coloured disc, so it stays identifiable at 16px.
Requires ImageMagick; `install.sh` checks for it.

```bash
browser-switcher set acme --icon ~/logos/acme.svg   # or: pick-icon, for a file dialog
```

### Supported browsers, and how each gets a per-client window identity

Every browser Omarchy can install (`omarchy install browser …`), plus the
preinstalled Chromium and the two extras Omarchy's own window rules already
recognise.

| Browser | Family | Profile isolation | Per-client app_id | Verified |
|---|---|---|---|---|
| Chromium | chromium | `--user-data-dir` | `--class` | yes, against `hyprctl` |
| Chrome, Brave, Brave Origin, Edge, Vivaldi | chromium | `--user-data-dir` | `--class` | same mechanism, not installed here |
| Zen | firefox | `--profile` | `MOZ_APP_REMOTINGNAME` | yes, against `hyprctl` |
| Firefox, LibreWolf | firefox | `--profile` | `MOZ_APP_REMOTINGNAME` | same mechanism as Zen, not installed here |

The two families set the window's app_id differently, and both paths were
tested against a live Hyprland rather than inferred:

- **Chromium** takes `--class=NAME`, which on Wayland becomes the app_id. A probe
  window reported `class=browser-switcher-classprobe`, `xwayland: false`.
- **Firefox-based browsers ignore `--class` on Wayland** — it only ever set the
  X11 `WM_CLASS`. Launching Zen with `--class=zen-probe-class` still produced
  app_id `zen`. `MOZ_APP_REMOTINGNAME` is what works: the same launch with
  `MOZ_APP_REMOTINGNAME=zen-acme` produced app_id `zen-acme`. Without it every
  Firefox-family client would share one app_id, so no per-client border colour
  could match and `StartupWMClass` would be wrong for all of them.

Two behaviours worth knowing, both measured rather than assumed:

- **Isolation comes from `--profile`, not from the remoting name.** Two different
  profile directories run as fully independent instances even when they share a
  remoting name. The remoting name is about window identity, not about keeping
  sessions apart.
- **Re-launching a running client hands it the URL** instead of starting a second
  copy, which is what `open` relies on to drop a link into the session you
  already have open.

Generated Hyprland rules also mirror whichever of Omarchy's two parity rules
applies: chromium-based browsers get `tile = true`, firefox-based ones don't.

Because a custom app_id misses Omarchy's full-match browser regex, these rules
are what keep a client window looking like a browser window rather than falling
back to generic opacity.

### No launcher script to install

The CLI *is* the launcher. Generated desktop entries call
`browser-switcher launch <id> %U`, which execs the browser with the right
`--user-data-dir` and `--class`. Nothing else needs to exist on disk, and there
is no wrapper script to keep in sync.

Link clicks and app launches differ in exactly one flag: opening a *link* omits
`--new-window` so Chromium reuses that profile's running window, while launching
from the app grid passes it.

### Window rules need no wiring

Omarchy's stock `hyprland.lua` ends with `require("default.hypr.toggles")`,
which auto-requires every `*.lua` in `~/.local/state/omarchy/toggles/hypr/` on
each reload. The plugin writes its rules there, so they load on a clean install
with **no edit to any config file** — and uninstalling is a single unlink rather
than config surgery.

That directory also loads *after* your own `hypr.*` modules, which is the
ordering border colours need: Hyprland evaluates rules top to bottom and the
last match wins.

`browser-switcher doctor` checks that the `default.hypr.toggles` line is still
present, since deleting it would silently cost you the border colours and
nothing else.

## Install

```bash
git clone <this repo> ~/code/omarchy-browser-switcher
cd ~/code/omarchy-browser-switcher
./install.sh
```

Bare, that installs the CLI and plugin and changes nothing about how links
currently open. Then opt in:

```bash
./install.sh --enable         # put the widget in the bar
./install.sh --set-default    # actually route links through the switcher
./install.sh --all            # both
```

`browser-switcher doctor` reports what is and isn't wired up.

Requires `python3` and `imagemagick`.

### Developing on it

`install.sh` symlinks the checkout into `~/.config/omarchy/plugins/`, so edits
land immediately — but the shell's plugin watcher does not follow the symlink,
and `rescanPlugins` won't pick changes up through it either. After editing QML,
reload with:

```bash
omarchy restart shell
```

The panel also answers on its own IPC target, which is handy while iterating and
worth binding to a key:

```bash
omarchy-shell browser-switcher toggle      # open/close the picker
omarchy-shell browser-switcher configure   # open straight into the manage view
omarchy-shell browser-switcher next        # cycle to the next client
```

## Using it

**In the bar.** Left-click opens the picker; click a client to switch. Right-click
cycles to the next client without opening anything — the "pop over to personal
for two minutes and come back" case shouldn't cost a menu. Middle-click opens a
new window of the current client.

The picker is just the list of clients and a gear in its header. Configuring is
rare next to switching, so it doesn't get a permanent row — except before the
first client exists, when the panel is otherwise empty and adding one is the
only useful thing to do.

**Configure** (the gear, or `c`) turns the same panel into the management view:
rename in place, set a colour, choose a logo, delete, add a client.

Picking a colour happens *inside* the panel — a swatch grid plus a hex field for
an exact brand colour. That is not just a style choice: the panel is a
layer-shell overlay with a fullscreen click-catcher beneath it, so any separate
dialog window opens *behind* it and the first click aimed at that dialog hits the
catcher and dismisses the panel instead. Anything that can be done in-panel is.

Choosing a logo does need a real file dialog, so the panel closes itself first,
hands over cleanly, and reopens on the manage view when you're done.

**From the terminal**, which is the whole API:

```bash
browser-switcher list                 # what exists, and what's active
browser-switcher use acme             # switch
browser-switcher add --name "Acme" --color '#D20F39' --icon ~/logos/acme.png
browser-switcher rename acme "Acme Corp"
browser-switcher remove acme          # keeps the browsing data
browser-switcher remove acme --purge  # deletes it too
browser-switcher doctor
```

**From a keybind** — bind these in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT", "B", "exec", "omarchy-shell browser-switcher next")
o.bind("SUPER ALT",   "B", "exec", "omarchy-shell browser-switcher toggle")
```

## Bringing an existing hand-made setup across

If you already built per-client browsers by hand, point a new client at the data
directory you already have and your logged-in sessions carry over:

```bash
browser-switcher add --name acme --color '#179299' \
  --profile-dir ~/.local/share/chromium-profiles/acme
```

Then delete your old desktop entry, icons and window rules. The plugin will not
do that for you — it never touches files it didn't create — and `add` will
refuse while an entry claiming the same window class is still in place.

## Backing out

```bash
omarchy plugin disable sven.browser-switcher
browser-switcher uninstall     # restores your previous default browser
```

`uninstall` removes only generated files and restores the browser that was your
default before the router took over. Add `--purge` to also drop the config and
badge images. Browsing data is never deleted except by `remove --purge`.

## Layout

| File | What it is |
|---|---|
| `bin/browser-switcher` | the CLI, the router and the launcher; owns all state and file generation |
| `Panel.qml` | bar widget and popup — switch view and manage view |
| `Service.qml` | thin cache over `browser-switcher list --json`, refreshed by file watch |
| `manifest.json` | Omarchy plugin declaration |
| `install.sh` | wiring, all of it opt-in |

The CLI is the single source of truth. The panel shells out to it for every read
and every mutation, so the bar, a terminal and a keybind cannot disagree about
what is configured.

## Status

Early.

- The CLI is tested, and the Chromium path is verified end to end against a
  running Hyprland.
- The Firefox-family path is verified with Zen, end to end: the plugin's own
  `launch` produces a window whose app_id matches the `wmClass` its generated
  Hyprland rule targets. Firefox and LibreWolf use the same mechanism but are
  not installed here. The `brave-origin` binary name remains a guess at that
  package's entry point.
- The bar panel now runs in a live shell. The switch view, manage view, inline
  colour picker and the file-dialog handoff have all been exercised on a real
  desktop.

`browser-switcher doctor` reports what is and isn't wired up.

## License

MIT
