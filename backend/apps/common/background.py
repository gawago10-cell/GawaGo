"""Run work outside the request/response cycle.

    enqueue(task, *args)

`task` must be a module-level function and `args` plain, picklable values
(ids, strings) -- never model instances or request objects, since the task
may run in another process minutes later.

The backend is chosen by settings.BACKGROUND_TASK_BACKEND:

- "django_q": Django-Q2 using the Django ORM as broker (the existing
  database; no Redis). Needs a `python manage.py qcluster` process running.
- "thread":   a daemon thread in the current process. No extra process, but
  work is lost if the process restarts before it finishes.
- "sync":     run inline, immediately. Tests and debugging only.

Callers that depend on committed data should schedule this with
transaction.on_commit(), so the task never runs for a rolled-back write.
"""

import logging
import threading

from django.conf import settings
from django.db import close_old_connections

logger = logging.getLogger(__name__)

BACKEND_DJANGO_Q = "django_q"
BACKEND_THREAD = "thread"
BACKEND_SYNC = "sync"
BACKENDS = {BACKEND_DJANGO_Q, BACKEND_THREAD, BACKEND_SYNC}


def task_path(task):
    return f"{task.__module__}.{task.__qualname__}"


def enqueue(task, *args, timeout=None):
    backend = getattr(settings, "BACKGROUND_TASK_BACKEND", BACKEND_DJANGO_Q)
    if backend not in BACKENDS:
        raise ValueError(f"BACKGROUND_TASK_BACKEND must be one of {sorted(BACKENDS)}, got {backend!r}")

    if backend == BACKEND_SYNC:
        return task(*args)

    if backend == BACKEND_THREAD:
        thread = threading.Thread(
            target=_run_in_thread, args=(task, args), name=f"bg-{task.__name__}", daemon=True
        )
        thread.start()
        return thread

    from django_q.tasks import async_task

    options = {"task_name": f"{task.__name__}{list(args)}"}
    if timeout is not None:
        options["timeout"] = timeout
    return async_task(task_path(task), *args, **options)


def _run_in_thread(task, args):
    # A new thread gets its own DB connection; close stale ones on the way in
    # and release ours on the way out so threads never leak connections.
    close_old_connections()
    try:
        task(*args)
    except Exception:
        logger.exception("Background task %s%s failed", task_path(task), args)
    finally:
        close_old_connections()
