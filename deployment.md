# GawaGo Deployment Plan

Target: a **$0/month** public deployment that stays awake during the capstone
defense. Every service below is on a permanent free tier, not a trial.

---

## 1. What actually gets deployed

GawaGo is not one app. Five things have to go live:

| # | Part | Source | Nature |
|---|------|--------|--------|
| 1 | Django REST API | `backend/` | Long-running Python process. Needs Postgres, outbound HTTPS (OpenRouteService / OSRM), and Gmail SMTP. |
| 2 | PostgreSQL | — | Persistent database. |
| 3 | Uploaded media | `media/` | **18 MB and growing.** Profile photos, job photos, portfolio work samples, certificates, government IDs, complaint evidence. Must survive restarts. |
| 4 | React web app | `frontend/` | Static files after `npm run build`. |
| 5 | Flutter app | `mobile/` | Static files after `flutter build web`, plus a signed Android APK. |

---

## 2. The chosen stack

| Part | Service | Why | Cost |
|------|---------|-----|------|
| API + Postgres + media | **Oracle Cloud Always Free** — one Ampere ARM VM (Ubuntu 24.04) | Always on, so no cold start in front of the panel. Real persistent disk, so uploaded IDs survive reboots and no object storage is needed. | $0 forever |
| React web app | **Cloudflare Pages** | Free, unlimited bandwidth, automatic HTTPS, builds from git. | $0 |
| Flutter web | **Cloudflare Pages** (second project) | Same. | $0 |
| Android APK | Signed release APK, linked from the web app or **Firebase App Distribution** | Play Store costs $25 and takes weeks of review — not worth it before the defense. | $0 |

**Why not the obvious managed route.** Render/Railway free web services sleep
after ~15 minutes idle and take roughly a minute to wake. The
`recommended-workers` endpoint already takes about **10 seconds on a job's
first call**, so a sleeping tier would make the panel wait ~10 s *on top of*
a ~60 s wake-up. A single always-on VM removes that risk entirely. See
§9 for the managed fallback if the VM route stalls.

> Verify the current free-tier limits when you sign up — these providers
> change them regularly, and the figures here were not checked against the
> providers' live pricing pages.

**Two known Oracle signup frictions.** It asks for a credit card for identity
verification (it is not charged on Always Free), and Ampere ARM capacity is
sometimes unavailable in a given region — retry, or pick a different home
region at signup. Do not fall back to Oracle's always-free *AMD* shape: at
1 GB RAM it cannot comfortably hold Django, Postgres and scikit-learn
together.

---

## 3. Code changes required before any deploy

Three gaps make the current `backend/` undeployable as-is. All three are
small.

### 3.1 Add a WSGI server and static handling

`backend/requirements.txt` has no production server. Add:

```
gunicorn>=22.0
whitenoise>=6.7
```

`gunicorn` runs the app; `whitenoise` is only needed if you later move to a
managed host (§9), but it is harmless to install now.

### 3.2 Add `STATIC_ROOT`

`backend/config/settings/base.py` defines `STATIC_URL` but **no
`STATIC_ROOT`**, so `collectstatic` cannot run and Django admin / the DRF
browsable API will load unstyled under `DEBUG=False`. Add next to the other
static settings:

```python
STATIC_ROOT = BASE_DIR / "staticfiles"
```

Then add it to `.gitignore` — `media/` and `.env` are already ignored, but
`staticfiles/` is not, and `collectstatic` output should never be committed:

```
backend/staticfiles/
```

### 3.3 Media is not served when `DEBUG=False` — by design

`backend/config/urls.py` only wires `MEDIA_URL` under `if settings.DEBUG`.
That is correct: in production **nginx serves media, not Django**. No code
change needed, but §5.6 must be configured or every photo 404s.

---

## 4. Accounts and tools to have ready

- Oracle Cloud account (Always Free tier)
- Cloudflare account
- A GitHub repo for this project (Cloudflare Pages builds from it)
- A Gmail account with a 16-character **App Password** for SMTP
- A fresh **OpenRouteService** API key — the key currently on the dev machine
  has exceeded its quota, which silently disables distance features
- Optional: a domain name. All services give free HTTPS subdomains if you
  skip this.

---

## 5. Part A — the API server (Oracle VM)

### 5.1 Provision

1. Create an **Always Free** compute instance: shape `VM.Standard.A1.Flex`,
   Ubuntu 24.04, 2 OCPU / 12 GB RAM (within the free allowance).
2. Save the SSH private key.
3. In the instance's VCN security list, open **ingress on TCP 80 and 443**
   from `0.0.0.0/0`.
4. On the VM itself, Oracle's Ubuntu images ship restrictive iptables rules:

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

### 5.2 System packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-venv python3-dev build-essential \
    libpq-dev postgresql postgresql-contrib nginx git certbot \
    python3-certbot-nginx
```

`build-essential` and `python3-dev` matter: scikit-learn/numpy may need to
compile on ARM.

### 5.3 PostgreSQL

```bash
sudo -u postgres psql <<'SQL'
CREATE DATABASE gawago;
CREATE USER gawago_user WITH PASSWORD 'use-a-real-password-here';
ALTER ROLE gawago_user SET client_encoding TO 'utf8';
ALTER ROLE gawago_user SET default_transaction_isolation TO 'read committed';
ALTER ROLE gawago_user SET timezone TO 'Asia/Manila';
GRANT ALL PRIVILEGES ON DATABASE gawago TO gawago_user;
SQL
```

On Postgres 15+ also grant schema rights:

```bash
sudo -u postgres psql -d gawago -c \
  "GRANT ALL ON SCHEMA public TO gawago_user;"
```

### 5.4 Application code

```bash
sudo mkdir -p /srv/gawago && sudo chown $USER:$USER /srv/gawago
git clone <your-repo-url> /srv/gawago
cd /srv/gawago/backend
python3 -m venv /srv/gawago/venv
/srv/gawago/venv/bin/pip install -U pip
/srv/gawago/venv/bin/pip install -r requirements.txt
```

Write `/srv/gawago/backend/.env` using the reference in §7, then:

```bash
export DJANGO_SETTINGS_MODULE=config.settings.production
/srv/gawago/venv/bin/python manage.py migrate
/srv/gawago/venv/bin/python manage.py collectstatic --noinput
/srv/gawago/venv/bin/python manage.py createsuperuser
```

Copy the existing dev uploads up if you want the demo data:

```bash
# from your Windows machine
scp -r C:/GawaGo/media/* ubuntu@<vm-ip>:/srv/gawago/media/
```

### 5.5 gunicorn under systemd

`/etc/systemd/system/gawago.service`:

```ini
[Unit]
Description=GawaGo Django API
After=network.target postgresql.service

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=/srv/gawago/backend
Environment="DJANGO_SETTINGS_MODULE=config.settings.production"
EnvironmentFile=/srv/gawago/backend/.env
ExecStart=/srv/gawago/venv/bin/gunicorn \
    --workers 3 \
    --timeout 60 \
    --bind 127.0.0.1:8000 \
    config.wsgi:application
Restart=always

[Install]
WantedBy=multi-user.target
```

`--timeout 60` is deliberate: the first `recommended-workers` call for a job
takes about 10 s, and gunicorn's 30 s default is uncomfortably close to the
outbound routing calls stacking up.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now gawago
sudo systemctl status gawago
```

### 5.6 nginx — including one rule that matters for privacy

`/etc/nginx/sites-available/gawago`:

```nginx
server {
    listen 80;
    server_name api.yourdomain.com;   # or the VM's public IP

    client_max_body_size 20M;         # job photos and ID uploads

    location /static/ {
        alias /srv/gawago/backend/staticfiles/;
    }

    # Government IDs live under media/verification_documents/. The app
    # deliberately serves those through an authenticated API route
    # (/api/common/verification-requests/<id>/documents/<type>/), so nginx
    # must NOT hand them out by path -- otherwise anyone who guesses
    # /media/verification_documents/7/id.jpg downloads a worker's ID and
    # bypasses the auth check entirely.
    location /media/verification_documents/ {
        deny all;
        return 404;
    }

    location /media/ {
        alias /srv/gawago/media/;
    }

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

`production.py` already sets
`SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")`, which is
exactly what the `X-Forwarded-Proto` header above feeds. No change needed.

```bash
sudo ln -s /etc/nginx/sites-available/gawago /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 5.7 HTTPS

```bash
sudo certbot --nginx -d api.yourdomain.com
```

Certbot installs its own renewal timer. **If you have no domain**, you cannot
get a Let's Encrypt certificate for a bare IP — either register a cheap
domain, use a free DNS name, or put Cloudflare in front. HTTPS is not
optional here: `production.py` sets `SECURE_SSL_REDIRECT=True` and the
browser will block mixed content from an HTTPS frontend to an HTTP API.

---

## 6. Parts B–D — the clients

### 6.1 React web app (Cloudflare Pages)

Create a Pages project from the repo:

- **Root directory:** `frontend`
- **Build command:** `npm run build`
- **Output directory:** `dist`
- **Environment variable:** `VITE_API_URL = https://api.yourdomain.com/api`

`frontend/src/api/apiClient.js` already reads `VITE_API_URL`, so no code
change is needed. Add a SPA fallback so deep links work — `frontend/public/_redirects`:

```
/*    /index.html   200
```

### 6.2 Flutter web (Cloudflare Pages, second project)

Cloudflare's build image has no Flutter SDK, so build locally and deploy the
output directly:

```bash
cd mobile
flutter build web --release \
  --dart-define=GAWAGO_API_BASE_URL=https://api.yourdomain.com/api
npx wrangler pages deploy build/web --project-name gawago-mobile
```

`mobile/lib/src/core/config/api_config.dart` reads `GAWAGO_API_BASE_URL` at
build time and also keeps a runtime override in secure storage, so the same
build can be repointed without recompiling.

### 6.3 Android APK

```bash
cd mobile
flutter build apk --release \
  --dart-define=GAWAGO_API_BASE_URL=https://api.yourdomain.com/api
```

Output: `mobile/build/app/outputs/flutter-apk/app-release.apk`.

For anything installed on a panelist's phone, sign it with a real keystore
rather than shipping the debug key — see Flutter's "Build and release an
Android app" guide. Distribute via Firebase App Distribution or a download
link on the web app.

### 6.4 Wire the origins back to the API

After the Pages URLs exist, set these in `/srv/gawago/backend/.env` and
restart (`sudo systemctl restart gawago`):

```
DJANGO_ALLOWED_HOSTS=api.yourdomain.com
CORS_ALLOWED_ORIGINS=https://gawago-web.pages.dev,https://gawago-mobile.pages.dev
CSRF_TRUSTED_ORIGINS=https://gawago-web.pages.dev,https://gawago-mobile.pages.dev
```

A missing origin here is the most common cause of a deploy that looks broken:
requests fail CORS and the UI shows empty data with no obvious error.

---

## 7. Environment variable reference (`backend/.env`)

Derived from `backend/.env.example`, with production values.

```ini
# Core
DJANGO_SECRET_KEY=<50+ random chars, never the repo default>
DJANGO_DEBUG=False
DJANGO_ALLOWED_HOSTS=api.yourdomain.com

# Database
DJANGO_USE_SQLITE_FOR_DEV=False
DJANGO_DB_ENGINE=postgresql
DB_NAME=gawago
DB_USER=gawago_user
DB_PASSWORD=<the password from 5.3>
DB_HOST=127.0.0.1
DB_PORT=5432

# Origins (fill in after 6.1/6.2)
CORS_ALLOWED_ORIGINS=https://gawago-web.pages.dev
CORS_ALLOW_CREDENTIALS=True
CSRF_TRUSTED_ORIGINS=https://gawago-web.pages.dev

# Security
DJANGO_SECURE_SSL_REDIRECT=True
DJANGO_SECURE_HSTS_SECONDS=31536000
DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS=True
DJANGO_SECURE_HSTS_PRELOAD=True

# Email / password reset
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=<your gmail>
EMAIL_HOST_PASSWORD=<16-char app password>
DEFAULT_FROM_EMAIL=<your gmail>
PASSWORD_RESET_TOKEN_TTL_MINUTES=10

# Road-route distance
OPENROUTESERVICE_API_KEY=<a fresh key>
OPENROUTESERVICE_DIRECTIONS_URL=https://api.openrouteservice.org/v2/directions/driving-car/geojson
OPENROUTESERVICE_TIMEOUT_SECONDS=4
OSRM_DIRECTIONS_URL=https://router.project-osrm.org/route/v1/driving
```

`base.py` refuses to boot with `DEBUG=False` while `DJANGO_SECRET_KEY` is
still the repo default, and `production.py` raises if `DJANGO_ALLOWED_HOSTS`
is empty. Both are intentional — a failed boot here means the env file is
wrong, not that the code is broken.

Keep `.env` out of git and `chmod 600` it.

---

## 8. Post-deploy smoke test

Run these against the live URLs, not localhost.

- [ ] `curl -I https://api.yourdomain.com/api/accounts/me/` → `401`, and the response is over HTTPS
- [ ] Django admin at `/admin/` loads **with styling** (proves `collectstatic` + §3.2 worked)
- [ ] Register a household and a worker from the deployed web app
- [ ] Post a job, then open **Smart Matching** — expect ~10 s on the first call, then fast
- [ ] Apply as the worker, hire from the household side, complete, and leave a review
- [ ] Upload a profile photo and confirm it renders after a **hard refresh** (proves nginx `/media/`)
- [ ] Submit a verification request, approve it in the admin queue, and open the ID document — it must load through the app
- [ ] Confirm `https://api.yourdomain.com/media/verification_documents/1/` returns **404**, not a file (§5.6)
- [ ] Trigger a password reset and confirm the email arrives
- [ ] Install the APK on a real phone and log in
- [ ] `sudo reboot` the VM, wait, then confirm the API and uploaded photos both come back (proves systemd `enable` + persistent disk)

---

## 9. Fallback: all-managed free tier

If the Oracle VM stalls on capacity or the ops work is too much, this route
is far less setup but the API sleeps.

| Part | Service |
|------|---------|
| API | Render free Web Service (`gunicorn config.wsgi:application`) |
| Postgres | **Neon** free — *not* Render's free database, which expires |
| Media | **Cloudflare R2** free + `django-storages[s3]` and `boto3` |
| Clients | Cloudflare Pages, same as §6 |

Two extra pieces of work this route forces:

1. **Media must move to object storage.** Render's filesystem is ephemeral,
   so `MEDIA_ROOT` on disk means every redeploy destroys uploaded IDs and
   certificates. Configure `STORAGES["default"]` for S3/R2. This also means
   re-checking that verification documents stay private — R2 buckets must not
   be public, and the authenticated document route must fetch through the
   storage backend.
2. **Mitigate the sleep.** Ping `/api/...` every ~10 minutes from a free cron
   (cron-job.org, or a GitHub Actions schedule) so the service is warm when
   the panel arrives. Render's free allowance is roughly one always-on
   service, so this fits — but it is a workaround, not a guarantee.

Add `whitenoise` to `MIDDLEWARE` directly after `SecurityMiddleware` on this
route, since there is no nginx to serve `/static/`.

---

## 10. Known issues to watch

- **OpenRouteService quota.** The key on the dev machine is already over
  quota. When it fails the code falls back to public OSRM, which is
  rate-limited and unreliable under load. Get a fresh key before the defense.
- **First-call latency.** `recommended-workers` takes ~10 s the first time a
  job is scored, then caches. Job-match notifications are also computed
  synchronously on `JobPosting` save, so posting a job is slower as the
  worker pool grows. Both are flagged in the code for a move to Celery;
  neither blocks the demo.
- **Complaint evidence is publicly addressable.** Unlike verification IDs,
  complaint photos are served straight off `MEDIA_URL` with no
  authenticated route, so `/media/complaint_evidence/<id>/<file>` is
  guessable. That is the current design and §5.6 leaves it served on
  purpose — blocking it would break admin report review. Worth raising as
  known future work rather than fixing during deployment.
- **No database backups.** Add a nightly `pg_dump` to cron and copy it off
  the VM. A capstone demo losing its data the night before is avoidable.
- **`connect-src *` in the SPA's CSP.** `frontend/index.html` allows any
  origin for fetches, which is why the cross-origin API works without a CSP
  change. Tightening it to the API origin would be a small hardening win.
