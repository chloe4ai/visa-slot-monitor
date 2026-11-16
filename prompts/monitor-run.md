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
- Still there: do nothing, send nothing, end immediately. A previous run is
  already parked on the confirmation page waiting for the user.
- Gone: set `holding_tab` to null and continue.

## 2. Open the page once

Call `tabs_context_mcp`. Reuse an existing tab on the scheduling domain and
navigate it to `{{SITE_URL}}`; otherwise `tabs_create_mcp` then navigate.
Load the page ONCE per run. Never reload in a loop.

## 3. Blocked / stuck detection

Wait 10 seconds, then run ONE cheap `javascript_tool` probe — do not take a
screenshot, it costs far more than it tells you:

```js
JSON.stringify({
  title: document.title,
  challenge: /just a moment|verify you are human|security verification/i
    .test(document.title + ' ' + document.body.innerText.slice(0, 500)),
  login: /sign in|log in|\u767b\u5f55|security question/i
    .test(document.body.innerText.slice(0, 500)),
  hasCalendarUI: !!document.querySelector('#datepicker'),
  hasPostSelect: !!document.querySelector('select')
})
```

You are STUCK if `challenge` or `login` is true, if `hasPostSelect` is false, or
if the probe itself throws or the page never loads. Take a screenshot ONLY when
the probe says stuck and you cannot tell why — never on the happy path.

If stuck:
- NEVER click the verification checkbox, never try to pass the challenge, never
  type a password. These are the user's to do.
- Read `state.stuck_since`. If it is null, set it to the current ISO timestamp
  and treat this as a FIRST stuck event.
- Alert if this is a first stuck event, OR if
  `now - state.stuck_since >= {{STUCK_REALERT_HOURS}} hours` (then reset
  `stuck_since` to now so the next reminder is another interval away).
  - Alert = Gmail to `{{NOTIFY_EMAIL}}`, subject
    "[Visa monitor] Blocked — needs a human", body saying what blocked it
    (Cloudflare / login / error), when it first got stuck, and that monitoring
    is PAUSED until they open Chrome and clear it. Plus a PushNotification.
- Otherwise send nothing.
- Write the state file back and end.

If not stuck: set `state.stuck_since` to null and continue.

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
   open — do not close it, reload it, or navigate away.
e. If the slot is taken mid-flow or the page errors: do not retry another date.
   Send a PushNotification saying the slot was taken, leave `holding_tab` null,
   write state back, end.

## 8. Always

Write the state file back before ending, on every path. Never click a final
confirmation button. Never solve a human-verification challenge. Never type a
password.
