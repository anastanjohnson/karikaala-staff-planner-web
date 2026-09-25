# KARIKAALA Staff Planner

The website is the release web build of the Flutter app in `flutter/`, exported from the existing FlutLab project on 25 September 2026. Mobile and desktop use the same screens, bottom navigation, theme, Firebase authentication, and Firestore data. The separate HTML/Supabase implementation is replaced.

## Shared source

Make future app and website changes in `flutter/lib/`. Import this Flutter folder into FlutLab when continuing work there; independent copies do not synchronize automatically. Keep the exported native Android and iOS targets with the same Dart source. Native builds have not been validated in this migration.

## Build the website

Validated with Flutter 3.47.1. From `flutter/`:

```sh
flutter pub get
flutter test
flutter build web --release --base-href /karikaala-staff-planner-web/
```

GitHub Actions automatically tests, builds, and deploys updates to `flutter/` from main using the Pages workflow. Do not copy sample data or bypass authentication. The existing Flutter Firebase project is used; data from the previous separate Supabase website is not migrated.
