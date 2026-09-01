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

## Using it

**In the bar.** Left-click opens the picker; click a client to switch. Right-click
cycles to the next client without opening anything — the "pop over to personal
for two minutes and come back" case shouldn't cost a menu. Middle-click opens a
new window of the current client.

**Configure** (the gear, or `c`) turns the same panel into the management view:
rename in place, set a colour, choose a logo, delete, add a client.

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

Early. The CLI is tested; the panel has not yet run through a full session in a
live shell. See `browser-switcher doctor` if something looks wrong.

## License

MIT
