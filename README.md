# Abdulmajeedpharma (APH)

A real pharmaceutical platform, primarily for Android users, with Flutter mobile,
cloud backend, PostgreSQL, and an administrative website.

**Project Owner:** Dr. Abdulmajeed Abdullah Almakhedhi  
**App Short Name:** APH  
**Current Phase:** Phase 01 — Project Foundation and Environment Validation

## Repository Layout

```
abdulmajeedpharma/
├── mobile/          # Flutter Android app (Clean Architecture, Riverpod, GoRouter)
├── backend/         # FastAPI Python backend
├── admin/           # Next.js admin dashboard
├── database/        # PostgreSQL migrations and seeds
├── data-import/     # CSV / Excel / JSON / image import assets
├── ai/              # AI RAG architecture and prompts
├── infrastructure/  # Docker and deployment configs
├── docs/            # Architecture, status, security, roadmap
├── scripts/         # Health checks and tooling
├── .gitignore
├── .env.example
├── README.md
└── LICENSE
```

## Environment Status (Phase 01)

| Tool | Version | Status |
|------|---------|--------|
| Git | 2.39.5 | Installed |
| Python | 3.11.2 | Installed |
| Node.js | 22.22.3 | Installed |
| npm | 10.9.8 | Installed |
| Flutter SDK | — | **Missing** |
| Dart SDK | — | **Missing** |
| Docker | — | **Missing** |
| Android SDK | — | **Missing** |

Flutter/Dart/Docker/Android SDK are not available in this environment, so the
Flutter mobile project cannot be compiled, analyzed, or tested in Phase 01.
The mobile directory is scaffolded with valid Dart/Flutter source files so it
is ready for Phase 02 once the Flutter SDK is installed.

## Getting Started (Phase 02)

1. Install the Flutter SDK (stable channel) and Dart.
2. Install Android Studio and the Android SDK for Android builds.
3. Run `flutter doctor` in `mobile/`.
4. Copy `.env.example` to `.env` and fill in placeholder values (never commit `.env`).
5. Run `scripts/health_check.py` to validate project health.

## License

See [LICENSE](LICENSE).
