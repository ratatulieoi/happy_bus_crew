# Happy Bus online prototype

This directory contains a Django 5.2.17 and SQLite backend with a plain browser UI for crew reports, private receipt images, fixed bus slots, oil maintenance, and administrator-managed crew accounts. It does not migrate the Flutter app's local SQLite data.

## Set up the backend

Use Python 3.13. Run these commands from `backend/`:

```sh
python3.13 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Set a throwaway development secret for each command that loads Django. The project creates the ignored `runtime/` database and media parents on startup. Set `HAPPYBUS_DB` and `HAPPYBUS_MEDIA_ROOT` to absolute paths when you need disposable runtime data elsewhere.

```sh
DJANGO_SECRET_KEY='replace-with-a-development-only-secret' .venv/bin/python manage.py migrate --noinput
DJANGO_SECRET_KEY='replace-with-a-development-only-secret' HAPPYBUS_ADMIN_PASSWORD='at-least-10-characters' .venv/bin/python manage.py bootstrap_admin --username admin
DJANGO_SECRET_KEY='replace-with-a-development-only-secret' .venv/bin/python manage.py runserver 127.0.0.1:8000
```

There is no default password. The bootstrap command is idempotent. It creates missing bus slots and preserves an existing administrator password, bus edit, report, and oil data. New passwords must contain at least 10 characters.

## API reference

All API paths use a trailing slash except the CSV path. JSON errors have the shape `{ "error": "..." }`. Mutations require a Django session and the `X-CSRFToken` header. Login also requires CSRF.

| Route | Purpose |
| --- | --- |
| `GET /api/session/` | Read the current user and obtain a CSRF token. |
| `POST /api/login/`, `POST /api/logout/` | Start or end a session. |
| `GET, POST /api/users/`, `PATCH /api/users/<id>/` | Admin-only crew account listing, creation, and activation changes. |
| `GET /api/buses/`, `PATCH /api/buses/<id>/` | Read buses for authenticated users or edit bus identity as an admin. |
| `POST /api/buses/<id>/oil-change/` | Record an admin oil change. |
| `GET, POST /api/reports/` | List accessible reports or create a draft report. Supports `bus_id`, `status`, and `deficit=1` filters. |
| `GET, PATCH, DELETE /api/reports/<id>/` | Read, edit, or delete a draft report. |
| `POST /api/reports/<id>/submit/`, `POST /api/reports/<id>/reopen/` | Submit a draft or let an admin reopen a submitted report. |
| `POST /api/reports/<id>/receipts/` | Upload a PNG or JPEG receipt up to 2 MiB. |
| `GET, DELETE /api/receipts/<id>/` | Download or delete an authorized receipt. |
| `GET /api/reports/export.csv` | Admin-only CSV export using the same `bus_id`, `status`, and `deficit` filters. |

Successful creates return 201. Successful deletes return 204. Receipt downloads use authenticated image responses and are not public media URLs. Reports are newest first, preserve their bus plate snapshot, and calculate expense totals, balance, and distance on the server. A crew report with positive BBM requires a receipt before submission. Admins can reopen submitted reports.

## Run checks

```sh
DJANGO_SECRET_KEY='test-only' .venv/bin/python manage.py check
DJANGO_SECRET_KEY='test-only' .venv/bin/python manage.py makemigrations --check --dry-run
DJANGO_SECRET_KEY='test-only' .venv/bin/python manage.py test
```

## Local-only limits

This prototype has no public signup, cloud provider, offline sync, pagination, PDF renderer, CORS support, or public media route. It does not claim production HTTPS, secure cookies, deployment settings, backups, monitoring, or secret management. Run the development server on loopback only. Use a production database, storage, secret manager, and HTTPS settings before deployment.
