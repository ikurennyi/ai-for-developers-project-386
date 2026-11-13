# Guest navigation and privacy (#29)

Calendar/form URLs contain only the selected civil date and start instant. On
navigation and refresh, the existing generated SDK reloads availability from
Rails. A stale interval returns to selection with an explanation, retaining a
valid date; unavailable meeting types offer the meeting-type list.

Guest drafts are scoped by meeting-type address in the current tab's session
history (`history.state`). Synchronous input updates preserve them through Back,
Forward and refresh. Vue Router's own history state is preserved. Neither URLs,
localStorage nor sessionStorage contain guest details. In particular, using only
sessionStorage for personal data would be unsafe: `window.open` with an opener
clones it into the new tab.

After confirmation, the creation response is saved in that tab's history and the
form is replaced with `/confirmation/<random-token>`. The token only matches
a locally held response: it is not a server booking identifier, bearer capability,
or public lookup. Refresh renders that response without any POST or booking GET.
Opening the address in another tab, including one retaining its opener, or a
different browser context shows no details and offers meeting selection.

Success clears all guest drafts. A non-personal sessionStorage generation marker
invalidates older history snapshots so Back/refresh cannot restore cleared input.
No permanent guest storage, shared cookie, or public booking lookup is added.
As with other same-origin state, this is not an isolation boundary against an
actively malicious same-origin script accessing its opener.

The real Playwright application scenario in `frontend/e2e/guest-draft.mjs` runs
inside `mise run smoke` and therefore `mise run check`, with isolated Rails,
PostgreSQL and the production SDK. It covers Back/Forward, refresh, URL contents,
draft clearing, stale calendar/form links, and opener/context privacy. A canary
proves the opener tab really cloned sessionStorage rather than merely testing a
fresh isolated tab. Existing HTTP/OpenAPI checks retain server-side validation,
privacy and absence of public booking-detail GET.

Stable uncertain-result attempt identity remains #30; advanced changed-details
and conflict recovery remains #31. The guest-state module is the tab-local seam
for their later persistence needs. Local checks do not confirm external Actions.
