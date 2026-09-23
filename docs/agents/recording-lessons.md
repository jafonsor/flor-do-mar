# Recording Lessons

Where a lesson goes when work turns up something worth keeping. Applies to any
non-trivial task, not only debugging.

## Propose it; do not write it

Report the lesson, its destination file, and a one-line draft in the handoff, then
wait for confirmation. Nothing enters the docs until a human agrees it is durable —
the judgement that a lesson generalises past this task is theirs, not yours.

## Encode it first

Try these in order and take the first that holds:

| if the lesson... | encode it as | because |
|---|---|---|
| can be enforced mechanically | a wrapper, a test, a build flag | the check runs by itself |
| records a design decision | `docs/adr/NNNN-*.md` | decisions are captured when made |
| is a trap that hides behind a false signal | `docs/agents/<topic>.md` | reached by pointer when it fires |
| defines or renames a domain term | `CONTEXT.md` | one glossary for the project |

Prose is the residue of a lesson that cannot be encoded. Prefer it last: a
documented rule waits for a reader to recall it at the right moment, while an
encoded one applies itself.

`testNavigationSteeringDoesNotWeave` in `test/CombatTest.hs` is the shape to copy.
The weave was not filed as a caution: the throwaway harness that reproduced it
(`test/DiagnosisTrajectoryShape.hs`) was promoted into a check in the suite that
runs on every `combat-test`, and the harness now only exists for the next
investigation.

## Test whether it is a lesson at all

Record it only if another agent in this repo would hit the same wall at a decision
point. If the answer is no, it is local to this task: leave it out.

## Fix what the lesson invalidates

If it contradicts existing text, correct that text in the same change. Never leave
a stale claim standing with a correction beside it.

## Shape

- Head the section with the **false signal**, not the topic. "A browser tab that
  outlives the client used to freeze silently" is matchable mid-debug; "Client
  lifecycle" is not.
- Give evidence a reader can re-run — the command and its output — not just the
  instruction. "Prefer `--soft`" persuades less than a count of what `--hard`
  destroyed.
- Any claim pinned to a version, path, or store hash needs its own expiry: an
  override, a glob, or a check that announces when it breaks.

## Verify before you propose it

Run the command. Do not propose a filter you have not executed against this
codebase.

## Then hand off

The lesson lands in one commit with the work that produced it, at the same time as
the fix, so the message can say which belief turned out wrong. State that hypothesis
in the commit message: the next reader learns more from the correction than from the
rule.
