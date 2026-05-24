---
name: skill-test
model: claude-sonnet-4-6
description: "Validate skill files for structural compliance and behavioral correctness. Three modes: static (linter), spec (behavioral), audit (coverage report)."
argument-hint: "static [skill-name | all] | spec [skill-name] | category [skill-name | all] | audit"
user-invocable: true
allowed-tools: Read, Glob, Grep, Write
---

# Skill Test

Validates `.claude/skills/*/SKILL.md` files for structural compliance and
behavioral correctness. No external dependencies â€” runs entirely within the
existing skill/hook/template architecture.

**Four modes:**

| Mode | Command | Purpose | Token Cost |
|------|---------|---------|------------|
| `static` | `/skill-test static [name\|all]` | Structural linter â€” 7 compliance checks per skill | Low (~1k/skill) |
| `spec` | `/skill-test spec [name]` | Behavioral verifier â€” evaluates assertions in test spec | Medium (~5k/skill) |
| `category` | `/skill-test category [name\|all]` | Category rubric â€” checks skill against its category-specific metrics | Low (~2k/skill) |
| `audit` | `/skill-test audit` | Coverage report â€” skills, agent specs, last test dates | Low (~3k total) |

---

## Phase 1: Parse Arguments

Determine mode from the first argument:

- `static [name]` â†’ run 7 structural checks on one skill
- `static all` â†’ run 7 structural checks on all skills (Glob `.claude/skills/*/SKILL.md`)
- `spec [name]` â†’ read skill + test spec, evaluate assertions
- `category [name]` â†’ run category-specific rubric from `CCGS Skill Testing Framework/quality-rubric.md`
- `category all` â†’ run category rubric for every skill that has a `category:` in catalog
- `audit` (or no argument) â†’ read catalog, list all skills and agents, show coverage

If argument is missing or unrecognized, output usage and stop.

---

## Phase 2A: Static Mode â€” Structural Linter

For each skill being tested, read its `SKILL.md` fully and run all 7 checks:

### Check 1 â€” Required Frontmatter Fields
The file must contain all of these in the YAML frontmatter block:
- `name:`
- `description:`
- `argument-hint:`
- `user-invocable:`
- `allowed-tools:`

**FAIL** if any are absent.

### Check 2 â€” Multiple Phases
The skill must have â‰¥2 numbered phase headings. Look for patterns like:
- `## Phase N` or `## Phase N:`
- `## N.` (numbered top-level sections)
- At least 2 distinct `##` headings if phases aren't explicitly numbered

**FAIL** if fewer than 2 phase-like headings are found.

### Check 3 â€” Verdict Keywords
The skill must contain at least one of: `PASS`, `FAIL`, `CONCERNS`, `APPROVED`,
`BLOCKED`, `COMPLETE`, `READY`, `COMPLIANT`, `NON-COMPLIANT`

**FAIL** if none are present.

### Check 4 â€” Collaborative Protocol Language
The skill must contain ask-before-write language. Look for:
- `"May I write"` (canonical form)
- `"before writing"` or `"approval"` near file-write instructions
- `"ask"` + `"write"` in close proximity (within same section)

**WARN** if absent (some read-only skills legitimately skip this).
**FAIL** if `allowed-tools` includes `Write` or `Edit` but no ask-before-write language is found.

### Check 5 â€” Next-Step Handoff
The skill must end with a recommended next action or follow-up path. Look for:
- A final section mentioning another skill (e.g., `/story-done`, `/gate-check`)
- "Recommended next" or "next step" phrasing
- A "Follow-Up" or "After this" section

**WARN** if absent.

### Check 6 â€” Fork Context Complexity
If frontmatter contains `context: fork`, the skill should have â‰¥5 phase headings
(`##` level or numbered Phase N headers). Fork context is for complex multi-phase
skills; simple skills should not use it.

**WARN** if `context: fork` is set but fewer than 5 phases found.

### Check 7 â€” Argument Hint Plausibility
`argument-hint` must be non-empty. If the skill body mentions multiple modes
(e.g., "Mode A | Mode B"), the hint should reflect them. Cross-reference the
hint against the first phase's "Parse Arguments" section.

**WARN** if hint is `""` or if documented modes don't match hint.

---

### Static Mode Output Format

For a single skill:
```
=== Skill Static Check: /[name] ===

Check 1 â€” Frontmatter Fields:    PASS
Check 2 â€” Multiple Phases:       PASS (7 phases found)
Check 3 â€” Verdict Keywords:      PASS (PASS, FAIL, CONCERNS)
Check 4 â€” Collaborative Protocol: PASS ("May I write" found)
Check 5 â€” Next-Step Handoff:     WARN (no follow-up section found)
Check 6 â€” Fork Context Complexity: PASS (8 phases, context: fork set)
Check 7 â€” Argument Hint:         PASS

Verdict: WARNINGS (1 warning, 0 failures)
Recommended: Add a "Follow-Up Actions" section at the end of the skill.
```

For `static all`, produce a summary table then list any non-compliant skills:
```
=== Skill Static Check: All 52 Skills ===

Skill                  | Result       | Issues
-----------------------|--------------|-------
gate-check             | COMPLIANT    |
design-review          | COMPLIANT    |
story-readiness        | WARNINGS     | Check 5: no handoff
...

Summary: 48 COMPLIANT, 3 WARNINGS, 1 NON-COMPLIANT
Aggregate Verdict: N WARNINGS / N FAILURES
```

---

## Phase 2B: Spec Mode â€” Behavioral Verifier

### Step 1 â€” Locate Files

Find skill at `.claude/skills/[name]/SKILL.md`.
Look up the spec path from `CCGS Skill Testing Framework/catalog.yaml` â€” use the
`spec:` field for the matching skill entry.

If either is missing:
- Missing skill: "Skill '[name]' not found in `.claude/skills/`."
- Missing spec path in catalog: "No spec path set for '[name]' in catalog.yaml."
- Spec file not found at path: "Spec file missing at [path]. Run `/skill-test audit`
  to see coverage gaps."

### Step 2 â€” Read Both Files

Read the skill file and test spec file completely.

### Step 3 â€” Evaluate Assertions

For each **Test Case** in the spec:

1. Read the **Fixture** description (assumed state of project files)
2. Read the **Expected behavior** steps
3. Read each **Assertion** checkbox

For each assertion, evaluate whether the skill's written instructions, if
followed correctly given the fixture state, would satisfy it. This is a
Claude-evaluated reasoning check, not code execution.

Mark each assertion:
- **PASS** â€” skill instructions clearly satisfy this assertion
- **PARTIAL** â€” skill instructions partially address it, but with ambiguity
- **FAIL** â€” skill instructions would NOT satisfy this assertion given the fixture

For **Protocol Compliance** assertions (always present):
- Check whether the skill requires "May I write" before file writes
- Check whether the skill presents findings before requesting approval
- Check whether the skill ends with a recommended next step
- Check whether the skill avoids auto-creating files without approval

### Step 4 â€” Build Report

```
=== Skill Spec Test: /[name] ===
Date: [date]
Spec: CCGS Skill Testing Framework/skills/[category]/[name].md

Case 1: [Happy Path â€” name]
  Fixture: [summary]
  Assertions:
    [PASS] [assertion text]
    [FAIL] [assertion text]
       Reason: The skill's Phase 3 says "..." but the fixture state means "..."
  Case Verdict: FAIL

Case 2: [Edge Case â€” name]
  ...
  Case Verdict: PASS

Protocol Compliance:
  [PASS] Uses "May I write" before file writes
  [PASS] Presents findings before asking approval
  [WARN] No explicit next-step handoff at end

Overall Verdict: FAIL (1 case failed, 1 warning)
```

### Step 5 â€” Offer to Write Results

"May I write these results to `CCGS Skill Testing Framework/results/skill-test-spec-[name]-[date].md`
and update `CCGS Skill Testing Framework/catalog.yaml`?"

If yes:
- Write results file to `CCGS Skill Testing Framework/results/`
- Update the skill's entry in `CCGS Skill Testing Framework/catalog.yaml`:
  - `last_spec: [date]`
  - `last_spec_result: PASS|PARTIAL|FAIL`

---

## Phase 2D: Category Mode â€” Rubric Evaluation

### Step 1 â€” Locate Skill and Category

Find skill at `.claude/skills/[name]/SKILL.md`.
Look up `category:` field in `CCGS Skill Testing Framework/catalog.yaml`.

If skill not found: "Skill '[name]' not found."
If no `category:` field: "No category assigned for '[name]' in catalog.yaml.
Add `category: [name]` to the skill entry first."

For `category all`: collect all skills with a `category:` field and process each.
`category: utility` skills are evaluated against U1 (static checks pass) and U2
(gate mode correct if applicable) only â€” skip to the static mode for U1.

### Step 2 â€” Read Rubric Section

Read `CCGS Skill Testing Framework/quality-rubric.md`.
Extract the section matching the skill's category (e.g., `### gate`, `### team`).

### Step 3 â€” Read Skill

Read the skill's `SKILL.md` fully.

### Step 4 â€” Evaluate Rubric Metrics

For each metric in the category's rubric table:
1. Check whether the skill's written instructions clearly satisfy the criterion
2. Mark PASS, FAIL, or WARN
3. For FAIL/WARN, identify the exact gap in the skill text (quote the relevant section
   or note its absence)

### Step 5 â€” Output Report

```
=== Skill Category Check: /[name] ([category]) ===

Metric G1 â€” Review mode read:      PASS
Metric G2 â€” Full mode directors:   FAIL
  Gap: Phase 3 spawns only CD-PHASE-GATE; TD-PHASE-GATE, PR-PHASE-GATE, AD-PHASE-GATE absent
Metric G3 â€” Lean mode: PHASE-GATE only: PASS
Metric G4 â€” Solo mode: no directors:    PASS
Metric G5 â€” No auto-advance:       PASS

Verdict: FAIL (1 failure, 0 warnings)
Fix: Add TD-PHASE-GATE, PR-PHASE-GATE, and AD-PHASE-GATE to the full-mode director
     panel in Phase 3.
```

### Step 6 â€” Offer to Update Catalog

"May I update `CCGS Skill Testing Framework/catalog.yaml` to record this category check
(`last_category`, `last_category_result`) for [name]?"

---

## Phase 2C: Audit Mode â€” Coverage Report

### Step 1 â€” Read Catalog

Read `CCGS Skill Testing Framework/catalog.yaml`. If missing, note that catalog doesn't exist
yet (first-run state).

### Step 2 â€” Enumerate All Skills and Agents

Glob `.claude/skills/*/SKILL.md` to get the complete list of skills.
Extract skill name from each path (directory name).

Also read the `agents:` section from `CCGS Skill Testing Framework/catalog.yaml` to get the
complete list of agents.

### Step 3 â€” Build Skill Coverage Table

For each skill:
- Check if a spec file exists (use the `spec:` path from catalog, or glob `CCGS Skill Testing Framework/skills/*/[name].md`)
- Look up `last_static`, `last_static_result`, `last_spec`, `last_spec_result`,
  `last_category`, `last_category_result`, `category` from catalog (or mark as
  "never" / "â€”" if not in catalog)
- Priority comes from catalog `priority:` field (critical/high/medium/low)

### Step 3b â€” Build Agent Coverage Table

For each agent in catalog's `agents:` section:
- Check if a spec file exists (use the `spec:` path from catalog, or glob `CCGS Skill Testing Framework/agents/*/[name].md`)
- Look up `last_spec`, `last_spec_result`, `category` from catalog

### Step 4 â€” Output Report

```
=== Skill Test Coverage Audit ===
Date: [date]

SKILLS (72 total)
Specs written: 72 (100%) | Never static tested: 72 | Never category tested: 72

Skill                  | Cat      | Has Spec | Last Static | S.Result | Last Cat | C.Result | Priority
-----------------------|----------|----------|-------------|----------|----------|----------|----------
gate-check             | gate     | YES      | never       | â€”        | never    | â€”        | critical
design-review          | review   | YES      | never       | â€”        | never    | â€”        | critical
...

AGENTS (49 total)
Agent specs written: 49 (100%)

Agent                  | Category   | Has Spec | Last Spec   | Result
-----------------------|------------|----------|-------------|--------
creative-director      | director   | YES      | never       | â€”
technical-director     | director   | YES      | never       | â€”
...

Top 5 Priority Gaps (skills with no spec, critical/high priority):
(none if all specs are written)

Skill coverage:  72/72 specs (100%)
Agent coverage:  49/49 specs (100%)
```

No file writes in audit mode.

Offer: "Would you like to run `/skill-test static all` to check structural
compliance across all skills? `/skill-test category all` to run category rubric
checks? Or `/skill-test spec [name]` to run a specific behavioral test?"

---

## Phase 3: Recommended Next Steps

After any mode completes, offer contextual follow-up:

- After `static [name]`: "Run `/skill-test spec [name]` to validate behavioral
  correctness if a test spec exists."
- After `static all` with failures: "Address NON-COMPLIANT skills first. Run
  `/skill-test static [name]` individually for detailed remediation guidance."
- After `spec [name]` PASS: "Update `CCGS Skill Testing Framework/catalog.yaml` to record this
  pass date. Consider running `/skill-test audit` to find the next spec gap."
- After `spec [name]` FAIL: "Review the failing assertions and update the skill
  or the test spec to resolve the mismatch."
- After `audit`: "Start with the critical-priority gaps. Use the spec template
  at `CCGS Skill Testing Framework/templates/skill-test-spec.md` to create new specs."
