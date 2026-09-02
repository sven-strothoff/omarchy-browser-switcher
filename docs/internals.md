# How it works

Detail that would clutter the README. The short version lives there.

## Routing: one indirection

A generated router entry, `browser-switcher.desktop`, is registered **once** as
the default web browser. Every `http(s)` link therefore arrives at
`browser-switcher open`, which reads a one-line state file and re-launches the
URL in whichever target is selected.

```
link → xdg-open → browser-switcher.desktop → browser-switcher open
                                                    ↓
                                          reads ~/.local/state/…/active
                                                    ↓
                              chromium --user-data-dir=…/acme --class=chromium-acme
```

Switching is then a single small write rather than a rewrite of
`mimeapps.list`: instant, system-wide, nothing to restart, no cache to race.

### Why a bare URL is accepted

A link clicked in a GUI app and one clicked in a terminal take different routes,
and only one of them parses the desktop entry properly.

| Source | Route | What actually runs |
|---|---|---|
| GUI app | portal / GIO → mimeapps | the full `Exec` line, subcommand intact |
| Terminal | `xdg-open` → generic path | **first word of `Exec`** + the expanded `%U` |
| CLI tools, keybinds | `$BROWSER` → `omarchy-launch-browser` | **first word of `Exec`** + the URL |

`xdg-open`'s `search_desktop_file` builds its command as `Exec | first_word` and
keeps only the trailing field as the argument; `omarchy-launch-browser` does the
same with `sed 's/^Exec=\([^ ]*\).*/\1/'`. Both discard the `open` subcommand.
Under Hyprland this is the normal path, because `XDG_CURRENT_DESKTOP=Hyprland`
matches no desktop `xdg-open` knows and it falls to its generic handling.

So `browser-switcher <url>` — no subcommand — is dispatched as `open`. Detection
is deliberately strict (a scheme, a path, or a bare `www.` host) so a mistyped
subcommand still gets a normal argparse error instead of being handed to the
browser. Unrecognised flags are forwarded to the browser, because
`omarchy-launch-browser` rewrites `--private` into a browser-specific
`--incognito` / `--private-window` on the way past.

`xdg-settings` also refuses to set a default while `$BROWSER` is set, and Omarchy
always sets it — so every `xdg-settings` call runs with `BROWSER` stripped, the
same way Omarchy's own scripts do.

## Two browser families

They differ in how a window gets a per-profile identity, and getting it wrong is
not cosmetic — without one, every profile shares an app_id and no border rule can
match.

- **Chromium** takes `--class=NAME`, which on Wayland becomes the app_id.
  Verified against `hyprctl`: the window reports `class=NAME`, `xwayland: false`.
  Each `--user-data-dir` is its own singleton.
- **Firefox** ignores `--class` on Wayland — it only ever set the X11
  `WM_CLASS`. Verified with Zen: `--class=zen-probe` still produced app_id `zen`,
  while `MOZ_APP_REMOTINGNAME=zen-acme` produced `zen-acme`.

Isolation itself comes from `--profile`, not the remoting name: two profile
directories run as independent instances even when they share one. The remoting
name is about window identity.

Opening a *link* omits `--new-window` so the profile's existing window is reused;
launching from the app grid passes it. Confirmed: re-launching a running profile
with a URL hands it to that instance and spawns no new process.

## Icons

You supply a logo in any format ImageMagick reads. It is composited onto a
filled disc in the profile's colour, then onto the browser's own icon, and
rendered at all seven hicolor sizes. A profile with no logo still gets the
coloured disc, so it stays identifiable at 16px.

The badged PNG keeps one filename for its whole life, so re-colouring rewrites
the file without changing the URL — which means Qt will happily serve the pixmap
it already cached. The CLI reports an `iconVersion` (the file's mtime) and the
panel reloads when it moves.

## Colours

[Catppuccin Latte](https://catppuccin.com/palette/) accents. Omarchy ships
Catppuccin as a theme, so the swatches read as part of the desktop; Latte rather
than Mocha because its accents are darker and stay visible as a thin border on
light and dark themes alike.

Eleven of the fourteen, plus one neutral. Flamingo, maroon and sapphire are left
out because they sit too close to rosewater, red and teal to tell apart at border
width — as CIE76 ΔE in Lab, the full set's closest pair is 10.1 and this subset's
is 21.3. A colour you can't distinguish is no use as an identity.

## Layout

| File | What it is |
|---|---|
| `bin/browser-switcher` | the CLI, the router and the launcher; owns all state and file generation |
| `Panel.qml` | bar widget and popup — switch view and manage view |
| `Service.qml` | cache over `browser-switcher list --json`, refreshed by file watch |
| `Select.qml` | dropdown that doesn't drift under the pointer (below) |
| `manifest.json` | Omarchy plugin declaration |
| `install.sh` | convenience for a git checkout; not needed for a plugin install |

The CLI is the single source of truth. The panel shells out to it for every read
and every mutation, so the bar, a terminal and a keybind cannot disagree.

Two exceptions, both deliberate:

- `launch` goes out via `Quickshell.execDetached`. Its CLI path ends in an
  `execv`, so the process *becomes* the browser and does not exit until that
  window closes — through the shared action process it pinned the queue for the
  browser's lifetime.
- Bar appearance is persisted with `bar.shell.updateEntryInline`, the mechanism
  first-party widgets use, rather than shelling out to `omarchy bar set`.

Panel actions otherwise queue in a FIFO rather than being dropped, so a slow
command can't silently swallow the next click.

## Why `Select.qml` exists

The shipped `qs.Ui.Dropdown` has two defects, both filed upstream:

| Bug | Upstream |
|---|---|
| popup `implicitHeight` omits its own padding | [omacom/omarchy#7476](https://github.com/omacom/omarchy/issues/7476) |
| clicking the trigger reopens instead of dismissing | [omacom/omarchy#6725](https://github.com/omacom/omarchy/pull/6725) |

The popup budgets `Style.spacing.xxs` (2px) of vertical padding while applying
`Border.top + hairline` twice (4px), so its ListView viewport is permanently two
pixels shorter than its content. Because the row delegate assigns `currentIndex`
on hover, `ListView` then scrolls to keep the current row visible — pointing at
the first or last option moves the list. The deficit is constant, so it happens
at any option count.

Separately, a press on the trigger while the popup is open counts as an outside
press, so the popup closes on the press and the release reopens it.

`Select.qml` lays its rows out in a plain `Column`: nothing tracks a current
index for the view to chase, so there is no mechanism left to scroll. It also
records when the popup closed and swallows exactly the click that caused it.
Delete this file once both land upstream.

## Developing

`install.sh` symlinks the checkout into `~/.config/omarchy/plugins/`, so edits
land immediately — but the shell's plugin watcher does not follow the symlink and
`rescanPlugins` won't reach through it either. After editing QML:

```bash
omarchy restart shell
```

QML errors do not surface in the panel; a plugin with a broken binding often just
renders nothing. Check the log first when something disappears:

```bash
journalctl --user --since "1 minute ago" | grep browser-switcher
```

The panel answers on its own IPC target, which is handy while iterating:

```bash
omarchy-shell browser-switcher toggle      # open/close the picker
omarchy-shell browser-switcher configure   # straight into the manage view
omarchy-shell browser-switcher next        # cycle
```

## Bringing a hand-made setup across

Point a new profile at the data directory you already have and the logged-in
sessions carry over:

```bash
browser-switcher add --name acme --color '#179299' \
  --profile-dir ~/.local/share/chromium-profiles/acme
```

Then delete your old desktop entry, icons and window rules. The plugin will not
do that for you — it never touches files it didn't create — and `add` refuses
while an entry claiming the same window class is still in place.
