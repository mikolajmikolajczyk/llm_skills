---
name: radboard
description: >
  Radboard label conventions for Radicle issues and patches. Use when
  authoring issues/patches in a project tracked by radboard so the
  kanban board, priority ordering, milestones, blocker links, and
  patch↔issue linking light up automatically. Pairs with the radicle
  skill — radicle covers the rad CLI, radboard covers what to put in
  titles/labels/commit subjects.
triggers:
  - radboard
  - kanban
  - "state:"
  - "priority:"
  - "milestone:"
  - "blocked:"
  - issue label
  - patch label
min_trust: guest
user-invocable: false
allowed-tools: Bash
---

# Radboard Skill

Radboard is a Tauri desktop kanban over Radicle. It does not store data of
its own — every board state comes from Radicle issues, patches, and
labels. To make a project "radboard-ready" out of the box, follow the
label and title conventions below.

This skill assumes you can already drive `rad` (see the `radicle` skill).

## TL;DR cheat sheet

| Convention | Effect in radboard |
|------------|--------------------|
| `state:<col>` label on open issue | Places card in dynamic kanban column `<col>` |
| `priority:critical\|high\|medium\|low` | Orders card inside Open column; colored badge |
| `milestone:<name>` (prefix configurable) | Groups issues in Milestones view, progress bar |
| `blocked:<hex7>` label | Renders a "blocked by #<hex7>" chip linking to that issue |
| `blocked:<free-text>` label | Renders a non-link blocker chip (e.g. `blocked:awaiting-design`) |
| 7-char hex prefix of issue ID in patch title | Patch appears as indicator on that issue's card |
| 7-char hex prefix in patch description | Same |
| 7-char hex prefix in **commit subject** | Same — use this for multi-issue patches |
| Issue `--solved` (not `--closed`) when finishing | Card moves to Closed column with "solved" status |

## Label conventions (the contract)

Radboard parses four reserved label prefixes. Anything else is treated as
a plain label chip.

### `state:<column>` — kanban column for open issues

- Drives column membership in the kanban view.
- `Open` and `Closed` columns are always present and bracket dynamic
  columns. Don't add `state:open` or `state:closed` — useless.
- Typical values: `state:triage`, `state:in-progress`, `state:review`,
  `state:blocked`. Pick whatever workflow you want — the column appears
  automatically once any open issue has the label.
- Closed/solved issues ignore any lingering `state:*` label and sit in
  the Closed column regardless.
- Moving a card in the UI rewrites this label.

```bash
rad issue label <ID> -a state:in-progress
rad issue label <ID> -d state:triage           # remove old before adding new
```

When opening an issue you want to land in a specific column from day one:

```bash
rad issue open -t "Title" -d "Body" --labels state:in-progress,priority:high
```

### `priority:critical|high|medium|low` — ordering + badge

- **Exactly these four values.** Anything else (`priority:p1`,
  `priority:urgent`) is ignored by the priority logic and rendered as a
  plain label.
- Orders cards inside the Open column (`critical` on top, `low` at the
  bottom).
- Drives a colored priority badge on the card.

```bash
rad issue label <ID> -a priority:critical
```

### `milestone:<name>` — milestone grouping (prefix configurable)

- Default prefix: `milestone:`. The user can change it per-board to e.g.
  `m:` or `release:` via `LocalConfig.milestonePrefix`. **Do not hardcode
  `milestone:` in tooling — read it from config if you have access; if
  not, ask before assuming.**
- Issues can have multiple milestone labels (e.g. shipped in
  both `v0.5.0` and a tracking milestone).
- Sort behavior:
  - Semver values (`v1.0.0`) sort ascending and are grouped under a
    "Released" / "Upcoming" split.
  - Numeric prefixes (`0-alpha`, `1-beta`) get stripped + title-cased
    for display, sort by the numeric prefix.
  - Everything else: alphabetical.
- A milestone with all issues solved/closed shows as 100% in the
  progress bar.

```bash
rad issue label <ID> -a milestone:v0.6.0
```

### `blocked:<value>` — blocker chips and graph

Two flavours, both rendered as red chips on the card:

- **`blocked:<hex7>`** where `<hex7>` is a 7-character hex prefix of
  another issue's ID. Becomes a clickable link to that issue. Radboard
  also builds the inverse map ("issue X blocks issues Y, Z") for the
  detail sidebar.
- **`blocked:<free-text>`** for external blockers
  (e.g. `blocked:awaiting-design`, `blocked:upstream`, `blocked:dead123`
  where the hex doesn't match a real issue). Rendered as a plain
  non-link blocker chip.

```bash
# Issue 89a5bb2 is blocked by issue 586feea:
rad issue label 89a5bb2 -a blocked:586feea

# Issue is blocked by an external constraint:
rad issue label 89a5bb2 -a blocked:awaiting-design
```

Use 7 chars — radboard matches against the first 7 hex chars of issue IDs.
A full 40-char hex won't link.

## Patch ↔ issue linking

Radboard links patches to issues by scanning for **7-char hex prefixes**
of issue IDs in three places:

1. Patch **title**
2. Patch **description**
3. Each commit's **subject line**

If any hex7 in those texts matches an open/closed issue's ID prefix, the
patch shows up as an indicator on that issue's kanban card, and the
issue is listed in the patch's "linked issues" section.

### Single-issue patch

Easiest: put the hex7 in brackets in the patch title.

```bash
git push rad HEAD:refs/patches \
  -o patch.message="[abc1234] fix: tighten auth check" \
  -o patch.message="Long-form description here."
```

Or include it inline:

```
feat: add csv export for abc1234
```

### Multi-issue patch (the radboard-specific trick)

When one patch resolves several issues, do **not** cram every ID into
the title. Instead, give the patch a clean title and put one issue ID
per commit subject:

```
Sprint cleanup batch         <- patch title (no hex needed)
├─ fix: validate input bounds for 0d948aa
├─ feat: add csv export for 3ca544a
└─ docs: clarify retry semantics for e9f1c22
```

Radboard scans all three commit subjects and links the patch to issues
`0d948aa…`, `3ca544a…`, and `e9f1c22…` automatically. No UI changes
needed on either side.

### Conventional commit recipe

A safe template for any commit subject:

```
<type>: <short summary> (<hex7>)
```

The `<hex7>` can appear anywhere in the subject — start, middle, end,
brackets, parens — the regex is `/[0-9a-f]{7}/gi`. Be wary of
accidental matches: 7 consecutive hex chars in a path or random string
will be treated as an issue prefix. Prefer the `(hex7)` or `[hex7]`
form for clarity.

## Issue state semantics (radicle gotcha worth repeating)

Radboard maps Radicle issue states directly:

- `open` → Open column (or dynamic `state:*` column)
- `solved` → Closed column, "solved" badge — use for **completed** work
- `closed` → Closed column, "closed" badge — use for **abandoned /
  won't-fix**

When finishing work:

```bash
rad issue state --solved <ID>     # NOT --closed
```

Closed-as-abandoned and solved-as-done look different on the board.
Don't pick `--closed` out of GitHub muscle memory.

## Editing issue descriptions

Use `rad issue edit -d "…"` to fix or expand the description. Don't add
comments to patch up the description — radboard renders the description
prominently and comments separately. Comments are for discussion.

## Assignees

Radboard surfaces assignees as avatar chips on cards and filters in the
toolbar. Use the standard `rad issue assign`:

```bash
rad issue assign <ID> -a <DID>
rad issue assign <ID> -d <DID>     # unassign
```

Aliases are resolved through the local Radicle alias store — assign by
DID, the UI shows the alias.

## Worktree / sync conventions

Radboard creates patch worktrees as **siblings of the main clone**, e.g.
`<parent>/<repo>-<branch>/`. When scripting around an existing radboard
project:

- Don't put worktrees inside the main clone — radboard's local-repo
  scan won't find them and the user's worktree picker will desync.
- Default branch comes from the Radicle identity document, not from
  `origin/HEAD`. If you create patches against `main` but the repo's
  default is `master`, radboard's sync banner will flag every patch as
  behind. Match the repo's default branch.

## Putting it all together (end-to-end recipe)

For a brand-new project that should "just work" in radboard:

1. **Init repo and pick label vocabulary up front.** Decide your state
   columns now — easier than rewiring later.
   ```bash
   rad init -t "myproject" -d "..." --default-branch master
   ```
2. **Open issues with state + priority from the start.**
   ```bash
   rad issue open -t "Add CSV export" -d "..." \
     --labels state:triage,priority:medium,milestone:v0.1.0
   ```
3. **When you start work, move the card.**
   ```bash
   rad issue label <ID> -d state:triage
   rad issue label <ID> -a state:in-progress
   ```
4. **When you push a patch, encode the issue ID(s).**
   - Single issue: `[<hex7>]` in patch title.
   - Multiple issues: clean title, one `<hex7>` per commit subject.
5. **When the patch merges, mark issues solved.**
   ```bash
   rad issue state --solved <ID>
   ```
6. **For tracking dependencies**, add `blocked:<hex7>` labels — the
   blocker graph populates automatically.

Following this recipe means radboard's kanban view, priority ordering,
milestone progress bars, blocker chips, and patch indicators all light
up with zero extra configuration.

## Gotchas

1. `state:open` / `state:closed` are no-ops — `Open` and `Closed` are
   built-in columns. Removing them is fine, adding them is noise.
2. Only the four canonical `priority:*` values get the priority badge
   and ordering. `priority:p1` shows as a plain label.
3. The milestone prefix is **configurable** per board — don't assume
   `milestone:`.
4. `blocked:<hex7>` only links if the hex matches a real issue prefix
   in the same repo. Mismatches render as a plain blocker chip.
5. Patch-issue linking uses **7-char hex**. Shorter prefixes are
   ignored; longer ones still match on the first 7 chars but may also
   catch unintended substrings.
6. Use `rad issue state --solved`, not `--closed`, for completed work.
7. Closed/solved issues ignore lingering `state:*` labels — safe to
   leave the label in place after solving, but it has no effect.
8. Don't bake `state:`, `priority:`, `milestone:`, or `blocked:`
   prefixes into label names users will pick (e.g. don't name a regular
   label `state-machine` — fine; `state:machine` — collides with the
   dynamic-column logic).
