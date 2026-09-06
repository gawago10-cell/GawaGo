# API Configuration Setup

GawaGo has one Django API that is used by the React web client and the Flutter mobile client. Keep every client pointed at the same backend `/api` base URL.

## Local Django API

From the repository root:

```powershell
cd backend
python manage.py runserver 0.0.0.0:8000
```

Use these base URLs depending on the client:

| Client | API base URL |
| --- | --- |
| React web on the same computer | `http://localhost:8000/api` |
| Android emulator | `http://10.0.2.2:8000/api` |
| Physical phone on the same Wi-Fi | `http://YOUR_PC_LAN_IP:8000/api` |
| Physical phone through ngrok | `https://YOUR-NGROK-DOMAIN.ngrok-free.app/api` |

## React Web

Create `frontend/.env.local`:

```env
VITE_API_URL=http://localhost:8000/api
```

Then run:

```powershell
cd frontend
npm install
npm run dev
```

If the backend is exposed through ngrok, change `VITE_API_URL` to the current ngrok `/api` URL and restart the Vite dev server.

## Flutter Mobile

The mobile app reads `GAWAGO_API_BASE_URL` at build/run time:

```powershell
cd mobile
flutter run --dart-define=GAWAGO_API_BASE_URL=http://10.0.2.2:8000/api
```

For a physical phone on the same Wi-Fi:

```powershell
flutter run --dart-define=GAWAGO_API_BASE_URL=http://YOUR_PC_LAN_IP:8000/api
```

The app also has a runtime Backend API URL field. That is useful for development, but installed release APKs should still be rebuilt when the ngrok domain changes so first launch points at a working backend.

## Build APK From Current Ngrok URL

Start Django, then start ngrok:

```powershell
ngrok http 8000
```

In another terminal from the repository root:

```powershell
.\scripts\build_mobile_ngrok.ps1
```

The script reads `http://127.0.0.1:4040/api/tunnels`, selects the active HTTPS tunnel, appends `/api` if needed, and runs:

```powershell
flutter build apk --dart-define=GAWAGO_API_BASE_URL=<current-ngrok-url>/api
```

To copy the APK to a predictable location:

```powershell
.\scripts\build_mobile_ngrok.ps1 -OutputApkPath .\GawaGo-runtime-server-url.apk
```

When ngrok gives a new URL, rebuild and reinstall the APK. Old APKs keep the old compile-time URL unless the user changes the runtime Backend API URL inside the app.

## Backend Admin Authority

Backend-sensitive actions must be protected in Django views, not only by hiding frontend UI:

| Area | Required backend authority |
| --- | --- |
| Verification queue and review decisions | `IsPlatformAdmin` |
| Analytics dashboard metrics | `IsPlatformAdmin` |
| Superadmin-only account or admin management | `IsPlatformSuperAdmin` |
| User-owned documents and notifications | Owner or `IsPlatformAdmin` |

`IsPlatformAdmin` maps to authenticated Django users with `is_staff=True`. `IsPlatformSuperAdmin` maps to authenticated Django users with both `is_staff=True` and `is_superuser=True`.
