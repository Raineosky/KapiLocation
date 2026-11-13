# 卡皮定位 KapiLocation 0.1.0

這是基於 [ChrisMack32/Locus](https://github.com/ChrisMack32/Locus) 的 MIT 開源客製版，不是完全獨立重寫，也不是原作者的官方版本。基底固定於 `83c8fb324983728e8f44759cfd834dc637ee38b5`。

**交付狀態：原始碼與編譯流程已準備，尚未經 Xcode 編譯及 iPhone 實機驗證；此 ZIP 不是可安裝的 IPA。**

## 這一版的功能

保留 Locus 的地圖選點、地名搜尋、瞬移、搖桿、步行／行車路線、手繪路徑、GPX 匯入匯出、最近使用、配對導引與背景維持機制。是否能長時間背景運作仍受 iOS 限制，不能保證所有 App 接受模擬定位。

- 新增自訂速度：0.1～300 km/h；搖桿與路線共用，設定保存在手機。
- 新增速度設定入口：主畫面速度數字、設定頁、路線頁。
- 可切換固定速度／±10% 隨機波動。搖桿推動幅度會進一步縮放速度。
- 原版已有最愛座標；此版再加入手動經緯度輸入、搜尋、拖曳排序、JSON 備份匯入／匯出。
- 匯入前檢查備份版本與座標；重複座標保留既有名稱。
- 修正路線取消後可能送出舊座標，以及短路段移動時間的計算。
- 改用球面計算，處理跨越國際換日線的移動。
- 獨立 App 名稱「卡皮定位」及 Bundle ID `tw.kapi.location`，可與 Locus 並存。
- 本次新增介面為繁體中文；原版部分介面仍保留英文。

## 使用條件

- 專案最低目標 iOS 18。這代表編譯設定，不代表已驗證每個 iOS 版本。
- 仍需已安裝的 **LocalDevVPN**；不需要同時執行原版 Locus。
- iOS 18～26 依原專案方式，先準備並匯入本機的 **RPPairing** 檔。原版 Locus 的配對與收藏不會自動跨 App 搬移。
- 連接 LocalDevVPN，預設隧道 IP `10.7.0.1`；首次建立定位連線先用 Wi-Fi。
- 若系統要求，開啟開發者模式並允許本機網路、定位權限。
- 保留上游的較新 iOS 配對程式碼，但未自行驗證；不要將上游的相容性描述當成實機測試結果。

## Windows 使用者：先透過 GitHub 產生 IPA

不用把 Apple ID、密碼、RPPairing 檔或手機資料上傳到 GitHub。這個流程只產生未簽署 IPA，之後由電腦上的 Sideloadly 或 AltStore Classic 簽署。

1. 解壓縮本檔，先閱讀 `開始使用.txt`。
2. 在 GitHub 建立自己的新儲存庫，例如 `kapi-location`。若選私人庫，先查看帳號的 Actions 配額／費用。
3. 使用 GitHub Desktop：File → New repository，選擇一個空目錄建立儲存庫；把解壓縮資料夾**裡面的內容**複製到該儲存庫。
4. 在 GitHub Desktop 提交變更（Commit），再 Publish repository。根目錄應直接看得到 `project.yml`、`Locus`、`scripts`。
5. 在 GitHub 網站進入 Actions → **Build KapiLocation IPA** → **Run workflow**。
6. 等待綠色成功標記；到該次執行頁面底部 Artifacts，下載 `KapiLocation-unsigned`，解壓縮後取得 `KapiLocation-unsigned.ipa`。
7. 若出現紅色失敗，尚未產生合格 IPA；下載或複製失敗步驟的錯誤訊息以便修正。不要把原始碼 ZIP 改副檔名為 IPA。

編譯工作使用 macOS 15 / Xcode 26.3，執行幾何測試後才編譯及打包；如果 GitHub 更新預裝 Xcode，需調整 workflow 中的路徑。`Vendor/idevice/libidevice_ffi.a` 在編譯時從固定上游提交下載並核對 SHA-256，避免在網頁上傳大型檔案。雜湊只驗證檔案一致性，不等於二進位安全稽核。

## 側載

### Sideloadly（Windows / Mac）

1. 使用官方 [Sideloadly](https://sideloadly.io/)。連接並信任 iPhone。
2. 把編譯好的 `KapiLocation-unsigned.ipa` 拖入，選擇裝置並在 Sideloadly 內完成 Apple ID 簽署。
3. 安裝後依 iOS 提示信任開發者、開啟開發者模式。
4. 啟用 LocalDevVPN，再開啟「卡皮定位」並匯入 RPPairing。

### AltStore Classic

先依 [AltStore 官方文件](https://faq.altstore.io/altstore-classic/your-altstore) 完成 AltServer / AltStore Classic 安裝，再從 My Apps 的「＋」選取 IPA。這裡指 **Classic**，不是 AltStore PAL。簽署方式與刷新限制依 AltStore / Apple 當時規定。

免費 Apple ID 側載通常需要每 7 天重新簽署；此專案沒有解除這項限制。

## 功能操作

- 點地圖建立標記 →「定位」。
- 點底部 `5.0 km/h` 類似的數字 → 開啟自訂速度 → 輸入數值 →「套用」。
- 關閉自訂速度後，回到步行／跑步／單車／開車的原版預設速度。
- 點星星開啟「收藏座標」，右上角「＋」選單可新增座標、匯入／匯出備份。
- 向左滑收藏可以改名或刪除；點「Edit」可排序。搜尋時不能拖曳排序。
- 點選收藏會直接啟用該座標的定位；路線到達終點後保持終點定位。
- 「停止」會中止移動並向系統要求清除模擬位置。若 VPN 已中斷而清除失敗，會顯示錯誤，不能宣稱已恢复真實 GPS；可重新連線後重試，必要時重新啟動手機。

## 後續更新

未來可以繼續加入功能，修改原始碼、遞增 `project.yml` 中的版本與 build number，重新跑 Actions 產生新版 IPA。

使用**相同 Apple ID、簽署方式及 Bundle ID**覆蓋安裝，通常可保留 App 資料。不要先刪除舊 App；更新前先匯出收藏備份。從原版 Locus 到本 App 是另一個 App，須重新匯入配對與收藏。

這版沒有 App 內自動下載／自動安裝更新；更新是「取得新版 IPA → 同一方式覆蓋側載」。

## Mac 本機編譯

安裝 Xcode 26 以上及 XcodeGen 後：

```sh
brew install xcodegen
bash scripts/build-ipa.sh
```

要用 Xcode 開啟：先執行 `bash scripts/fetch-engine.sh`、`xcodegen generate`，再開啟產生的 `Locus.xcodeproj`，scheme 仍叫 `Locus`，產品叫 `KapiLocation`。直接在 Xcode 安裝到手機時需自行選擇開發者團隊。

## 隱私與依賴

新增程式碼沒有分析 SDK、廣告 SDK、帳號後端或位置上傳伺服器。收藏和速度寫入 App 本機儲存，仍可能包含在使用者自己的裝置備份中。Apple 地圖的圖資、搜尋、路線規劃會連網。自行分享 JSON／GPX 時，檔案會經你選擇的服務傳送。

定位底層沿用上游提供的 idevice 預編譯函式庫；沒有對該二進位或 LocalDevVPN 做完整安全稽核，因此不承諾「絕對不外洩」。配對檔含裝置信任資料，請只保存在自己的裝置，不要放進 GitHub 或公開分享。

完整授權見 `LICENSE`。上游參考說明存於 `UPSTREAM-README.md` 與 `SETUP.md`，若其 App 名稱／版本與本文件不同，以本文件說明本客製版的部分為準。

## 驗證狀態

詳見 `VALIDATION.md`：已做檔案、設定及腳本靜態檢查；Xcode 編譯、IPA 安裝、定位注入、背景行為與 iPhone UI 仍待實際執行驗證。
