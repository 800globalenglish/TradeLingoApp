# 800 Global English - Android App (Flutter)

## What's built so far

- **Login screen** - talks to a `MobileLogin` endpoint you'll add to your
  ASP.NET `AccountController` (not built yet - see below).
- **Lesson list screen** - loads lessons from your server if online, falls
  back to a local offline database if not.
- **Local database** (`lib/services/local_db.dart`) - stores lessons and
  pending quiz scores on the phone itself, so quizzes work fully offline.
- **Sync service** - sends locally-saved quiz scores to the server once
  back online, keeping only the best score per quiz.

## What's NOT built yet (placeholders for now)

- The actual lesson detail screen (words, sentences, quizzes, video player)
- The video download manager (wifi-gated, per-lesson)
- The content-package.zip download + unzip logic
- Your server-side endpoints:
  - `POST /Account/MobileLogin` (username, password) -> { success, token, memberId }
  - `GET /MobileApi/GetAllLessons` -> JSON array of lessons
  - `POST /MobileApi/SubmitQuizResult` (token, lessonGuid, quizType, score) -> { success }

Until those server endpoints exist, the app will always show "Offline" and
fall back to an empty local list - that's expected, not a bug.

## How to run this on your computer

1. **Install Flutter** - follow Google's official installer for your OS:
   https://docs.flutter.dev/get-started/install
   (This also installs Dart, which Flutter uses.)

2. **Install Android Studio** (if you don't have it) - needed for the
   Android emulator and SDK tools, even though we're writing code in
   VS Code or any editor you like:
   https://developer.android.com/studio

3. **Open a terminal in this project folder** and run:
   ```
   flutter pub get
   ```
   This downloads the packages listed in `pubspec.yaml` (sqflite, http, etc).

4. **Start an emulator** (from Android Studio's Device Manager) or plug in
   a real Android phone with USB debugging enabled.

5. **Run the app:**
   ```
   flutter run
   ```

You should see the login screen. Since the server endpoints don't exist
yet, login will show "Invalid username or password, or no internet
connection" - that's expected until we build the ASP.NET side.

## Next step

Let's build the `MobileLogin` endpoint on your ASP.NET server next, so you
can actually test a real login end-to-end.
