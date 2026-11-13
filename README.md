# Luna Cycle

離線優先的繁體中文月經與健康週期紀錄 App。Android 是第一版安裝目標，Application ID 為 `app.lunacycle.personal`。

## 開發環境

本專案需要目前相容的 Flutter stable、Android SDK command-line tools、Android SDK、JDK 及 Gradle。請以 `flutter doctor -v` 確認環境。具體版本將在工具鏈與套件相容性確認後記錄。

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```

## Release APK

Release 使用專用 Android keystore。請勿將 keystore 或含密碼的 `key.properties` 加入版本控制。設定完成後執行：

```sh
flutter build apk --release
```

輸出位於 `build/app/outputs/flutter-apk/app-release.apk`。覆蓋更新必須沿用相同 Application ID 與簽章，並遞增 `versionCode`；實際更新與資料保留需在 Android 裝置驗證。

目前仍在 Phase 1，功能與建置狀態以 `TASKS.md` 驗收紀錄為準。

