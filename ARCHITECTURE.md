# Luna Cycle 架構

## 產品邊界

Android 優先的離線個人健康紀錄工具。第一版不建立帳號、不送出網路請求；預測是紀錄輔助，不是醫療診斷或避孕依據。

## 分層

- `features/<feature>/presentation`：Flutter widgets、表單及畫面狀態。
- `features/<feature>/application`：用例與 Riverpod providers。
- `features/<feature>/domain`：實體、Repository contracts 與純 Dart 預測邏輯。
- `features/<feature>/data`：Drift 查詢及 Repository 實作。
- `core/database`、`core/security`、`core/notifications`、`core/design_system`：跨功能基礎設施。

Widget 不直接操作 SQLite。日期紀錄以當地日曆的年月日保存；created／updated 時間以 UTC 保存。Drift schema version 逐版遷移，禁止破壞性重建使用者資料。

## 本機安全

SQLite 使用具加密能力的 SQLite3MultipleCiphers，透過啟動檢查確認 cipher 可用，任何失敗均不得退回明文資料庫。隨機 DB key 儲存於平台安全儲存；PIN／生物辨識解鎖由獨立安全服務管理。備份以明確版本封裝，驗證完整性與密碼後才原子式取代現有資料。

## 預測

週期定義為相鄰實際月經開始日的日曆日差。採最近最多六個可用完整週期間隔的中位數及 MAD，將資料筆數和變異明確呈現。預測快照保留生成時間，供事後比較而不受重算覆寫。生育期僅在明確開啟、資料支持且適用模式中顯示粗略估算。

## 未來同步

所有可同步紀錄使用 UUID、version、updatedAt、deletedAt，預留同步狀態與 outbox。Repository 是資料邊界；雲端服務尚未實作。未來首次上傳敏感資料必須由使用者明確同意，且本機離線資料流程持續可用。

## 建置與簽章

固定 Application ID 為 `app.lunacycle.personal`，最低 Android API 24。Release keystore 與 `key.properties` 不進 Git；版本遵守 Android versionCode 單調遞增。新版 APK 必須由相同簽章簽署才可覆蓋安裝並保留 app 私有資料。

