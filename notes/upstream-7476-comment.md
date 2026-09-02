Confirming this independently, and adding a second symptom that I think makes it
worth fixing sooner than "the last option is clipped" suggests.

**The list also scrolls under the pointer.** The row delegate assigns
`currentIndex` on hover:

```qml
MouseArea {
  ...
  onPositionChanged: optionList.currentIndex = parent.index
}
```

Since `ListView` keeps its current item visible (`highlightFollowsCurrentItem`
defaults to true), and the shortfall you describe leaves the viewport permanently
scrollable by that amount, hovering the **first or last** option scrolls the list
to that end. The middle rows are already fully visible, so the effect is a small
jump between two positions as the pointer moves between the ends of the list —
not a gradual drift.

That reads as a worse bug than clipping, because the thing you are pointing at
moves while you point at it.

**It reproduces on the default theme**, not only with a 2px popup border. With a
1px border the shortfall is `2 * 1 = 2px`, which is already enough to make the
view scrollable — so a 4-option dropdown in a popup with plenty of room still
drifts. That may be why this gets noticed as the list twitching rather than as a
clipped option.

Your arithmetic matches what I get:

| popup border | padding applied | reserved (`xxs`) | viewport shortfall |
|---|---|---|---|
| 1px | 4px | 2px | 2px |
| 2px | 6px | 2px | 4px |

The patch you propose fixes both symptoms as far as I can tell from the numbers —
deriving the height from the rows plus the padding actually applied makes the
viewport exactly the content height, so there is nothing left to scroll and
nothing clipped. I have not run it, so treat that as arithmetic rather than a
test result.

Worth noting #6725 is an open PR for a different defect in the same component
(clicking the trigger reopens the popup instead of dismissing it), so whoever
picks this up may want to look at both together.
