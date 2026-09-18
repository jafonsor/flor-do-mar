Status: ready-for-agent

# Open Setup Overlay With Escape

## What to build

Add an engagement setup overlay that opens when the player presses Escape. Opening setup pauses combat ticks while leaving the current valid configuration available. The setup overlay lets the player choose the player boat kind and enemy boat kind from the loaded boat configs. Launching an engagement restarts the duel using the selected roster, with one player boat and one enemy boat. Boat kind selection is locked for the current engagement until the next explicit launch.

## Acceptance criteria

- [ ] Pressing Escape opens the setup overlay over the tactical battle view.
- [ ] Combat simulation ticks do not advance while the setup overlay is open.
- [ ] The overlay offers configured boat kinds for the player and enemy selections.
- [ ] Launch Engagement restarts combat with exactly one player boat and one enemy boat using the selected boat kinds.
- [ ] The default engagement still starts automatically when the client launches.
- [ ] The selected boat kinds are fixed for the engagement and are not silently replaced by later config reloads.

## Blocked by

- `.scratch/hot-reloadable-boat-physics/issues/01-load-configured-default-engagement.md`

## Comments

