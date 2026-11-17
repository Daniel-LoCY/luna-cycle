# Luna Cycle 架構

## 產品邊界

Android 優先、離線優先的個人健康紀錄工具。沒有帳號、後端、雲端同步或分析追蹤 SDK。Android 可選擇透過 HTTPS 查詢公開 GitHub Release，僅傳送版本請求，不傳送健康資料；下載與安裝由使用者操作並由 Android 確認。資料只會在使用者明確選擇匯出或分享時離開 App。週期、排卵及易受孕日都是估算，不可當作醫療診斷或避孕依據。

## 程式分層

```text
lib/
  app.dart                         GoRouter、五個主分頁、全域鎖定與週期提醒重排
  main.dart                        zh-TW 初始化、加密資料庫啟動、ProviderScope
  core/
    cycle_prediction.dart          無副作用的週期統計與預測
    providers.dart                 Riverpod Repository、設定、資料流
    database/
      app_database.dart            Drift schema v3、加密連線、版本遷移
      cycle_repository.dart        驗證、交易、CRUD、刪除標記及同步 outbox
    data_management/
      export_archive_service.dart  CSV／JSON、版本化加密備份與安全還原
      health_report_pdf_service.dart 繁體中文健康摘要與就診摘要 PDF
    notifications/                 時區、勿擾時間及本機通知排程
    updates/                       GitHub Release、APK 驗證與 Android 安裝橋接
    design_system/                  顏色、深淺主題、共用元件
  features/
    dashboard/ calendar/ records/ analysis/ settings/ onboarding/
```

Widget 只透過 Repository／Riverpod 讀寫資料，不直接操作 SQLite。週期預測、勿擾區間計算、資料備份和 PDF 產生都可獨立測試。日期欄位代表日曆日並以 UTC 午夜儲存；createdAt、updatedAt、deletedAt 儲存 UTC 時戳，通知排程使用裝置 IANA 時區。

## 本機資料模型與升級

Drift schema version 為 3：

- `Periods`：經期起訖、經血量、點狀出血、血塊、備註、UUID、version、tombstone 與 syncState。
- `DailyLogs`：疼痛、經血量、點狀出血、血塊、症狀、情緒、身體／生殖健康 JSON、藥物、標籤、日記與同步欄位；日期唯一。
- `AppSettings`：週期模式、提醒、主題與隱私設定。
- `PredictionSnapshots`：可追溯的估算結果快照。
- `SyncOutbox`：為未來本機優先同步預留的變更佇列。
- `MedicationSchedules`：每日藥物／補充品提醒時段與版本化刪除標記。
- `MedicationIntakeEntries`：依排程、日期與時間唯一識別的已服用／略過標記，保留當時名稱快照。

所有可同步紀錄使用穩定 UUID。更新遞增 version，刪除以 tombstone 保留同步語意。schema v1→v2 新增每日紀錄經血量、點狀出血及血塊欄位；v2→v3 新增藥物排程與服用標記表。遷移測試確認舊健康資料保留。遷移失敗時必須由 SQLite 交易回復；任何版本禁止刪除或重建使用者資料庫。

## 週期估算

以實際經期開始日的日曆差計算週期，最多採用最近六個間隔。中位數降低單次異常值影響，MAD、週期跨度與資料量決定信心說明。少於三個間隔時最多顯示一筆明確標示的初步估算；資料不足時不捏造日期。歷史日期更新或刪除後，Riverpod 資料流會更新首頁、日曆、分析及已排定的本機提醒。

自然週期預測僅適用一般追蹤、不規律週期與備孕模式。排卵與易受孕區間須使用者開啟、模式適用且歷史穩定時才顯示；荷爾蒙避孕、懷孕、產後及只記錄模式不使用自然週期模型。

## 提醒與 App 鎖定

提醒使用 `flutter_local_notifications` 與 IANA 時區，不要求精確鬧鐘權限，Android 使用非精確省電排程。每日、估算經期、自訂與藥物多時段提醒皆使用通用通知文字。勿擾區間由 App 在排程時計算；系統通知權限被撤銷或排程失敗時，提醒設定頁顯示需要處理的狀態。App 回到前景、裝置重新開機或 App 更新後重新排程。服用摘要只計算使用者標記的項目，未標記項目不解讀成漏服。

App 鎖定可選擇系統生物辨識或裝置螢幕鎖（PIN、圖形或密碼）。鎖定畫面擋住所有 App 內容，驗證使用 `local_auth`；SQLite 加密仍是儲存層保護，不依賴 UI 鎖定。

## 加密、匯出與還原

SQLite 以 SQLite3MultipleCiphers 的 `sqlite3mc` cipher 加密，隨機 256-bit 金鑰存在 `flutter_secure_storage`。啟動時驗證 cipher 可用；既有資料庫缺少金鑰時停止操作並保留原檔，不建立新的明文資料庫。Android 自動備份關閉，避免加密資料與金鑰不同步搬移。

加密備份含格式版本、資料庫 schema 版本、PBKDF2-HMAC-SHA256 參數、salt、AES-256-GCM nonce、ciphertext 及認證 tag。還原先驗證封裝、密碼、完整 JSON、欄位、ID、唯一日期與資料大小，再於單一 SQLite transaction 內取代全部資料。解密失敗、錯誤密碼或寫入失敗不得部分改動現有資料。

CSV 與 JSON 使用選定日期範圍，分享前顯示明確的敏感資料提示。PDF 內嵌 Noto Sans TC，可離線產生；實際紀錄摘要與週期估算分節呈現。純文字匯出不加密，保留給使用者明確指定分享目的地。

就診摘要 PDF 可另外加入選定期間的逐日症狀、疼痛、情緒、經血量、藥物與日記，以及已明確標記的藥物服用狀態。產生前提醒該 PDF 未加密且含敏感資料。

資料庫金鑰只保護本機 SQLite；加密備份密碼是另一把使用者管理的金鑰，遺失後無法還原。Release keystore 和密碼不提交 Git，覆蓋更新沿用同一組簽章並提高 versionCode。

## Android 更新來源

`GitHubUpdateRepository` 僅查詢固定公開 repository 的 latest published release，限制 HTTPS、回應大小、重新導向主機、版本格式、套件識別碼與最低 Android API。`update.json` 的 SHA-256 會與 Release asset digest（若 API 提供）及下載 APK bytes 比對。下載後再由原生 PackageManager 讀取 APK package、version、minSdk 與簽章憑證，必須符合目前安裝版本和固定 Release 憑證指紋。APK 暫存在 App 私有目錄；呼叫 PackageInstaller 前再次驗證檔案雜湊與簽章。安裝由 Android 系統 UI 完成，不靜默安裝。

首次揭露後每天最多自動查詢一次；使用者可關閉。請求不附帶任何健康紀錄或本機識別資料。更新功能使用 Android INTERNET 與安裝來源權限；這不影響離線記錄。`scripts/publish_github_release.sh` 本機建置並驗證簽署 APK、產生 manifest、建立 Draft Release，不含 keystore 上傳步驟。公開 repository 建立前不能做 live OTA 端對端測試。

## 雲端同步擴充

目前沒有任何遠端資料來源或網路同步。未來可在 Repository 邊界加入遠端實作，使用 UUID、version、updatedAt、deletedAt 與 outbox 做增量傳輸和衝突處理。首次上傳敏感健康資料前，必須取得明確同意，並說明端對端保護、資料位置、撤回及刪除方式。離線 CRUD 和預測仍由本機資料層維持。

## 測試邊界

`test/` 涵蓋週期演算法、日期、資料 CRUD、v1→v3／v2→v3 遷移、加密備份錯誤回復及舊備份相容、PDF、提醒排程、GitHub manifest／APK 完整性、更新授權流程與主要 Widget 流程。`integration_test/` 覆蓋容器啟動與五個主要頁面導覽。Android 發布檢查另包含加密資料庫重啟保存與同簽章覆蓋更新；本次 GitHub OTA 發布尚待 repository 建立後驗證。
