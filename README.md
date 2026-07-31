# Linka

An English-tutoring marketplace for Uzbekistan. Students book 1:1 lessons with
tutors, sit full mock IELTS tests, enrol in live group courses, and pay from an
in-app wallet.

Built with Flutter for iOS and Android, against a Django REST backend.

## Features

**Learning**
- 1:1 lesson booking with tutor availability and scheduling
- Live group courses with co-tutors, session rosters and announcements
- Full mock IELTS tests — reading, listening, writing and speaking, with scored results and history
- Speaking practice with random partner matchmaking over WebSockets, plus debate rooms
- Writing prompts with sample submissions and feedback
- Podcasts with transcripts, sleep timer and playback progress
- Articles and PDF reading material

**Tutors**
- Profiles with certificate verification, speaking and writing samples
- Schedule and availability management
- Course authoring and management
- Earnings with held balances and payouts

**Platform**
- Phone (OTP), email and Telegram sign-in
- In-app wallet, payments and IELTS test registration
- Chat, channels, stories and webinars
- Push notifications and an in-app inbox

## Getting started

Requires the Flutter SDK (stable channel).

```bash
flutter pub get
flutter run
```

Build release artifacts:

```bash
flutter build apk --release
flutter build ipa --release
```

## Project layout

```
lib/
  data/       static data and constants
  models/     domain models
  screens/    one file per screen
  services/   API clients and platform services
  theme/      colours, typography, theming
  widgets/    shared UI components
landing/      marketing landing page
docs/         backend integration notes
test/         widget and unit tests
```

## Documentation

- [`API.md`](API.md) — REST API reference
- [`FLUTTER_SPEAKING_AND_DAILY.md`](FLUTTER_SPEAKING_AND_DAILY.md) — speaking matchmaking and Daily.co video flows
- [`docs/backend/media-upload-streaming.md`](docs/backend/media-upload-streaming.md) — media upload and streaming
