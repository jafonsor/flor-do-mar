Status: ready-for-agent

# Load Configured Default Engagement

## What to build

Load runtime combat configuration on local client startup and start a default engagement from that configuration. The configuration defines global physics defaults and boat kinds, including a large player boat and a small enemy boat. Startup loading is strict: missing, malformed, or semantically invalid configuration fails fast with diagnostics instead of silently falling back. Snapshots expose the configured boat kind, display name, hull integrity, and rendered size so the tactical battle view can show distinct large and small boats immediately.

## Acceptance criteria

- [ ] Runtime config assets exist for global physics and at least `big` and `small` boat kinds.
- [ ] Startup config loading validates parser errors, required fields, semantic numeric ranges, and boat config ID-to-asset-name mismatches.
- [ ] Invalid startup config fails fast with actionable diagnostics instead of starting from defaults.
- [ ] The local default engagement starts automatically with a big player boat and a small enemy boat.
- [ ] Combat snapshots expose boat kind, display name, max hull, current hull, rendered length, and rendered width.
- [ ] The tactical battle view renders configured ship sizes, with the large boat visibly larger than the small boat.
- [ ] Existing command and snapshot boundaries remain intact for future remote Combat API use.

## Blocked by

None - can start immediately

## Comments

