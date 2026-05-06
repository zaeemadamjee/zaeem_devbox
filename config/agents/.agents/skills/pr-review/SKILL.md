---
name: pr-review
description: >
  Pull, review, test, and summarize a GitHub pull request. Use when asked to
  review a PR, given a PR URL or number. Gathers context from the codebase,
  Linear, Notion, and Slack, then produces a structured review.
---

# PR Review

## Mindset

Approach every review as a principal-level software engineer. You are not
checking boxes — you are evaluating whether this change is something you would
be comfortable deploying to production and maintaining long-term. Prioritize
judgment over process. Focus on what matters: correctness, security, clarity,
and whether the change moves the codebase in a good direction. Be direct, be
concise, and don't waste the author's time on trivia when there are substantive
things to discuss.

---

## Read-Only Mode

**You are strictly read-only for the entire duration of this skill.**

- Do NOT edit, write, or create any files.
- Do NOT make commits, push branches, or modify git state.
- Do NOT approve, merge, comment on, or request changes to the PR via `gh`.
- Do NOT run commands that mutate state (no `npm install`, no `make build`, etc.).
- You may READ anything: files, diffs, git log, test output (dry-run only), tool APIs.
- If a step below says "run tests," read the test configuration and report what
  *would* need to pass — do not execute them unless the user explicitly asks.

If the user wants you to take action (post a comment, approve, etc.), confirm
with them first and only proceed with their explicit go-ahead.

---

## Review Depth

This skill supports three depth levels. **Default is `deep` if not specified.**

| Depth | What it does |
|-------|--------------|
| `quick` | Fetch PR metadata, read the diff, classify the PR type. Skip external context (Linear, Notion, Slack). Skip related PR analysis. Produce the review from the diff alone. |
| `standard` | Everything in quick, plus: explore neighboring files, check Linear by branch name, search Notion by title, read existing tests. |
| `deep` | Everything in standard, plus: full Linear fallback chain, Slack search, read recent merged PRs on the same files, trace downstream consumers, check commit history, cross-check acceptance criteria. |

Adjust your work accordingly. The output format is the same at all depths — if
a section has no findings because work was skipped, write "Skipped (quick review)."

---

## 1. Fetch PR Metadata

```bash
gh pr view <number> --json number,title,body,author,baseRefName,headRefName,files,additions,deletions,labels,reviewRequests,milestone
```

Extract:
- PR number, title, author
- Branch names (head → base)
- File list, additions/deletions counts
- Labels, milestone, linked issues

---

## 2. Classify PR Type

Before diving into the diff, classify the PR into one of these types based on
the title, labels, branch name, and file list:

| Type | Signals | Section emphasis |
|------|---------|-----------------|
| **Feature** | New files, new endpoints, `feat/` branch | Security, Test Analysis, Acceptance Criteria |
| **Bugfix** | `fix/` branch, issue reference, small diff | Security & Correctness, Test Analysis |
| **Refactor** | Renames, moves, no behavior change | Style & Consistency, Before/After Structure |
| **Config / Infra** | CI, Dockerfile, terraform, env vars | Security, File Heatmap |
| **Dependency** | lockfile changes, version bumps | Security, File Heatmap |
| **Docs** | Markdown, comments only | Style & Consistency, Strengths |

State the detected type in the metadata table. Use it to weight your attention
across the review sections — spend more time on the emphasized sections and keep
the others brief.

For **refactor** PRs, replace the Security & Correctness section with a
**Before / After Structure** section that describes what the code looked like
architecturally before the change and after. Focus on module boundaries, naming,
data flow — not line-by-line diffs.

---

## 3. Read the Diff

```bash
gh pr diff <number>
```

Read the full diff. For large PRs (>1000 lines), prioritize:
1. New files first
2. Files with the most changes
3. Config/infra changes
4. Test changes last

---

## 4. Explore the Codebase

Before forming opinions, gather context:

- Read files neighboring the changed files to understand conventions.
- Check `git log --oneline -20 -- <changed-file>` for recent history on key files.
- Look at existing tests for the modules being changed.
- Search for related patterns in the codebase (e.g., if a new API endpoint is added,
  find how existing endpoints are structured).
- **Trace downstream consumers:** For each modified file, check what imports or
  depends on it. Note these in the File Heatmap.

---

## 5. Check Related PRs

_Skip at `quick` depth._

Find recently merged PRs that touch the same files:

```bash
gh pr list --state merged --limit 10 --search "<changed-file-name>"
```

Look for:
- Conflicting or overlapping changes that this PR might not account for.
- Patterns established by recent PRs that this one follows or breaks.
- Work-in-progress that this PR might interact with.

Note relevant related PRs in the Review Context section of the output.

---

## 6. Gather External Context

Attempt each of the following. If a tool is unavailable, note it using the
format shown in the output template (`Tools unavailable` blockquote). Do not
skip the rest of the review.

### Linear

Search for the related issue using these methods in order. Stop once you find a match:

1. **Branch name** — Extract an issue identifier from the head branch (e.g., `feat/ENG-123-some-feature` → `ENG-123`). Search Linear by identifier.
2. **PR title/body** — Look for issue keys mentioned in the PR title or description.
3. **Keyword search** — Search Linear by keywords from the PR title. _(deep only)_
4. **Recent team issues** — List recent issues for the team and look for a plausible match. _(deep only)_

Once found, gather: title, description, acceptance criteria, parent/sub-issues, project, cycle, and priority.

### Notion

- Search Notion for documents related to the PR title, linked Linear issue, or feature name.
- Look for specs, RFCs, design docs, or meeting notes that provide background.

### Slack

_Deep depth only._

- Search for recent threads about the feature or issue.
- Look for decisions or discussions that inform the PR's approach.

### Other Sources

- Check PR comments and review threads on GitHub for prior discussion.
- Look at related/linked PRs via `gh pr list --search "<keyword>"`.

---

## 7. Produce the Review

Output the review using **exactly** the format below. Every review must have
every section. If a section has no findings, write "No issues found." Do not
omit sections.

---

## Output Format

When referencing code throughout the review, always use the pattern
`path/to/file.ts:42` so the reader can navigate directly to the source.

Get the repo name from the git remote or `gh repo view --json nameWithOwner`.

````markdown
# <owner>/<repo> — PR #<number>: <title>

| | |
|---|---|
| **Repo** | `<owner>/<repo>` |
| **Branch** | `<head>` → `<base>` |
| **Author** | @<username> |
| **Type** | Feature / Bugfix / Refactor / Config / Dependency / Docs |
| **Changes** | <file count> files (+<additions>, -<deletions>) |
| **Context** | [ENG-123](link), [Design Doc](link) |

---

## Review Context

One sentence on what you reviewed, then bullets for specific sources. Keep it tight.

Reviewed the diff and <N> neighboring files in `src/module/`. Checked CI status on GitHub.

- **Linear:** [ENG-123 — Issue title](link) _(or: no matching issue found)_
- **Notion:** [Design Doc title](link) _(or: no relevant pages found)_
- **Slack:** #channel — [thread title](link) _(or: unavailable, no MCP configured)_
- **Related PRs:** #138, #140 touch the same files _(or: none found)_

> **Tools unavailable:** <tool1>, <tool2>

_Only include the tools-unavailable notice if any tools were actually missing. Omit it entirely otherwise._

---

## Executive Summary

- **What:** 1 sentence on what the PR does, referencing org context (link to Linear issue, Notion doc, etc.).
- **How:** 1 sentence on the approach or key technical decision.
- **Scope:** 1 sentence on the blast radius — what areas of the codebase are touched and why.

---

## File Heatmap

Rank every changed file from most risky to least risky. Assess risk based on:

- **Logic changes in critical paths** — auth, payments, data mutations, security boundaries.
- **Blast radius** — how many other files import or depend on this file.
- **Complexity of the change** — new branching logic, error handling changes, state mutations.

Risk levels are **absolute, not relative.** If every file in the PR is a safe
change, every row should be 🟢. Do not inflate risk to fill the scale.

| Risk | File | Consumers | Notes |
|------|------|-----------|-------|
| 🔴 Critical | `path/to/file.ts` | `a.ts`, `b.ts`, `c.ts` | One-line reason |
| 🟢 Safe | `path/to/other.ts` | `tests/other.test.ts` | One-line reason |

---

## Acceptance Criteria

_If a Linear issue with acceptance criteria was found, cross-check each
criterion against the diff. If no criteria exist, write "No acceptance criteria
found on linked issue." If no issue was found at all, write "No linked issue."_

| Criterion | Status |
|-----------|--------|
| Description of the criterion from the issue | ✅ Met / ❌ Not met / ❓ Unclear |

---

## Security & Correctness

_For refactor PRs, replace this section with **Before / After Structure** —
describe the architectural shape of the code before and after the change.
Focus on module boundaries, naming, and data flow, not line-by-line diffs._

Reserve 🔴 Critical and 🟠 High for **real** correctness bugs or security
vulnerabilities — logic that is actually wrong, data that can be lost, or an
attack surface that is actually exploitable. Use 🟡 Medium and 🟢 Low for
things worth mentioning that don't pose a current threat (e.g., a missing
validation that can't be reached yet, a theoretical race condition).

| Severity | Finding |
|----------|---------|
| <emoji> <level> | Brief one-line description (`path/to/file.ts:42`) |

<details>
<summary>Details</summary>

**<Finding title>**

Explanation of the issue, why it matters, and what the correct behavior should be.

```diff
- problematic code
+ suggested fix or reference
```

</details>

---

## Style & Consistency

| Severity | Finding |
|----------|---------|
| <emoji> <level> | Brief one-line description (`path/to/file.ts:42`) |

<details>
<summary>Details</summary>

**<Finding title>**

Explanation referencing existing codebase patterns. Quote the convention being
followed or broken and where the canonical example lives.

</details>

---

## Test Analysis

Check the following:

- Is every new code path covered by a test?
- Are there old test paths that are now dead code and should be deleted?
- Check CI status: `gh pr checks <number>`. Report whether tests are passing,
  failing, or pending on GitHub.

| Severity | Finding |
|----------|---------|
| <emoji> <level> | Brief one-line description |

<details>
<summary>Details</summary>

**<Finding title>**

What is missing or could be stronger, and why it matters.

</details>

---

## Strengths

- **<Title>** — Why this is good and worth calling out.
- **<Title>** — What pattern or practice is well-executed.

---

## Improvements

| Priority | Suggestion |
|----------|------------|
| <emoji> <level> | Brief one-line suggestion (`path/to/file.ts:42`) |

<details>
<summary>Details</summary>

**<Suggestion title>**

What could be better, why, and a concrete suggestion.

```diff
- current approach
+ suggested approach
```

</details>

---

## Action Items

The 3-10 most important things to address, distilled from all sections above.
Order by importance. Every item should be actionable — something the author
can act on in the next revision.

| # | Type | Item |
|---|------|------|
| 1 | 🔒 Security | Brief actionable description |
| 2 | 🐛 Bug | Brief actionable description |
| 3 | 🧪 Test | Brief actionable description |
| 4 | 🎨 Style | Brief actionable description |
| 5 | 💡 Nit | Brief actionable description |

_Type labels: 🔒 Security, 🐛 Bug, 🧪 Test, 🎨 Style, 💡 Nit, 📐 Architecture, 📝 Docs_

````

### Severity/Priority Levels

Use these consistently across all sections:

| Emoji | Level | Meaning |
|-------|-------|---------|
| `🔴` | Critical | Blocks merge — security hole, data loss, broken functionality |
| `🟠` | High | Should fix before merge — actual correctness risk or security concern |
| `🟡` | Medium | Worth mentioning — no current threat but could become one |
| `🟢` | Low | Nitpick — optional improvement, stylistic preference |

---

## Guardrails

- **Every section is mandatory.** If there are no findings, write "No issues found."
- **Be specific.** Reference file paths with line numbers (`file.ts:42`), function names, and existing patterns.
- **Be balanced.** Always include strengths. A review with only criticisms is incomplete.
- **Link context.** Every reference to a Linear issue, Notion doc, or Slack thread must be a clickable link.
- **Stay read-only.** Do not modify anything. Gather, analyze, report.
