Status: ready-for-agent

# Handle Navigation Edge Cases

## What to build

Harden navigation behavior around combat lifecycle and existing commands. Movement orders should interact cleanly with broadside firing, disabled ships, hot reload, setup pause, and terminal scenarios. These are edge cases, but they protect the command model from surprising state corruption.

## Acceptance criteria

- [ ] Broadside firing does not clear or mutate active navigation orders.
- [ ] Disabled ships clear or ignore navigation intent.
- [ ] Setup overlay blocks navigation input and planning overlays.
- [ ] Scenario-finished state hides planning overlays and rejects new navigation input.
- [ ] Hot reload preserves the committed reachable waypoint for active orders.
- [ ] Hot reload recomputes movement/projection behavior from updated physics without moving the committed waypoint.
- [ ] If a safety cap prevents arrival after later state/physics changes, the order is surfaced as a safety/test fallback rather than silently reclamped.
- [ ] Tests cover broadside independence, disabled ship behavior, setup blocking, finished scenario blocking, and hot reload preserving the committed waypoint.

## Blocked by

- `.scratch/mouse-navigation-trajectory-planner/issues/03-plan-and-execute-navigation-orders.md`
- `.scratch/mouse-navigation-trajectory-planner/issues/06-commit-mouse-navigation-and-drag-speed.md`
