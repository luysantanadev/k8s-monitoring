---
name: session-handoff
description: 'Records project evolution by updating Memory Bank files so every new session resumes with full context. Use at the START of a session ("resume project", "what is the current state?") to load context, and at the END ("update memory bank", "record session progress", "session handoff") to persist what was done. Also updates automatically after successful progressive-commits milestones.'
license: MIT
---

# Session Handoff — Project Context Persistence

You maintain the Memory Bank so every AI session begins with accurate, complete context and leaves a documented trail of decisions and progress.

**Guiding principle**: The Memory Bank is the only link between sessions. If it is outdated, the next session hallucinates. Accuracy beats brevity.

---

## When to Use This Skill

| Trigger phrase                                                                      | Action                                                        |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| "resume project", "continue where we left off", "what is the state of the project?" | **Session START** → read all memory bank files                |
| "update memory bank", "record session progress", "session handoff", "save context"  | **Session END** → update all changed files                    |
| After each successful `progressive-commits` milestone                               | **Inline update** → update `activeContext.md` + `progress.md` |
| "add task", "create task"                                                           | Create task file in `memory-bank/tasks/`                      |
| "show tasks", "show tasks active"                                                   | Read `memory-bank/tasks/_index.md` and report                 |
| "mark task done [ID]"                                                               | Update task file and `_index.md`                              |

---

## Memory Bank Location

All files live under `memory-bank/` at the repository root:

```
memory-bank/
├── projectbrief.md       ← NEVER changes unless scope changes
├── productContext.md     ← WHY the project exists
├── systemPatterns.md     ← Architecture, ADRs, naming rules
├── techContext.md        ← Stack, tools, endpoints, credentials
├── activeContext.md      ← ALWAYS update: current focus + next steps
├── progress.md           ← What works, what's pending, known issues
└── tasks/
    ├── _index.md         ← Task registry (all statuses)
    └── TASK<N>-<name>.md ← One file per task
```

---

## SESSION START Workflow

Use the todo list to track and show the user your progress.

```
- [ ] Step 1: Read all memory bank files
- [ ] Step 2: Report current state to user
- [ ] Step 3: Clarify ambiguities before proceeding
```

### Step 1 — Read all memory bank files

Read these files in this order (they build on each other):

1. `memory-bank/projectbrief.md`
2. `memory-bank/productContext.md`
3. `memory-bank/systemPatterns.md`
4. `memory-bank/techContext.md`
5. `memory-bank/activeContext.md`
6. `memory-bank/progress.md`
7. `memory-bank/tasks/_index.md`

If any file is missing, report it as a gap. Do **not** invent content to fill it.

### Step 2 — Report current state

Present a concise summary:

```
## Project State: k8s-monitoring

**Current Focus:** [from activeContext.md]

**Recent Changes:**
- [bullet list from activeContext.md]

**Next Steps:**
- [bullet list from activeContext.md]

**Open Blockers:**
- [list from activeContext.md]
```

### Step 3 — Clarify before proceeding

If `activeContext.md` has empty or stale sections, ask the user:

- "The last session ended on [date]. Is the focus still X, or has it changed?"
- Do **not** proceed with assumptions if context is ambiguous.

---

## SESSION END Workflow

Use the todo list to track and show the user your progress.

```
- [ ] Step 1: Summarise what was accomplished
- [ ] Step 2: Update activeContext.md
- [ ] Step 3: Update progress.md
- [ ] Step 4: Update tasks/_index.md and any open task files
- [ ] Step 5: Update systemPatterns.md or techContext.md if patterns/tools changed
- [ ] Step 6: Confirm all files saved
```

### Step 1 — Summarise the session

Review the conversation and extract:

- What was built / changed / fixed
- Decisions made (especially ones that affect future work)
- Scripts or services confirmed working
- New patterns or conventions discovered
- Blockers encountered or resolved

### Step 2 — Update `activeContext.md`

Replace the three sections:

```markdown
## Current Focus

[New focus for the NEXT session, not what just happened]

## Recent Changes

- [Most recent change first]
- [Previous changes below]

## Next Steps

- [ ] [Concrete, actionable item the next session can start immediately]
```

**Rules**:

- "Current Focus" describes what the NEXT session should do, not the current session
- Keep "Recent Changes" to the last 2-3 sessions (remove stale entries)
- "Next Steps" items should be specific enough to execute without asking questions

### Step 3 — Update `progress.md`

- Mark completed items as ✅
- Add new items to "What's Left to Build" if discovered
- Update "Known Issues" table if issues appeared or were resolved
- Update the "Current Status" summary at the bottom

### Step 4 — Update `tasks/_index.md`

Move tasks between sections (In Progress / Completed / Pending / Abandoned).
For any task that had significant activity, update its individual file in `memory-bank/tasks/` with a new progress log entry.

### Step 5 — Update patterns/tech files (only if changed)

Update `systemPatterns.md` if:

- A new architectural decision was made (add as `ADR-NNN`)
- A naming convention was established or changed
- A new service/component was added to the architecture diagram

Update `techContext.md` if:

- A new tool/service was installed
- A new endpoint, port, or credential was added
- The tech stack changed

### Step 6 — Confirm

Report to the user:

```
Memory Bank updated. Session context saved:
- activeContext.md ✅
- progress.md ✅
- tasks/_index.md ✅
[any other files updated] ✅

Next session will resume at: [one-sentence summary of next steps]
```

---

## INLINE UPDATE (after progressive-commits milestone)

When a `progressive-commits` milestone succeeds (script runs, service deploys, feature ships), do a lightweight inline update **before** committing the memory bank changes:

1. In `activeContext.md`:
   - Move the completed item from "Next Steps" to "Recent Changes"
   - Add the next logical step to "Next Steps"
2. In `progress.md`:
   - Mark the completed item as ✅
3. Then commit the memory bank update alongside the milestone commit using type `docs` and scope `memory-bank`:
   ```
   docs(memory-bank): update progress after <milestone>
   ```

---

## Task Management

### Creating a task

When user says "add task" or "create task":

1. Assign the next sequential ID from `_index.md` (e.g., `TASK006`)
2. Create `memory-bank/tasks/TASK006-<kebab-name>.md` using this template:

```markdown
# TASK006 - <Task Name>

**Status:** Pending
**Added:** YYYY-MM-DD
**Updated:** YYYY-MM-DD

## Original Request

[Exact user request]

## Thought Process

[Discussion and reasoning behind the approach]

## Implementation Plan

- [ ] Step 1
- [ ] Step 2

## Progress Tracking

**Overall Status:** Not Started — 0%

### Subtasks

| ID  | Description | Status      | Updated | Notes |
| --- | ----------- | ----------- | ------- | ----- |
| 6.1 | ...         | Not Started | —       | —     |

## Progress Log

### YYYY-MM-DD

- Task created
```

3. Add the task to `_index.md` under "Pending"

### Updating a task

When user says "update task TASK006":

1. Open `memory-bank/tasks/TASK006-*.md`
2. Update the subtask table
3. Add a new progress log entry with today's date
4. Update `_index.md` if status changed

---

## Rules for All Updates

| Rule                              | Explanation                                                                                   |
| --------------------------------- | --------------------------------------------------------------------------------------------- |
| **Accuracy over speed**           | Verify claims against actual file state — never assume                                        |
| **Never delete history**          | Add to progress logs, don't overwrite. Move tasks, don't delete them                          |
| **Separate facts from intent**    | `[TODO]` = unknown, `[PLANNED]` = planned but not started                                     |
| **Keep `activeContext.md` short** | Max ~30 lines. It's read first every session — density matters                                |
| **Date all entries**              | Every progress log entry gets a `YYYY-MM-DD` header                                           |
| **Commit memory bank updates**    | After any session-end update, recommend a commit: `docs(memory-bank): update session context` |

---

## Anti-Patterns to Avoid

| ❌ Don't                                                                     | ✅ Do instead                                                   |
| ---------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Leave `activeContext.md` with stale "Current Focus" from a completed session | Update to reflect what the NEXT session should start            |
| Write "fixed things" without specifying what                                 | "Fixed Redis ServiceMonitor label selector mismatch"            |
| Mark items complete without verifying the output                             | Check `kubectl get pods`, exit code, or endpoint response first |
| Create a task file but forget to add it to `_index.md`                       | Always update both                                              |
| Update only `activeContext.md` and skip `progress.md`                        | Both must be updated at session end                             |

---

## Integration with progressive-commits

This skill pairs with `progressive-commits`:

```
Execute step
    ↓
Verify success
    ↓
Update memory-bank (activeContext + progress)
    ↓
git add memory-bank/
    ↓
Conventional commit: "docs(memory-bank): update after <step>"
    ↓
Proceed to next step
```

The memory bank becomes part of the commit history, making session context traceable via `git log`.
