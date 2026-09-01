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

## What a client gets

Adding a client called `acme` creates:

| Thing | Where |
|---|---|
| Isolated browser data directory | `~/.local/share/chromium-profiles/acme` |
| Desktop entry | `~/.local/share/applications/browser-switcher-acme.desktop` |
| Badged icon (7 sizes) | `~/.local/share/icons/hicolor/*/apps/browser-switcher-acme.png` |
| Hyprland border rule | `~/.config/hypr/browser-switcher.lua` |
| An entry in the bar panel | — |

The icon is the browser's own icon with the client's logo composited into a disc
in the client's colour, so a client is identifiable at 16px in the bar and in
the taskbar. The Hyprland rule colours that client's window borders with the
same colour, so an unfocused window still says whose it is.

## Install

```bash
git clone <this repo> ~/code/omarchy-browser-switcher
cd ~/code/omarchy-browser-switcher
./install.sh
```

Bare, that installs the CLI and plugin and changes nothing about how links
currently open. Then opt in to as much as you want:

```bash
./install.sh --adopt          # register hand-made launchers you already have
./install.sh --enable         # put the widget in the bar
./install.sh --hyprland       # coloured window borders
./install.sh --set-default    # actually route links through the switcher
./install.sh --all            # all of the above
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
browser-switcher use acme            # switch
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

## Existing setups are adopted, never overwritten

If you already wired up per-client browsers by hand, `adopt` registers them
without touching a byte of what you built:

```bash
browser-switcher discover   # what it can see
browser-switcher adopt      # register all of it
```

It reads your desktop entries — following wrapper scripts to find the real
`--user-data-dir` — and picks the client's colour back out of your existing
Hyprland rules rather than assigning a new one.

Adopted targets are recorded as `managed: false`, and every generator in the
tool skips them: no desktop entry is written, no icon is re-badged, no window
rule is emitted. The switcher learns how to launch them and otherwise leaves
them alone.

Everything the tool *does* generate is prefixed `browser-switcher-` and carries
a "Do not edit" banner, so which files are yours and which are its is never
ambiguous. `add` refuses outright to create a target whose window class would
collide with an entry it didn't write.

## Backing out

```bash
omarchy plugin disable sven.browser-switcher
browser-switcher uninstall     # restores your previous default browser
```

`uninstall` removes only generated files, and restores the browser that was
your default before the router took over. Add `--purge` to also drop the config
and badge images. Hand-made entries are left where they are.

## Layout

| File | What it is |
|---|---|
| `bin/browser-switcher` | the CLI, and the router; owns all state and file generation |
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
