# Monitor run prompt (template)

Substitute every `{{TOKEN}}` from `config.json` before scheduling this as a
recurring prompt. `render.sh` does the substitution for you.

---

{{CONSULAR_POST}} visa appointment monitor. Follow these steps exactly. Do not
improvise, do not widen the scope. Stay quiet: when there is no hit, output one
or two lines, not a report.

State file: `{{STATE_FILE}}` (read it with `cat` first, write it back with a
heredoc before you finish).
Threshold: `{{THRESHOLD_DATE}}` — only a date STRICTLY EARLIER than this counts
as a hit.
Notify: `{{NOTIFY_EMAIL}}`.

## 1. Held tab check

If `state.holding_tab` is not null, call `tabs_context_mcp` and check whether
that tabId still exists.

- **Gone** (user closed it): set `holding_tab`, `held_slot`, `held_since` and
  `held_nag_at` to null and continue to step 2.
- **Still there**: the tab is parked on a confirmation page the user has not
  clicked yet. Do not touch the tab, do not reload it, do not click anything in
  it. Decide by how long it has been parked, using `state.held_since`:

  - **under {{HELD_NAG_MINUTES}} minutes**: send nothing, end.
  - **at or past {{HELD_NAG_MINUTES}} minutes, and `held_nag_at` is null or
    older than {{HELD_NAG_MINUTES}} minutes**: send ONE PushNotification —
    `"<slot> still waiting for your confirm — slot may be gone"` — set
    `held_nag_at` to now, write state back, end. Do not email; the hit email
    already went out.
  - **at or past {{HELD_RELEASE_HOURS}} hours**: give up on this slot. The user
    did not click and it is almost certainly taken. Clear `holding_tab`,
    `held_slot`, `held_since` and `held_nag_at`, and REMOVE that date from
    `alerted_dates` so a future opening on it can alert again. Send one
    PushNotification — `"released <slot>, monitoring resumed"` — then continue
    to step 2 and run a normal check this same run.

  Parking must never blind the monitor indefinitely: a slot the user never
  confirmed is worth less than catching the date they actually want.

## 2. Open the page once

Call `tabs_context_mcp`. Reuse an existing tab on the scheduling domain and
navigate it to `{{SITE_URL}}`; otherwise `tabs_create_mcp` then navigate.
Load the page ONCE per run. Never reload in a loop.

## 3. Health probe

Wait 10 seconds, then run ONE cheap `javascript_tool` probe — do not take a
screenshot, it costs far more than it tells you. The probe must be null-safe:
`document.body` can still be null mid-load.

```js
(() => {
  const t = document.title || '';
  const b = document.body ? document.body.innerText.slice(0, 600) : '';
  return JSON.stringify({
    title: t,
    blocked: /you have been blocked|attention required/i.test(t + ' ' + b),
    challenge: /just a moment|verify you are human|security verification/i.test(t + ' ' + b),
    login: /sign in|log in|登录|security question/i.test(b),
    hasCalendarUI: !!document.querySelector('#datepicker'),
    hasPostSelect: !!document.querySelector('select')
  });
})()
```

Three outcomes, in this order. They are NOT the same thing and must not be
handled the same way.

### 3a. `blocked` is true — Cloudflare WAF ban

The request is being refused at the edge. **The user cannot fix this by
clicking anything** — it is an IP/fingerprint ban that expires on its own. So
do not tell them to go clear it, do not open another tab, do not switch
networks, and do not retry inside this run. One probe per run IS the backoff.

- `state.blocked_since` is null (first detection): set it and
  `block_last_alert` to now. Send ONE Gmail to `{{NOTIFY_EMAIL}}`, subject
  "[Visa monitor] Blocked by Cloudflare — will retry on its own", plus ONE
  PushNotification. Say: access is blocked, the monitor keeps probing once an
  hour and resumes by itself when the ban lifts, nothing is needed from them,
  and they should NOT sit refreshing the site because that extends the ban.
- Otherwise, if `now - state.block_last_alert >= {{BLOCK_REALERT_HOURS}}`
  hours: send ONE PushNotification saying how many hours it has been blocked
  and that probing continues. Set `block_last_alert` to now. No email.
- Otherwise: send nothing.

Then increment `block_checks`, write the state file back, and end.

### 3b. `challenge` or `login` is true, or `hasPostSelect` is false — needs a human

This one DOES need her: a human-verification checkbox, a login, or a site
error. Monitoring is paused until she opens Chrome.

- NEVER click the verification checkbox, never try to pass the challenge, never
  type a password. These are hers to do.
- Read `state.stuck_since`. If null, set it to now and treat this as a FIRST
  stuck event.
- Alert if this is a first stuck event, OR if
  `now - state.stuck_since >= {{STUCK_REALERT_HOURS}}` hours (then reset
  `stuck_since` to now so the next reminder is another interval away).
  - Alert = Gmail to `{{NOTIFY_EMAIL}}`, subject
    "[Visa monitor] Needs your click — verification or login", body saying
    which of the three it is, when it first got stuck, and that monitoring is
    PAUSED until she opens Chrome and clears it. Plus a PushNotification.
- Otherwise send nothing.
- Write the state file back and end. Take a screenshot ONLY if you genuinely
  cannot tell which of the three it is — never on the happy path.

### 3c. Healthy

If `state.blocked_since` was not null, the ban has just lifted: send ONE
PushNotification — `"access restored, monitoring resumed"` — and clear
`blocked_since`, `block_checks` and `block_last_alert`. Then set
`state.stuck_since` to null and continue to step 4 in this same run.

## 4. Select applicant and post

Use `find` / `read_page` to locate the applicant label for
`{{APPLICANT_NAME}}` in the group-members panel and click it. Then
`form_input` the consular-post dropdown to `{{CONSULAR_POST}}`. Wait 5 seconds.
The calendar does not render until both are set.

## 5. Read availability in ONE call

The calendar is a jQuery UI datepicker whose `beforeShowDay` callback decides
whether each day is selectable, and the whole availability set is already in the
page after step 4 — changing months fires no network request. So do NOT page
through months, screenshot, or read the accessibility tree. Ask the page once
with `javascript_tool`:

```js
(() => {
  const $ = window.jQuery;
  const inst = $.data(document.getElementById('datepicker'), 'datepicker');
  const fn = inst && inst.settings && inst.settings.beforeShowDay;
  if (typeof fn !== 'function') return 'FALLBACK';
  const open = [];
  const d = new Date({{SCAN_FROM}});
  const end = new Date({{SCAN_TO}});
  while (d <= end) {
    let r; try { r = fn.call(inst, new Date(d)); } catch (e) { r = null; }
    if (r && r[0] === true) open.push(
      `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`);
    d.setDate(d.getDate() + 1);
  }
  return JSON.stringify({ openCount: open.length, open });
})()
```

Scan from today through `{{THRESHOLD_DATE}}` inclusive. Note the JS `Date`
month argument is zero-based: January is 0.

This returns every open date in one short result. It reads data the page has
already loaded in the user's own session — it does not forge requests, replay
cookies, or go around the site's bot protection. Never do those things.

If the snippet returns `FALLBACK` or throws, fall back to the slow path for this
run only: set the year and month dropdowns per view, `read_page
filter=interactive`, and treat clickable `link "<day>"` cells as available.
Element refs are invalidated on every month or year change.

## 6. Decide

Collect every available date strictly earlier than `{{THRESHOLD_DATE}}`.
- Empty: update `last_check`, `last_seen_earliest`, `last_seen_available`,
  write state back, end quietly. No notification, no long output.
- Non-empty but the earliest is already in `state.alerted_dates`: do not
  re-alert. Update state, write back, end.
- Non-empty and the earliest is new: go to step 7.

## 7. Hit — notify first, then park

In this order. Notification comes before any clicking.

a. Gmail to `{{NOTIFY_EMAIL}}`, subject
   "[Visa monitor] Earlier slot at {{CONSULAR_POST}}: <earliest date>", body
   listing every available date earlier than the threshold (priority-month
   dates first and flagged) plus `{{SITE_URL}}`. Also send a PushNotification
   like "<post> slot open <date> — open Chrome and confirm".
b. Add the earliest date to `alerted_dates` and write the state file
   immediately, before touching the page.
c. Go back to the page, click that earliest date, pick the earliest time slot
   of that day, and walk forward to the LAST STEP BEFORE final confirmation.
d. DO NOT click the final Confirm / Submit / Reschedule button. That click
   belongs to the user and to nobody else. Stop on the last step, screenshot,
   store the tabId in `state.holding_tab`, write state back. Leave the tab
   open — do not close it, reload it, or navigate away. Also set `held_since`
   to the current ISO timestamp and `held_nag_at` to null, so step 1 can nag and
   later release it.
e. If the slot is taken mid-flow or the page errors: do not retry another date.
   Send a PushNotification saying the slot was taken, leave `holding_tab` null,
   write state back, end.

## 8. Always

Write the state file back before ending, on every path. Never click a final
confirmation button. Never solve a human-verification challenge. Never type a
password.
