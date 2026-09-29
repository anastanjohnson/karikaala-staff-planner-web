# Staff website on Firebase Hosting

Production target: `karikaala-staff-planner`, https://karikaala-staff-planner.web.app

This is the existing Flutter staff app. Firebase Auth and Firestore remain in the existing `karikaala-staff-planner` project; deployment does not alter staff or roster data.

The `Build Firebase Hosting release` GitHub workflow tests and builds the current main branch with `/` as the base path and uploads `firebase-hosting-web`. It builds only; it does not automatically deploy or hold a service account credential.

To deploy, download that workflow's artifact into `flutter/build/web`, authenticate the Firebase CLI with an authorized hosting deployer, then run from the repository root:

```
firebase deploy --only hosting --project karikaala-staff-planner
```

Alternatively, with Flutter 3.47.1 installed, run `flutter pub get`, `flutter test`, `flutter build web --release --base-href /`, and `python3 tool/version_web.py` from `flutter/` before deploying.

The GitHub Pages workflow remains available at its original URL during the transition. Do not publish the repository's legacy root HTML app as the staff portal.

A custom domain such as `staff.karikaala.de` requires domain-owner DNS verification in Firebase Hosting. Use the exact DNS records Firebase supplies; do not change the restaurant's root domain records.
