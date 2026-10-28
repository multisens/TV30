# Contributing

This repository is a testbed for the TV 3.0 application coding layer, *ABNT NBR 25608 — TV 3.0 —
Application coding*. Its observable behaviour follows the standard; everything else is a choice of
this project and should be documented as such.

The rules below apply to people and to coding agents alike.

---

## What goes into the repository

Only the testbed's code, configuration, tests and the documentation that describes them.

Keep out of version control:

- **Agent instructions** — `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, skills, agent settings. Keep
  them as local copies (e.g. `CLAUDE.local.md`) and exclude them in `.git/info/exclude`.
- **Task material** — plans, notes, pending decisions, work logs, task folders.
- **Documents from other projects** — the standard, scope documents, specifications, evaluations.
  Read them where they live; do not copy them in.
- **Anything tied to one machine** — personal paths, local network addresses, secrets.

---

## Code

- **Keep it simple.** Before writing a helper, check the standard library and the existing
  dependencies.
- **Only what is asked.** Implement what the standard or the task requires, nothing speculative.
- **Fail early and loudly.** Validate input, check the environment at startup, never swallow an
  error.
- **Least surprise.** A name says what the code does. If name and behaviour disagree, fix one of
  them; do not explain the gap in a comment.
- **Input outside the standard is rejected** with the standard's error code, not tolerated.
- **Configuration comes from the environment** — addresses, ports, paths, secrets — and is checked
  at startup.
- **No dead code.** No commented-out code, no function without a caller. A feature that is off is
  removed or switched off by configuration, and listed as not implemented.
- **Ask before adding a dependency.**
- **Before you are done,** run the type checker and the tests of the submodule you touched. Style
  fixes go in a separate commit from behaviour changes.

Names and comments are in English. Comments wrap at 80 columns. File and folder names are lower
case, `kebab-case` when there is more than one word. In Go, `gofmt` wins.

---

## Comments

**Comment the contract, not the obvious.** Comment a function, type or constant when its contract
cannot be read from the name and signature. Getters, setters and route handlers that only pass on to
a service get no comment.

**Say what the code does:** what it returns in each case, the standard's error codes, side effects,
what it ignores or drops.

```ts
// Returns null if no session has the id.
```

**Only what the code does.** No design decisions, no rationale, no history — those belong in the
documentation or the commit message. The one exception is an ordering or atomicity constraint that
the next change could break, with what it prevents:

```ts
// No await between the check and the write: another request could change
// the state in between.
```

**Keep it true.** When behaviour changes, the comment changes in the same commit. Do not write who
calls the code; that changes without anyone touching the comment.

**No commented-out code.** A `TODO` marking what is missing at that point is fine.

**Do not repeat a value declared elsewhere.** The exception is a value imposed by the standard,
cited:

```ts
// Port fixed by the standard (C.3.4).
```

**Place comments on the line above** the declaration, never at the end of the line. Inside a
function body, only to mark a step or a constraint.

**Citing the standard.** Cite the section, table or figure that defines the behaviour, with the
number checked against the text the code implements. Code in an API version folder (e.g.
`src/v<X.Y>/`) uses the numbering of that version's text, unmarked; elsewhere the number is the
published standard's, and a proposal is named (`C.x.y (proposal <n>)`).

| Declaration | Form | Example |
|---|---|---|
| Route | section + section title | `// C.x.y - <section title>` |
| Data type | section + table | `// C.x.y, Table C.n` |
| Function | section, table or figure + what it does | `// Figure C.n: <what the function does>` |

---

## Documentation

- **One fact, one place.** A fact is stated once; other pages link to it. A behaviour change
  updates the documentation in the same commit.
- **Describe what the code does today**, checked in the code body, not inferred from a name.
  Intended design may be described, in its own section and marked as such. Highlighted statements
  ("Important", "Core rule") and diagrams get checked first: they are the ones that spread.
- **List what is not implemented** and every divergence from the standard, each with its section.
  Divergent behaviour is never described as a feature.
- **Standard or testbed choice?** Say which wherever it matters — ports, access surfaces, client
  classes, messaging, gateways, storage. A value fixed by the standard cites its section.
- **Use the standard's terms** (TV 3.0 WebServices), and do not reuse a term the standard defines
  for something else.
- **Tables are complete** — topics, routes, ports, keys, containers — including what is outside the
  standard, marked as such, with exact names.
- **Cite the standard by its title**, not by a file in the repository. Section numbers follow the
  rule in *Comments*.
- **Describe, do not justify.** Pages about the current system say what exists, in the present
  tense; decisions and their rationale do not go there.

---

## Before opening a pull request

- [ ] Every statement about behaviour was read in the code body.
- [ ] No comment justifies, tells history or records a decision.
- [ ] No commented-out code; anything switched off is listed as not implemented.
- [ ] Every section, table and figure number was checked against the right version of the text.
- [ ] Standard and testbed choices are told apart.
- [ ] Nothing was repeated in a second page.
- [ ] No agent instructions, task material or machine-specific paths in the diff.
- [ ] Type checker and tests pass.

## For coding agents

The rules above apply unchanged. In addition: a name in this repository is not evidence of
behaviour — read the body before relying on it. Keep your instructions and task notes outside
version control.
