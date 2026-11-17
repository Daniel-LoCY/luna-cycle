# Luna Cycle 開發與驗收進度

## Phase 1 — 基礎建置
- [x] 建立 Flutter 專案、固定 Android Application ID 與 SDK 設定
- [x] Design System、深淺主題、繁體中文、五 Tab 路由
- [x] Drift／SQLite3MultipleCiphers、平台安全金鑰、本機 Repository 與同步中繼欄位
- [x] Onboarding：最近起訖日、週期參數、目的、預測及提醒選項，可略過
- [x] 首頁、日曆、日期範圍選擇、實際與預測標示
- [x] 真實月經與每日健康紀錄 CRUD、歷史搜尋及自訂症狀
- [x] API 31 Android 模擬器確認加密 SQLite 可啟動、強制停止後資料仍在；DB 檔案標頭不是明文 `SQLite`

## Phase 2 — 核心功能
- [x] 月經補登、開始／結束、編輯、刪除、經血量、點狀出血、血塊與備註
- [x] 症狀、疼痛、情緒、睡眠、精力、食慾、運動、體重、體溫及生殖健康欄位
- [x] 藥物、自訂標籤、自訂症狀及日記
- [x] 六個近期週期中位數、MAD、資料量可信度及多週期預測
- [x] 不規律週期及模式相容性；排卵／易受孕估算明確標示限制
- [x] 歷史修改後自動刷新首頁、日曆、分析及通知預測
- [x] 跨月、跨年、閏日、模式切換及預測停用單元測試

## Phase 3 — 進階功能
- [x] 以真實紀錄計算 fl_chart 分析及症狀熱度
- [x] 本機經期／每日／單次提醒、勿擾時段、權限請求及時區重排
- [x] 一般、不規律、備孕、荷爾蒙避孕、懷孕、產後與只記錄模式
- [x] CSV、JSON、繁體中文 PDF 日期範圍匯出與系統分享
- [x] 匯出前敏感資料提示，PDF 分開呈現實際資料與預測估算
- [x] 加密完整備份、密碼驗證、內容檢查與資料庫交易式還原

## Phase 4 — 安全與資料管理
- [x] 可選裝置生物辨識／螢幕鎖 App 鎖定
- [x] PBKDF2-HMAC-SHA256 + AES-256-GCM 備份與錯誤密碼／損壞檔回復測試
- [x] 清除本機紀錄、設定、預測快照與同步佇列
- [x] Drift schema v1→v3 遷移與舊資料保留測試
- [x] 禁止明文退回；遺失資料庫金鑰時停止使用並保留原始資料檔
- [x] 預測依據說明、跨週期症狀規律提示、加密備份檢查與備份提示間隔設定
- [x] 首頁快速記錄保留未編輯欄位，提供限時復原且避免覆蓋後續修改

## Phase 5 — 正式安裝
- [x] Null Safety、表單驗證、錯誤訊息、非同步狀態及 Repository 分層
- [x] 單元、Widget、資料庫遷移、備份、PDF、勿擾排程及主要互動測試
- [x] Android 整合測試：App 啟動、五個主要分頁及每日通知實際排程查詢
- [x] Xcode Simulator 原生建置：`flutter build ios --simulator --no-codesign`
- [x] 建立 Release keystore；簽署資料和密碼位於 Git 忽略的本機檔案
- [x] 建置 Release APK，檢查 Application ID、版本、正式簽章及 Release manifest 權限
- [x] 同簽章從 versionCode 1 覆蓋安裝 versionCode 2，確認週期資料保留
- [x] 記錄 APK SHA-256、正式簽章指紋與安裝教學

## Phase 6 — GitHub Release 更新與藥物追蹤
- [x] 查詢公開 GitHub Release；限制 HTTPS、重新導向主機、套件識別碼和最低 Android API
- [x] 下載大小限制、GitHub asset SHA-256、APK metadata 和固定 Release 簽章驗證
- [x] 首次更新揭露、每日檢查設定、手動檢查／下載及 Android 安裝確認
- [x] 藥物每日多時段提醒、排程 CRUD、服用／略過記錄與 30 天實際標記摘要
- [x] 加密備份含藥物資料，支援 v2 備份還原；就診摘要顯示使用者實際標記
- [x] 建立本機 Release 建置與驗證腳本；僅建立 Draft，從不包含簽署私鑰
- [x] 建立公開 `Daniel-LoCY/luna-cycle` repository
- [ ] 建立第一個 GitHub Draft Release
- [ ] 於 Android 裝置端對端驗證查詢、下載、安裝及既有加密 DB 保留

## 驗收紀錄

- 2026-11-13：以 Flutter 3.50.0 stable／Dart 3.14.0 實作 App；`flutter analyze` 通過，`flutter test --concurrency=1` 29 項通過。
- 2026-11-13：API 31 模擬器實際啟動 Onboarding、進入首頁、開始經期、強制停止與重新啟動；首頁仍顯示同一筆進行中紀錄。`run-as ... od -N16` 檢查加密資料庫標頭，不含 SQLite 明文檔案簽章。
- 2026-11-13：Android API 31 模擬器整合測試通過，完成略過 Onboarding、逐頁導覽、開啟每日提醒並向原生通知插件確認排程存在。
- 2026-11-13：Release APK `1.0.0+1` 以正式 keystore 安裝，建立進行中月經紀錄並強制停止重啟，首頁仍顯示週期第 1 天。再以相同 keystore 建置 `1.0.0+2` 並執行 `adb install -r`，安裝成功且原紀錄保留。兩版簽章 SHA-256 指紋皆為 `909ab7d2ac94094284335763e26246acf716376b1b2844867dbcf1b0cfb0b1d5`。
- 2026-11-13：交付 Release APK 為 versionCode 2、versionName 1.0.0，大小約 81.8 MB；Release 權限僅含震動、通知與生物辨識相關權限，未要求 INTERNET。SHA-256：`d242648fc3aef8b738e3c989d78754b5eed04366106411214c2af67cf9a7b17c`。
- 2026-11-13：最終版本 `flutter analyze` 無問題、`flutter test --concurrency=1` 29 項通過；OSV.dev 批次查詢 lockfile 中 149 個 Pub 套件版本，未回報已知公告。
- 2026-11-13：使用 Xcode 26.4.1 完成 `flutter build ios --simulator --no-codesign`，成功產生 `build/ios/iphonesimulator/Runner.app`；未測試 iOS 實機簽署／安裝。
- 2026-11-17：加入 Android GitHub Release 更新器與 Draft Release 發佈腳本；會驗證套件、版本、最低 API、SHA-256 及固定簽章指紋。公開 repository 已建立，第一個 Draft Release 待建立。
- 2026-11-17：Drift schema 升至 v3，加入藥物排程、服用標記、每日通知、舊 v2 備份相容、就診摘要 PDF、備份檢查和快速記錄復原；`flutter analyze` 通過，46 項 Flutter 測試通過。
- 2026-11-17：本機 Release APK `1.1.0+3` 成功建置，確認 Application ID `app.lunacycle.personal`、minSdk 24、簽章指紋與預期相符；SHA-256 `269a8ef81bd19c09d58ae0aa38f5f7c1f78b5137f81c393e7b0aa13947e48dae`。尚未在 Android 裝置覆蓋安裝。
