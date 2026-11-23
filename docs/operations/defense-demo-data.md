# Defense Demo Data

`python manage.py seed_defense_demo` fills a GawaGo database with demo people of Tayabas City and jobs in every state, so the live system looks lived-in during the capstone defense.

## What it creates

- **Households (6):** Liza Mendoza, Ramon Villanueva, Grace Bautista and Fernando Cruz are verified. Teresa Ramos waits in the Verification Queue. Paolo Garcia has sent nothing.
- **Workers (10):** Maria Santos, Jose Dela Rosa, Ana Villareal, Mark Aquino, Rosa Lim, Carlo Navarro and Rico Salazar are verified. Joy Fernandez waits in the queue, Ben Torres was rejected and Lea Morales has sent nothing. Rico has a certificate waiting in Worker Credentials.
- **Jobs (15)** in every state:
  - open, with applicants;
  - a hire request waiting on the worker;
  - hired but not started yet;
  - in progress;
  - past its last day and waiting to be marked done;
  - completed and rated both ways;
  - completed with only the automatic 3.5;
  - cancelled.

  Dates count from the day it runs.
- **Three complaints** (Submitted, Under Review, Resolved), two chat threads, a few notifications, and sample ID, clearance and certificate images marked "DEMO DOCUMENT".

Fernando Cruz can't post a new job (his laundry job waits to be marked done), which shows the posting rule. Mark Aquino, Ana Villareal and Jose Dela Rosa each get an AI job match.

Usernames are the names above in lowercase with a dot (`liza.mendoza`, `maria.santos`). Every demo account has the same password. Their emails are `gawago10+demo.<username>@gmail.com`, so any email the live site sends them lands in the project inbox.

## Running it

The password is never stored in the repository. It comes from `DEMO_PASSWORD` (or `--password`), at least 8 characters.

```
DEMO_PASSWORD=... python manage.py seed_defense_demo           # create or refresh
DEMO_PASSWORD=... python manage.py seed_defense_demo --reset   # delete every demo account, then rebuild
```

The command can run again safely: accounts are matched by username and jobs by title, and old document images are deleted before new ones are stored. It touches only demo accounts (emails starting `gawago10+demo.`), never the superadmin or real users.

## On Render (no console on the free plan)

`scripts/render_start.sh` runs the command at start-up when the API service has `SEED_DEFENSE_DEMO=True`. Optional arguments go in `SEED_DEFENSE_DEMO_ARGS` (for example `--reset`).

1. On `gawago-api`, set `DEMO_PASSWORD` and `SEED_DEFENSE_DEMO=True`, then deploy.
2. When the deploy is live, delete `SEED_DEFENSE_DEMO`. A later restart then won't seed again (doing so would put changed demo jobs back to their starting state).

A failed seed is logged (`render_start: demo seed failed`) and the site still starts.

After a new database is created (the free one lasts 30 days), run these steps again, and recreate the superadmin.
