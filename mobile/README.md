# Abdulmajeedpharma — Flutter Mobile

Android-first pharmaceutical platform built with Flutter.

## Tech Stack

- **Framework:** Flutter (stable)
- **Language:** Dart
- **State Management:** Riverpod
- **Navigation:** GoRouter
- **Backend Auth/Storage:** Supabase
- **Offline DB:** SQLite (Drift)
- **Localization:** intl (Arabic + English, RTL/LTR)

## Project Structure (Clean / Feature-First)

```
lib/
├── main.dart                 # Entry point
├── app/                      # App shell, router, providers
├── core/                     # Cross-cutting concerns
│   ├── config/               # Environment / flavor config
│   ├── constants/            # App constants (colors, strings, routes)
│   ├── errors/               # Custom exceptions / failure handling
│   ├── localization/         # i18n / l10n
│   ├── network/              # API client (Dio), interceptors
│   ├── storage/              # Local storage / preferences
│   ├── theme/                # Light / dark theme, design tokens
│   └── utils/                # Helpers / extensions
├── shared/                   # Reusable UI + domain models
│   ├── widgets/              # Common widgets
│   └── models/               # Shared data models
└── features/                 # Feature-first modules
    ├── home/
    ├── authentication/
    ├── drug_search/
    ├── drug_categories/
    ├── drug_details/
    ├── products/
    ├── manufacturers/
    ├── suppliers/
    ├── yemen_market/
    ├── image_recognition/
    ├── barcode_scanner/
    ├── pharma_ai/
    ├── favorites/
    ├── messaging/
    ├── notifications/
    ├── database_import/
    └── settings/
```

Each feature follows Clean Architecture layers:
- `data/` — repositories implementations, remote/local datasources, models
- `domain/` — entities, use cases, repository interfaces
- `presentation/` — Riverpod providers, UI pages/widgets

## Requirements

- Flutter SDK (stable)
- Android SDK (for Android builds)
- Supabase project (URL + anon key)
- Backend API running (FastAPI + PostgreSQL)

## Running

```bash
cd mobile
flutter pub get
flutter run
```

> **Note (Phase 01):** The Flutter SDK is not installed in this environment, so
> `flutter analyze` and `flutter test` could not be executed. They will run in
> Phase 02 once Flutter is available.
