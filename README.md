# RunTrack

A Flutter running-club PWA backed by Supabase Auth, PostgreSQL and server-side Google Health integrations. Training is private by default. There are no production mock repositories, simulated accounts, generated workouts or GPS/map features.

Migrations create exactly one active club, **Tyne Bridge Harriers**, with server-validated code **TBHRTA**, and zero athletes or activity/session data. A protected, verified-email bootstrap lets the designated founding owner register through the public website; the first arbitrary visitor never becomes an administrator.

See [the production release status and first-account guide](docs/production-release.md) for the latest hosted state. Start with [the deployment guide](docs/deployment.md) to reproduce the setup. It covers frontend configuration, fresh projects, Auth/email, PWA hosting and remaining external setup. Read [database/security setup](docs/database.md), [Google Health setup](docs/health.md), and [the implementation and verification report](docs/verification.md) for actual test/configuration status.

```sh
flutter pub get
flutter analyze
flutter test
cp env.example.json env.json
# Set the new project's URL and public publishable key in env.json.
sh scripts/build_web.sh env.json
```

Serve `build/web` over HTTPS. Missing configuration opens a genuine setup screen. Backend secrets belong only in Supabase's protected server configuration; `.env.example` is a backend reference and must never be passed to Flutter.

Local disposable backend and real Auth/RLS tests use Docker and `npx --yes supabase@3.1.0`; see the database guide. Tests never seed the intended live project. The current hosted backend, website and first-account status are recorded in the production release guide. Custom SMTP and Google OAuth approval/live provider sync require their separately documented configuration.
