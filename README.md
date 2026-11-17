# Luna Cycle

Luna Cycle 是一款 Android 優先、繁體中文、離線優先的月經週期與健康紀錄 App。無帳號、無後端、無分析追蹤 SDK；核心紀錄保存在手機的加密 SQLite 資料庫。Android 可選擇透過 HTTPS 查詢公開 GitHub Release 更新，查詢不會傳送健康資料。

## 功能

- 首頁、月曆、記錄、分析、我的五個主要分頁
- 月經開始／結束、歷史補登、編輯、刪除及每日經血紀錄
- 週期預測使用最近六個有效週期的中位數與變異程度；不同追蹤模式不會錯用自然週期模型
- 症狀、情緒、疼痛、身體狀況、生殖健康、藥物、自訂事件及日記記錄
- 週期長度、經期天數、症狀、情緒、疼痛、經血量與預測偏差分析
- 本機經期提醒、每日記錄提醒、自訂單次提醒及 App 靜音時段
- 每日藥物排程、多時段提醒、服用／略過標記與近 30 天已記錄摘要
- CSV、JSON、繁體中文 PDF 匯出；以密碼加密的完整備份與還原
- 可選擇產生包含逐日紀錄及已標記藥物服用狀態的就診摘要 PDF
- 可選擇以指紋、臉部辨識或裝置螢幕鎖保護 App
- Android GitHub Release 更新檢查、APK 雜湊／簽章驗證及系統安裝流程

預測只供紀錄與粗略估算，不提供醫療診斷或避孕保證。通知文字不含月經、症狀、藥物或提醒名稱。更新需要網路；健康紀錄、分析和匯出仍可離線使用。下載與安裝都需使用者操作並由 Android 顯示系統確認。

## 工具鏈

- Flutter 3.50 stable、Dart 3.14
- Android SDK 36、JDK 21、Gradle 9.5、AGP 9.3.1
- Android Application ID：`app.lunacycle.personal`；最低 API 24
- 主要套件：Riverpod、go_router、Drift、SQLite3MultipleCiphers、fl_chart、flutter_local_notifications、local_auth

目前已在 Android API 31 模擬器完成安裝、通知流程與覆蓋更新驗證；另以 Xcode 26.4.1 成功建置 iOS Simulator app（`flutter build ios --simulator --no-codesign`）。iOS 實機簽署及安裝尚未驗證。

從 Flutter 專案目錄執行：

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --concurrency=1
flutter run
```

執行 Android 端整合流程：

```sh
flutter test integration_test/app_flow_test.dart -d <emulator-id>
```

## 本機資料安全

SQLite 以 SQLite3MultipleCiphers 加密。隨機 256-bit 金鑰由 `flutter_secure_storage` 保存在平台安全儲存。若既有資料庫的金鑰遺失或加密引擎不可用，App 會停止開啟該資料庫，不會降級成明文或覆寫原檔。Android 自動備份已停用，避免只還原資料庫而遺失對應金鑰。

加密備份使用 PBKDF2-HMAC-SHA256 衍生金鑰及 AES-256-GCM 驗證加密。還原前會驗證密碼、格式、大小、欄位與版本，之後才在單一資料庫交易內取代現有內容。忘記備份密碼就無法還原。CSV、JSON 及 PDF 是未加密檔案，分享前會提醒使用者檢查目的地。

PDF 內嵌 Noto Sans TC 字型以支援離線繁體中文；字型依 SIL Open Font License 提供，授權檔在 `assets/licenses/NotoSansTC-OFL.txt`。

## 建立 Android APK

Debug APK：

```sh
flutter build apk --debug
```

Release APK：

```sh
flutter build apk --release
```

輸出位於 `build/app/outputs/flutter-apk/app-release.apk`。目前正式版為 `1.1.0+3`（versionCode 3，83,401,584 bytes），已發布至 [GitHub Release](https://github.com/Daniel-LoCY/luna-cycle/releases/tag/v1.1.0)。在 Android API 31 模擬器以同 Application ID／簽章、版本號設為 `1.0.0+2` 的 OTA 測試基底，完成線上查詢、下載、驗證、系統安裝至 `1.1.0+3`、啟動及最新版本檢查。測試時沒有週期紀錄可供逐筆比對；Android 回報首次安裝時間未變，且更新揭露沒有再次出現。

APK SHA-256：

```text
269a8ef81bd19c09d58ae0aa38f5f7c1f78b5137f81c393e7b0aa13947e48dae
```

正式簽章憑證 SHA-256 指紋：

```text
909ab7d2ac94094284335763e26246acf716376b1b2844867dbcf1b0cfb0b1d5
```

安裝或覆蓋更新：

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

正式版包含 OTA 查詢所需的 INTERNET 權限。App 不會在背景靜默安裝；正式版必須使用固定的 Android Application ID 與同一把 Release keystore 簽署，才可覆蓋更新並保留 SQLite 資料。

Keystore、密碼和 Gradle 設定都應放在 repo 外或 Git 忽略的本機檔案中。請將 keystore 和密碼各自安全備份，不要提交到 Git、聊天紀錄或公開雲端。若搬到另一台建置機，使用自己的私密路徑建立 `android/key.properties`：

```properties
storeFile=/absolute/path/to/luna-cycle-release.jks
storePassword=your-store-password
keyAlias=luna-cycle-release
keyPassword=your-key-password
```

簽章遺失後無法以相同 App 身分發布可覆蓋安裝的 APK。每次發布前提高 `pubspec.yaml` 版本號和 build number；再以相同 keystore 執行 Release build，安裝時可使用：

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

資料庫結構升級必須增加 Drift schema version 並撰寫 migration；不可在升級時刪除或重建使用者資料庫。覆蓋安裝仍應在 Android 裝置上驗證版本號、簽章及資料保留。

## GitHub Release 更新

App 只讀取公開的 `Daniel-LoCY/luna-cycle` 最新正式 Release。Release 必須包含 `update.json` 及命名為 `luna-cycle-<version>+<build>.apk` 的 APK。更新程式檢查 Application ID、versionCode、最低 Android API、GitHub asset SHA-256、APK 大小和固定正式簽章指紋，再交給 Android PackageInstaller 顯示確認。下載時 App 顯示百分比及已收／總大小，並標示雜湊與簽章驗證階段；安裝確認及實際安裝進度由 Android 系統畫面顯示。裝置可能要求在系統設定允許 Luna Cycle 安裝此來源的 App。

公開的 `1.0.0` APK 尚未包含 App 內更新器，首次升級至 `1.1.0` 必須手動安裝 APK；安裝後即可使用 App 內更新檢查後續版本。

下載進度介面已加入最新原始碼，尚未包含在公開的 `1.1.0` APK；需要下一版 APK 才能在手機上使用。

公開 GitHub repository 已建立，`v1.1.0` 已發布，且 API 31 模擬器已完成線上更新安裝端對端驗證。後續版本在本機完成 `gh auth login`、設定 `android/key.properties`，確保程式碼已提交且工作樹乾淨，再執行：

```sh
FLUTTER_BIN=/absolute/path/to/flutter scripts/publish_github_release.sh
```

腳本會本機簽署 APK、核對套件／版本／最低 API／憑證指紋，並產生含 SHA-256 的 `update.json`。預設建立 GitHub **Draft Release**；加入 `--publish` 會在驗證完成後直接公開發布：

```sh
FLUTTER_BIN=/absolute/path/to/flutter scripts/publish_github_release.sh --publish
```

`--publish` 會在本機建置與驗證完成後直接建立並發布 GitHub Release，不等待人工審稿。簽署私鑰及密碼只留在本機，不提交或上傳至 GitHub；自動建置／發布由本機腳本執行，尚未把簽章交給 GitHub Actions。每次發布前須提高 `pubspec.yaml` 的版本號和 versionCode。

首次揭露後，每日最多自動檢查一次；可在「我的 → App 更新」關閉。手動檢查永遠可用。GitHub 不可用時，App 仍可離線記錄與查看健康資料。

## 文件

- [ARCHITECTURE.md](ARCHITECTURE.md)：程式分層、安全資料流、資料模型、預測與雲端擴充界線
- [TASKS.md](TASKS.md)：實作、驗收狀態與測試紀錄
- [CHANGELOG.md](CHANGELOG.md)：版本更新摘要
