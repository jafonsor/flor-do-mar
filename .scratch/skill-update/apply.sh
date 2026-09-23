#!/usr/bin/env bash
# Update Matt Pocock's global agent skills to a pinned upstream commit.
# Policy: "released only" = engineering/ + productivity/ (the 25 skills in the plugin manifest).
set -euo pipefail

WS="/Users/joaorodrigues/devs/flor-do-mar"
STAGE="$WS/.scratch/skill-update/stage"
STAMP="2026-09-22"
BACKUP="$HOME/.agents/skill-update-$STAMP"
CANON="$HOME/.agents/skills"          # real files live here
CLAUDE="$HOME/.claude/skills"         # relative symlinks point at CANON

echo "==> 1. Backup current state -> $BACKUP"
rm -rf "$BACKUP"
mkdir -p "$BACKUP"
# Move the whole current canonical tree + lock aside (same filesystem, so instant).
if [ -d "$CANON" ]; then mv "$CANON" "$BACKUP/skills.old"; fi
if [ -f "$HOME/.agents/.skill-lock.json" ]; then
  mv "$HOME/.agents/.skill-lock.json" "$BACKUP/.skill-lock.json.old"
fi
# Also record the old symlink map for reference.
ls -l "$CLAUDE" > "$BACKUP/claude-skills-symlinks.txt" 2>/dev/null || true
echo "    backed up $(ls "$BACKUP/skills.old" | wc -l | tr -d ' ') skills"

echo "==> 2. Install the 25 released skills into $CANON"
mkdir -p "$CANON"
for d in "$STAGE"/*/; do
  name="$(basename "$d")"
  cp -R "$d" "$CANON/$name"
done
echo "    installed $(ls "$CANON" | wc -l | tr -d ' ') skills"

echo "==> 3. Remove retired symlinks from $CLAUDE"
# Only symlinks are removed. A real directory that is absent from $CANON was never
# part of the managed set, so "missing from $CANON" does not make it retired:
# removing those is how ~/.claude/skills/use-codex was lost. Report them instead.
removed=0
skipped=()
for entry in "$CLAUDE"/*; do
  [ -e "$entry" ] || [ -L "$entry" ] || continue
  name="$(basename "$entry")"
  [ -d "$CANON/$name" ] && continue
  if [ -L "$entry" ]; then
    rm -f "$entry"
    echo "    removed link $name"
    removed=$((removed + 1))
  else
    skipped+=("$name")
  fi
done
echo "    removed $removed retired symlinks"
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "    NOT removed (not symlinks, so not ours to delete): ${skipped[*]}"
  echo "    Review them, then delete manually if they are obsolete."
fi

echo "==> 4. Ensure a correct relative symlink for every released skill"
for d in "$CANON"/*/; do
  name="$(basename "$d")"
  target="$CLAUDE/$name"
  # Replace anything that is not already the correct relative symlink.
  if [ ! -L "$target" ]; then rm -rf "$target"; fi
  ln -sfn "../../.agents/skills/$name" "$target"
done

echo "==> 5. Verify"
echo "    canonical skills : $(ls "$CANON" | wc -l | tr -d ' ')"
echo "    claude entries   : $(ls "$CLAUDE" | wc -l | tr -d ' ')"
broken="$(find "$CLAUDE" -maxdepth 1 -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')"
echo "    broken symlinks  : $broken"
[ "$broken" = "0" ] || { echo "ERROR: broken symlinks present"; exit 1; }
missing="$(comm -23 <(ls "$CANON" | sort) <(ls "$CLAUDE" | sort) | wc -l | tr -d ' ')"
echo "    unlinked skills  : $missing"
[ "$missing" = "0" ] || { echo "ERROR: some skills lack a symlink"; exit 1; }

echo
echo "DONE. Backup at $BACKUP (revert: rm -rf $CANON && mv $BACKUP/skills.old $CANON)"
