# Browser Switcher

An Omarchy shell plugin that puts a browser picker in the bar. Click it, pick a
profile, and every link you open from that point on lands in that browser's
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

### Both link sources reach it

A link clicked in a GUI app and a link clicked in the terminal travel different
routes, and only one of them parses the desktop entry properly.

| Source | Route | What actually runs |
|---|---|---|
| GUI app | portal / GIO → mimeapps | the full `Exec` line, subcommand intact |
| Terminal (foot, alacritty, …) | `xdg-open` → generic path | **first word of `Exec`** plus the expanded `%U` |
| CLI tools, Omarchy keybinds | `$BROWSER` → `omarchy-launch-browser` | **first word of `Exec`** plus the URL |

Both of the lower rows discard the `open` subcommand: `xdg-open`'s
`search_desktop_file` takes `Exec | first_word` and keeps only the last field
(`%U`) as the argument, and `omarchy-launch-browser` does the same
`sed 's/^Exec=\([^ ]*\).*/\1/'`. Under Hyprland this is the normal path, since
`XDG_CURRENT_DESKTOP=Hyprland` matches no desktop `xdg-open` knows, so it falls
to its generic handling.

So `browser-switcher <url>` — a bare URL with no subcommand — is treated as
`open`, and that is what makes terminal links work. Unrecognised flags are
forwarded to the browser rather than rejected, because `omarchy-launch-browser`
rewrites `--private` into a browser-specific `--incognito` / `--private-window`
on the way past. A mistyped subcommand still gets a normal argparse error
rather than being handed to the browser as if it were a URL.

`doctor` also checks that `$BROWSER` still resolves back to the switcher, since
setting it to one specific browser silently bypasses everything above for the
tools that read it.

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

## What a profile gets

Adding a profile called `acme` creates:

| Thing | Where |
|---|---|
| Isolated browser data directory | `~/.local/share/browser-switcher/profiles/acme` |
| Desktop entry | `~/.local/share/applications/browser-switcher-acme.desktop` |
| Badged icon (7 sizes) | `~/.local/share/icons/hicolor/*/apps/browser-switcher-acme.png` |
| Hyprland border rule | `~/.local/state/omarchy/toggles/hypr/browser-switcher.lua` |
| An entry in the bar panel | — |

### Icons are generated, not supplied

You give it a logo — any PNG, JPG, SVG or WebP — and it does the compositing.
The logo is placed on a filled disc in the profile's colour and composited
onto the browser's own icon, rendered at all seven hicolor sizes. A profile with
no logo yet still gets the coloured disc, so it stays identifiable at 16px.
Requires ImageMagick; `install.sh` checks for it.

```bash
browser-switcher set acme --icon ~/logos/acme.svg   # or: pick-icon, for a file dialog
```

### Supported browsers, and how each gets a per-profile window identity

Every browser Omarchy can install (`omarchy install browser …`), plus the
preinstalled Chromium and the two extras Omarchy's own window rules already
recognise.

| Browser | Family | Profile isolation | Per-profile app_id | Verified |
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
  Firefox-family profile would share one app_id, so no per-profile border colour
  could match and `StartupWMClass` would be wrong for all of them.

Two behaviours worth knowing, both measured rather than assumed:

- **Isolation comes from `--profile`, not from the remoting name.** Two different
  profile directories run as fully independent instances even when they share a
  remoting name. The remoting name is about window identity, not about keeping
  sessions apart.
- **Re-launching a running profile hands it the URL** instead of starting a second
  copy, which is what `open` relies on to drop a link into the session you
  already have open.

Generated Hyprland rules also mirror whichever of Omarchy's two parity rules
applies: chromium-based browsers get `tile = true`, firefox-based ones don't.

Because a custom app_id misses Omarchy's full-match browser regex, these rules
are what keep a profile window looking like a browser window rather than falling
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

### From the plugin repository

```bash
omarchy plugin add <repo-url> --enable
```

That is the whole install. `omarchy plugin add` only clones the repo and
enables the widget — it deliberately never runs an install script — so the
plugin sets itself up from the panel instead:

- The CLI is found inside the plugin directory, so nothing has to be on `PATH`
  for the panel to work.
- Until links actually route here, the panel shows a **Make this the default
  browser** button. Pressing it registers the router, and links start arriving.
  Nothing takes over link handling without that press.
- That step also symlinks `browser-switcher` into `~/.local/bin`, so the
  command works in a terminal too.

### From a git checkout

`install.sh` is a convenience for working on the plugin, not a requirement:

```bash
git clone <this repo> ~/code/omarchy-browser-switcher
cd ~/code/omarchy-browser-switcher
./install.sh                  # links the CLI and the plugin, changes nothing else
./install.sh --enable         # put the widget in the bar
./install.sh --set-default    # route links through the switcher
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

QML errors do not surface in the panel — they go to the shell's log, and a
plugin with a broken binding often just renders nothing. Check there first when
something disappears:

```bash
journalctl --user --since "1 minute ago" | grep browser-switcher
```

The panel also answers on its own IPC target, which is handy while iterating and
worth binding to a key:

```bash
omarchy-shell browser-switcher toggle      # open/close the picker
omarchy-shell browser-switcher configure   # open straight into the manage view
omarchy-shell browser-switcher next        # cycle to the next profile
```

## Using it

**In the bar.** Left-click opens the picker; click an entry to switch.
Right-click opens a new window of whatever is currently selected — the usual
follow-up to switching, and worth having without going through a menu.
Middle-click cycles to the next entry.

The picker is just the list of entries and a gear in its header. Configuring is
rare next to switching, so it doesn't get a permanent row — except before the
first profile exists, when the panel is otherwise empty and adding one is the
only useful thing to do.

**Configure** (the gear, or `c`) turns the same panel into the management view:
rename a profile in place, set a colour, choose a logo, remove an entry,
and add a profile or a system browser.

Picking a colour happens *inside* the panel — a swatch grid plus a hex field for
an exact brand colour. That is not just a style choice: the panel is a
layer-shell overlay with a fullscreen click-catcher beneath it, so any separate
dialog window opens *behind* it and the first click aimed at that dialog hits the
catcher and dismisses the panel instead. Anything that can be done in-panel is.

Choosing a logo does need a real file dialog, so the panel closes itself first,
hands over cleanly, and reopens on the manage view when you're done.

### Two kinds of entry

A **profile** is an isolated session: its own browser data directory, a badged
icon, a coloured window border, its own desktop entry. That is the case this
plugin exists for.

A **system browser** is just a pointer at a browser as it is already installed —
its normal profile, its own icon, no window colouring, nothing generated for it
at all. Useful for "send this link to plain Firefox" without inventing a profile
for it.

The two are listed separately everywhere, and a system browser's name is not
editable: it is the browser's own name, so renaming it could only ever make the
list less accurate. In the switcher its row carries no subtitle either — the
name is already the browser's name, while a profile's subtitle is the one thing
saying which browser it runs.

```bash
browser-switcher add --name "Acme"     # an isolated profile
browser-switcher add-browser firefox   # plain Firefox, as itself
browser-switcher addable-browsers      # installed browsers not yet listed
```

Both appear in the switcher panel and both can be the active link destination.
Colour and logo apply only to profiles; asking for them on a system browser is
refused rather than silently ignored.

`list` groups the two and marks where links currently go:

```
Profiles (isolated)
    personal                      chromium      ■■ #DF8E1D
  → Acme Corp                       chromium      ■■ #D20F39
    Legacy                          firefox       ■■ #3F5FCF  (not installed)

System browsers
    Chromium                        chromium
    Zen Browser (zen)               zen
```

An entry's id is shown in brackets only when it differs from its name — most
ids are derived from the name, and printing both every time is just noise.
Either one works wherever a command takes a target. The colour swatch is drawn
only when stdout is a terminal and `NO_COLOR` is unset, so piping stays clean.

### Bar icon style

The badged icon is the clearest signal of which profile is live, but it is
full-colour artwork sitting in a row of monochrome glyphs. The widget's
`barIcon` setting picks how it presents:

| Value | Look |
|---|---|
| `No indicator` | just the glyph — no sign of which entry is active |
| `Colour dot` (default) | bar-coloured glyph with a small profile-colour dot |
| `Coloured glyph` | the glyph itself tinted with the profile's colour |
| `Profile icon` | the full-colour badged browser icon |

Pick it from the **Bar icon** row in the manage view: four cells, each drawing
exactly what the bar will look like, so the choice is made by looking rather
than by reading labels. It writes through `omarchy bar set`, so the change is
immediate and persists in `shell.json`. Editing that file by hand works too:
`{ "id": "sven.browser-switcher", "barIcon": "Profile icon" }`.

`Colour dot` and `Coloured glyph` have nothing to show for a system browser,
which has no colour of its own — those fall back to the bar's own foreground so
the glyph matches its neighbours exactly, rather than rendering a placeholder
grey that just looks like a slightly wrong colour.

Later options are clearer at a glance; earlier ones sit more quietly beside the
other bar icons. Labels from earlier versions (`Theme`, `Client colour`,
`Full colour`, `Client icon`) are still understood.

**From the terminal**, which is the whole API:

```bash
browser-switcher list                 # what exists, and what's active
browser-switcher use acme             # switch (id or name, either works)
browser-switcher add --name "Acme" --color '#D20F39' --icon ~/logos/acme.png
browser-switcher rename acme "Acme Corp"
browser-switcher remove acme          # keeps the browsing data
browser-switcher remove acme --purge  # deletes it too, irreversibly
browser-switcher doctor
```

**From a keybind** — bind these in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT", "B", "exec", "omarchy-shell browser-switcher next")
o.bind("SUPER ALT",   "B", "exec", "omarchy-shell browser-switcher toggle")
```

## Bringing an existing hand-made setup across

If you already built per-profile browsers by hand, point a new profile at the data
directory you already have and your logged-in sessions carry over:

```bash
browser-switcher add --name acme --color '#179299' \
  --profile-dir ~/.local/share/chromium-profiles/acme
```

Then delete your old desktop entry, icons and window rules. The plugin will not
do that for you — it never touches files it didn't create — and `add` will
refuse while an entry claiming the same window class is still in place.

## Removing a profile, and its data

Removing a profile deletes what this plugin generated — the desktop entry, the
badged icons, the window rule — but **leaves the browsing data alone**. That
directory holds real logins, cookies and history, and losing it to a misclick
would be worse than leaving it behind.

Both surfaces say so rather than leaving you to guess:

- The panel's confirm reads *"Its browsing data is kept unless you say
  otherwise"*, and offers a **Delete browsing data too** toggle. It is off
  every time a confirm opens, and only when it is on does the button change to
  *Remove and delete data*.
- The CLI prints where the data was kept, and that the directory holds the
  profile's logins and history.

`--purge` deletes it at removal time. It only ever removes a directory under
`~/.local/share/browser-switcher/profiles`; a profile pointed at a directory of
your own with `--profile-dir` is reported rather than deleted, since that
directory is not ours to remove.

Data left behind is easy to reclaim: re-adding a profile with the same name
reuses the directory, and the logins come straight back.

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
| `Select.qml` | dropdown that doesn't drift under the pointer (see below) |
| `manifest.json` | Omarchy plugin declaration |
| `install.sh` | wiring, all of it opt-in |

`Select.qml` exists to work around a bug in the shipped `qs.Ui.Dropdown`: its
popup budgets `Style.spacing.xxs` (2px) of vertical padding in `implicitHeight`
while actually applying `Border.top + hairline` twice (4px), so the ListView
viewport is permanently two pixels shorter than its own content. Because the
row delegate assigns `currentIndex` on hover, ListView then scrolls to keep the
current row visible — and pointing at the first or last option nudges the list.
The deficit is constant, so it happens at any option count, however much room
the popup has. Ours lays the rows out in a plain Column, so nothing tracks a
current index for the view to chase and there is no mechanism left to scroll;
the Flickable only becomes interactive if the list genuinely outgrows its cap.
Worth reporting upstream.

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
