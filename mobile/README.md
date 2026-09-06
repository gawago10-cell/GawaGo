# GawaGo Mobile

Flutter mobile client for the GawaGo Employment Platform.

## Status

The Flutter project is generated and its authentication foundation is connected
to the Django backend. Login sessions use secure storage, authenticated API
requests send the JWT bearer token, and valid sessions are restored on launch.

Run against the Android emulator with:

```powershell
flutter run
```

For a physical device, point the app at the computer running Django:

```powershell
flutter run --dart-define=GAWAGO_API_BASE_URL=http://YOUR_PC_IP:8000/api
```

For the shared web/mobile API URL strategy and automatic ngrok APK builds, see
`docs/setup/api-configuration.md` from the repository root.

## Suggested App Flow

Start with the worker-side MVP:

- Login and registration
- Worker dashboard
- Find jobs
- Job details
- Notifications
- My applications
- Worker profile

Then continue with the household-side flow:

- Household dashboard
- Post a job
- My jobs
- Smart matched workers
- Hire request flow
- Completion and review
