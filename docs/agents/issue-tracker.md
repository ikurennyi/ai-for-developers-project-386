# Issue tracker: GitHub

Issues and specs live in GitHub Issues. Use the gh CLI.

## Repository

The configured repository is ikurennyi/ai-for-developers-project-386.
Before the first issue creation in a session, verify the target with
`gh repo view --json nameWithOwner`. If it differs, confirm with the user.

## Operations

- Create: `gh issue create --title "..." --body-file <file>`.
- Read: `gh issue view <number> --json number,title,body,labels,comments`.
- List: `gh issue list --state open --json number,title,body,labels,comments`.
  Apply label and state filters as needed.
- Comment: `gh issue comment <number> --body-file <file>`.
- Labels: `gh issue edit <number> --add-label "..." --remove-label "..."`.
- Close: post an explanation with `gh issue comment`, then `gh issue close`.
  Post the comment separately even when the issue is already closed.

Use GitHub native sub-issues and dependencies when available:
- Sub-issue: `gh issue create --parent <parent> ...` or
  `gh issue edit <parent> --add-sub-issue <child>` (gh 2.94+).
- Blocker: `gh issue edit <child> --add-blocked-by <blocker>` (gh 2.94+).
- Older gh: use the GitHub REST API with issue database IDs.
- Where unavailable, add `Part of #<parent>` and `Blocked by: #<number>`
  to the child body and link children in the parent task list.
- A ticket is startable only when all blockers are closed.
  `gh api repos/ikurennyi/ai-for-developers-project-386/issues/<number> --jq .issue_dependencies_summary.blocked_by`
  counts open native blockers; also check textual fallbacks.

When a skill says to publish, create an issue here.
When it says to fetch a ticket, read the corresponding issue.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding operations

- Map: one issue labelled `wayfinder:map`, with Notes, Decisions-so-far, and Fog.
- Children: sub-issues labelled `wayfinder:<type>`, where type is research,
  prototype, grilling, or task. Use the parent task list as a fallback.
- Frontier: open children without open blockers or assignees, in map order.
- Claim: `gh issue edit <number> --add-assignee @me`, before other writes.
- Resolve: comment with the answer, close the child, then append a summary
  and link to the map's Decisions-so-far.
