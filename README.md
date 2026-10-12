# DailyFit

DailyFit is a workout and nutrition app with two independent native implementations: **SwiftUI for iOS** and **Java for Android**. Its main features work offline, with no account or synchronization. The interface uses a dark theme with lime-green accents and is currently **in Italian**.

**Code was generated with ChatGPT 6.1 Sol and reviewed with GPT 6 Astra.**

## Features

- Workout plans organized by training day, with configurable exercises and sets: repetitions, ranges, duration, weight and rest time.
- Exercise catalog with images, instructions, muscle groups and video links.
- Rest timer with start, pause, resume and completion alerts. Only one timer can run at a time.
- Free-form training notes.
- A recurring weekly meal plan, with changes for individual dates that leave the base plan untouched.
- Expandable meals, optional snacks and a food catalog with nutritional values per 100 g.
- Calorie and macronutrient totals, customizable targets and a shopping list.
- JSON backup and restore, plus Excel export for viewing in Excel or Google Sheets.
- A shortcut to ChatGPT, without automatically sharing app data.

A new installation includes 15 exercises with 30 images, a four-day workout plan and 6 foods. Weights, rest times, meals and targets can be adjusted to suit the user.

## Repository structure

```text
DailyFit/
├── iOS/         Xcode project, source code, assets and XCTest tests
├── android/     Gradle project, source code, assets and JUnit tests
├── .gitignore
├── LICENSE
└── README.md
```

Images and icons are bundled with each native project. Tests are included in the source code but are not shipped in the apps.

## Run on iPhone

Requires a Mac with Xcode and a simulator or device running iOS 17 or later.

1. Open `iOS/DailyFit.xcodeproj` in Xcode.
2. Select the **DailyFit** scheme and an iPhone simulator.
3. Press **⌘U** to run the tests or **⌘R** to launch the app.
4. To run on a physical iPhone, select your Team under **Signing & Capabilities**, connect the device and select it as the destination. Enable Developer Mode if prompted.

The bundle identifier is `it.dailyfit.app`. You may need to choose a unique identifier when signing with your own account.

## Run on Android

Requires Android Studio, Android SDK 36 and a compatible JDK 17 installation. The Gradle wrapper is included. The app supports Android 8.0 (API 26) and later.

1. Open the `android` directory in Android Studio.
2. Complete Gradle synchronization and select an emulator or device.
3. Run the **app** module.

To run the unit tests and build the debug APK, open a terminal in the `android` directory and execute:

**Windows**

```powershell
.\gradlew.bat testDebugUnitTest assembleDebug
```

**macOS/Linux**

```sh
chmod +x gradlew
./gradlew testDebugUnitTest assembleDebug
```

The application ID is `it.dailyfit.app`. The debug APK is written to `app/build/outputs/apk/debug/app-debug.apk`.

## Data and architecture

The code separates the interface, domain rules and persistence. SQLite saves changes through incremental updates. Photos are stored in private files and loaded when needed.

The rest timer calculates the remaining time from its deadline and uses system alerts, avoiding continuous background work.

Data stays on the device. Videos and ChatGPT may require an Internet connection. Backups and exports are created on request and can be shared manually.

## Verification

For **version 1.4.0**, the Android sources were compiled on Windows against SDK 36, Debug and Release APKs were generated, and **125 JUnit tests passed**. These checks used the SDK tools directly; the Gradle and Android Studio build workflow was not run in that verification session.

For iOS, the Xcode project, scheme, file references and assets were checked. The project contains **114 XCTest tests**. Swift compilation and test execution for this version still need to be completed on a Mac.

These checks do not replace testing the interface, notifications and app behavior on physical devices.

Archive metadata remains in memory, and backup and restore process the full dataset. Full pagination and automated UI tests are not implemented. Battery use and response times need to be measured on phones.

## Case study: from an idea to native apps with AI

DailyFit started as a personal project to manage workouts and nutrition. Development began with the feature requirements and an HTML prototype to explore the design. The iOS and Android versions followed, with changes driven by testing and issues found during use.

## Credits and license

DailyFit was created by Luca Venceslai.

The iOS and Android code, prototype and automated tests were generated with ChatGPT 6.1 Sol. GPT6 Astra was used for code review. The exercise images and app icon were also generated with AI.

DailyFit is released under the MIT license. See [LICENSE](LICENSE) for details.

Copyright (c) 2026 Luca Venceslai.
