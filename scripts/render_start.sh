#!/usr/bin/env bash
# Render start command for plans without a separate Background Worker:
# runs the Django-Q2 worker (qcluster) and gunicorn in the same service.
#
#   Start Command:  bash scripts/render_start.sh
#
# If either process exits, the other is stopped and the script exits with the
# failing process's status, so Render restarts the whole service instead of
# silently serving requests with no worker (or a worker with no web server).
set -euo pipefail

cd "$(dirname "$0")/../backend"

python manage.py collectstatic --noinput
python manage.py migrate --noinput

python manage.py qcluster &
QCLUSTER_PID=$!

gunicorn config.wsgi:application \
    --bind "0.0.0.0:${PORT:-8000}" \
    --workers "${WEB_CONCURRENCY:-2}" \
    --timeout 60 &
GUNICORN_PID=$!

shutdown() {
    kill -TERM "$QCLUSTER_PID" "$GUNICORN_PID" 2>/dev/null || true
    wait || true
}
trap 'shutdown; exit 0' TERM INT

set +e
wait -n
status=$?
set -e
echo "render_start: a process exited (status ${status}); stopping the other" >&2
shutdown
exit "$status"
