---
name: help
model: claude-haiku-4-5-20251001
description: "Analyzes what is done and the users query and offers advice on what to do next. Use if user says what should I do next or what do I do now or I'm stuck or I don't know what to do"
argument-hint: "[optional: what you just finished, e.g. 'finished design-review' or 'stuck on ADRs']"
user-invocable: true
allowed-tools: Read, Glob, Grep
context: |
  !echo "=== Live Project State ===" && echo "Stage: $(cat production/stage.txt 2>/dev/null | tr -d '[:space:]' || echo 'not set')" && echo "Latest sprint: $(ls -t production/sprints/*.md 2>/dev/null | head -1 || echo 'none')" && echo "Session state: $(head -5 production/session-state/active.md 2>/dev/null || echo 'none')"
---

# Studio Help â€” What Do I Do Next?

This skill is read-only â€” it reports findings but writes no files.

This skill figures out exactly where you are in the game development pipeline and
tells you what comes next. It is **lightweight** â€” not a full audit. For a full
gap analysis, use `/project-stage-detect`.

---

## Step 1: Read the Catalog

Read `.claude/docs/workflow-catalog.yaml`. This is the authoritative list of all
phases, their steps (in order), whether each step is required or optional, and
the artifact globs that indicate completion.

---

## Step 1b: Find Skills Not in the Catalog

After reading the catalog, Glob `.claude/skills/*/SKILL.md` to get the full list
of installed skills. For each file, extract the `name:` field from its frontmatter.

Compare against the `command:` values in the catalog. Any skill whose name does
not appear as a catalog command is an **uncataloged skill** â€” still usable but not
part of the phase-gated workflow.

Collect these for the output in Step 7 â€” show them as a footer block:

```
### Also installed (not in workflow)
- `/skill-name` â€” [description from SKILL.md frontmatter]
- `/skill-name` â€” [description]
```

Only show this block if at least one uncataloged skill exists. Limit to the 10
most relevant based on the user's current phase (QA skills in production, team
skills in production/polish, etc.).

---

## Step 2: Determine Current Phase

Check in this order:

1. **Read `production/stage.txt`** â€” if it exists and has content, this is the
   authoritative phase name. Map it to a catalog phase key:
   - "Concept" â†’ `concept`
   - "Systems Design" â†’ `systems-design`
   - "Technical Setup" â†’ `technical-setup`
   - "Pre-Production" â†’ `pre-production`
   - "Production" â†’ `production`
   - "Polish" â†’ `polish`
   - "Release" â†’ `release`

2. **If stage.txt is missing**, infer phase from artifacts (most-advanced match wins):
   - `src/` has 10+ source files â†’ `production`
   - `production/stories/*.md` exists â†’ `pre-production`
   - `docs/architecture/adr-*.md` exists â†’ `technical-setup`
   - `design/gdd/systems-index.md` exists â†’ `systems-design`
   - `design/gdd/game-concept.md` exists â†’ `concept`
   - Nothing â†’ `concept` (fresh project)

---

## Step 3: Read Session Context

Read `production/session-state/active.md` if it exists. Extract:
- What was most recently worked on
- Any in-progress tasks or open questions
- Current epic/feature/task from STATUS block (if present)

This tells you what the user just finished or is stuck on â€” use it to personalize
the output.

---

## Step 4: Check Step Completion for the Current Phase

For each step in the current phase (from the catalog):

### Artifact-based checks

If the step has `artifact.glob`:
- Use Glob to check if files matching the pattern exist
- If `min_count` is specified, verify at least that many files match
- If `artifact.pattern` is specified, use Grep to verify the pattern exists in the matched file
- **Complete** = artifact condition is met
- **Incomplete** = artifact is missing or pattern not found

If the step has `artifact.note` (no glob):
- Mark as **MANUAL** â€” cannot auto-detect, will ask user

If the step has no `artifact` field:
- Mark as **UNKNOWN** â€” completion not trackable (e.g. repeatable implementation work)

### Special case: production phase â€” read `sprint-status.yaml`

When the current phase is `production`, check for `production/sprint-status.yaml`
before doing any glob-based story checks. If it exists, read it directly:

- Stories with `status: in-progress` â†’ surface as "currently active"
- Stories with `status: ready-for-dev` â†’ surface as "next up"
- Stories with `status: done` â†’ count as complete
- Stories with `status: blocked` â†’ surface as blocker with the `blocker` field

This gives precise per-story status without markdown scanning. Skip the glob
artifact check for the `implement` and `story-done` steps â€” the YAML is authoritative.

### Special case: `repeatable: true` (non-production)

For repeatable steps outside production (e.g. "System GDDs"), the artifact
check tells you whether *any* work has been done, not whether it's finished.
Label these differently â€” show what's been detected, then note it may be ongoing.

---

## Step 5: Find Position and Identify Next Steps

From the completion data, determine:

1. **Last confirmed complete step** â€” the furthest completed required step
2. **Current blocker** â€” the first incomplete *required* step (this is what the
   user must do next)
3. **Optional opportunities** â€” incomplete *optional* steps that can be done
   before or alongside the blocker
4. **Upcoming required steps** â€” required steps after the current blocker
   (show as "coming up" so user can plan ahead)

If the user provided an argument (e.g. "just finished design-review"), use that
to advance past the step they named even if the artifact check is ambiguous.

---

## Step 6: Check for In-Progress Work

If `active.md` shows an active task or epic:
- Surface it prominently at the top: "It looks like you were working on [X]"
- Suggest continuing it or confirm if it's done

---

## Step 7: Present Output

Keep it **short and direct**. This is a quick orientation, not a report.

```
## Where You Are: [Phase Label]

**In progress:** [from active.md, if any]

### âœ“ Done
- [completed step name]
- [completed step name]

### â†’ Next up (REQUIRED)
**[Step name]** â€” [description]
Command: `[/command]`

### ~ Also available (OPTIONAL)
- **[Step name]** â€” [description] â†’ `/command`
- **[Step name]** â€” [description] â†’ `/command`

### Coming up after that
- [Next required step name] (`/command`)
- [Next required step name] (`/command`)

---
Approaching **[next phase]** gate â†’ run `/gate-check` when ready.
```

**Formatting rules:**
- `âœ“` for confirmed complete
- `â†’` for the current required next step (only one â€” the first blocker)
- `~` for optional steps available now
- Show commands inline as backtick code
- If a step has no command (e.g. "Implement Stories"), explain what to do instead of showing a slash command
- For MANUAL steps, ask the user: "I can't tell if [step] is done â€” has it been completed?"

Verdict: **COMPLETE** â€” next steps identified.

---

## Step 8: Gate Warning (if close)

After the current phase's steps, check if the user is likely approaching a gate:
- If all required steps in the current phase are complete (or nearly complete),
  add: "You're close to the **[Current] â†’ [Next]** gate. Run `/gate-check` when ready."
- If multiple required steps remain, skip the gate warning â€” it's not relevant yet.

---

## Step 9: Escalation Paths

After the recommendations, if the user seems stuck or confused, add:

```
---
Need more detail?
- `/project-stage-detect` â€” full gap analysis with all missing artifacts listed
- `/gate-check` â€” formal readiness check for your next phase
- `/start` â€” re-orient from scratch
```

Only show this if the user's input suggested confusion (e.g. "I don't know", "stuck",
"lost", "not sure"). Don't show it for simple "what's next?" queries.

---

## Collaborative Protocol

- **Never auto-run the next skill.** Recommend it, let the user invoke it.
- **Ask about MANUAL steps** rather than assuming complete or incomplete.
- **Match the user's tone** â€” if they sound stressed ("I'm totally lost"), be
  reassuring and give one action, not a list of six.
- **One primary recommendation** â€” the user should leave knowing exactly one thing
  to do next. Optional steps and "coming up" are secondary context.
