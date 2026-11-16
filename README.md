# visa-slot-monitor

A Claude Code setup that watches a US visa scheduling calendar for an earlier
appointment slot, emails and pushes you the moment one appears, walks the
booking flow up to the final confirmation screen — and stops there, because
the last click is yours.

It drives **your own already-logged-in Chrome** through the Claude in Chrome
extension. It does not touch the site's API, does not store your credentials,
and does not solve human-verification challenges.

## What it will and will not do

**Will**
- Check the calendar on a schedule and find every open date earlier than a
  threshold you set.
- Email you and send a push notification *before* it touches anything.
- Select the earliest date and its earliest time slot, advance to the last
  screen before confirmation, and park there with the tab left open.
- Tell you when it is blocked and monitoring has paused.

**Will not**
- Click the final Confirm / Submit / Reschedule button. Never. By design.
- Solve a CAPTCHA or a Cloudflare challenge, or type a password.
- Retry other dates if a slot gets taken out from under it.
- Guarantee you get the slot. See *Honest limitations*.

## Setup

```sh
git clone <this repo>
cd visa-slot-monitor
cp config.example.json config.json   # config.json is gitignored
$EDITOR config.json
./init-state.sh
./render.sh > run-prompt.txt
```

`config.json` holds the applicant name, email and appointment details. It is
gitignored and must stay that way.

Then, in a Claude Code session with the Claude in Chrome extension connected,
ask Claude to schedule the contents of `run-prompt.txt` as a recurring job at
the interval in `interval_cron`.

### config.json fields

| field | meaning |
| --- | --- |
| `site_url` | the scheduling page to open |
| `consular_post` | exact dropdown label, e.g. `CITY (城市)` |
| `applicant_name` | exact name as it appears in the group-members panel |
| `threshold_date` | `YYYY-MM-DD`; only strictly earlier dates count |
| `scan_views` | which two-month calendar views to scan, priority first |
| `notify_email` | where hit and blocked alerts go |
| `interval_cron` | 5-field cron; avoid `:00`/`:30` |
| `stuck_realert_hours` | how often to re-nag while blocked |
| `held_nag_minutes` | remind this long after parking on a slot |
| `held_release_hours` | give up on an unconfirmed slot after this long |
| `state_file` | where run-to-run state lives (outside the repo) |

## State

A JSON file outside the repo, so a hit is never announced twice and a parked
confirmation tab is never disturbed:

- `alerted_dates` — dates already announced
- `holding_tab` — tabId parked on a confirmation page; while set, every run
  exits immediately and leaves it alone
- `held_since` / `held_nag_at` — when the tab was parked and when the user was
  last nagged; after `held_nag_minutes` it pushes a reminder, after
  `held_release_hours` it gives up on the slot and resumes checking
- `stuck_since` — when the monitor first got blocked, drives re-alerts
- `last_seen_available` — last full read of the calendar

## Honest limitations

Read these before relying on it.

1. **It dies with the session.** Claude Code cron jobs are in-memory and
   session-scoped. Close the session, quit the app, or let the machine sleep
   and the monitor stops silently. Recurring jobs also auto-expire after seven
   days and must be recreated.
2. **It cannot tell you it died.** If the session is gone, nothing runs — no
   process is left to send you an alert. The blocked-alert in step 3 only
   covers the case where the monitor is alive but the *site* is blocking it.
   Check in on it yourself.
3. **It reads, it does not scrape.** Availability is pulled from the page's own
   already-loaded datepicker in your logged-in session — one JavaScript call per
   run, no screenshots, no month-by-month paging. It never extracts cookies,
   replays a `cf_clearance` token, or calls the site's endpoints from a script.
   Going around the bot protection is what gets an applicant account banned, and
   it would not even help here: the calendar makes no network call, so you have
   to load the page either way.
4. **Polling loses races.** Slots that are released and taken within seconds
   will not be caught by any polling interval you can safely use. What this
   catches is slots that sit unclaimed for minutes — cancellations, batch
   releases.
5. **It does not secure the slot.** Selecting a date and time does not submit
   anything, and almost certainly places no server-side hold — parking saves you
   the clicks, not the slot. It can be gone by the time you click Submit. If you
   do not confirm, the monitor nags once and then releases the slot and resumes
   checking, so a stale park never blinds it.
6. **Polling faster raises your risk.** More frequent checks mean more
   Cloudflare challenges and more chance the site flags the account. The
   monitor stops and asks for help rather than pushing through.

## Privacy

`config.json` and the state file are gitignored and live outside the repo.
Nothing in this repository contains a real name, email address, application
number, or appointment date. Keep it that way if you fork it.
