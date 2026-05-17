# Draft Canvas — フル仕様書

> 対象読者: ユーザー（機能・対応環境・ライセンス）および開発者（アーキテクチャ・ドメインモデル・外部依存・ビルド）
>
> 更新: 2026-05-16  
> ブランチ: dev

---

## 目次

1. [概要](#1-概要)
2. [ユーザー向け機能仕様](#2-ユーザー向け機能仕様)
3. [ライセンス・課金](#3-ライセンス課金)
4. [プライバシー・利用規約](#4-プライバシー利用規約)
5. [アーキテクチャ](#5-アーキテクチャ)
6. [ドメインモデル](#6-ドメインモデル)
7. [外部依存](#7-外部依存)
8. [永続化レイアウト](#8-永続化レイアウト)
9. [ビルド・配布](#9-ビルド配布)
10. [ローカライズ](#10-ローカライズ)
11. [参考資料](#11-参考資料)

---

## 1. 概要

### 1.1 プロダクト概要

Draft Canvas は macOS 向けの AI 画像生成・編集デスクトップアプリケーションです。テキストプロンプトから画像を生成し、インペイント・背景除去・アップスケール・ベクター化といった後処理をプロジェクト単位のキャンバスで管理します。画像生成には Codex CLI を `app-server` モードでサブプロセス起動し、JSON-RPC over stdio 経由で OpenAI の画像生成 API（gpt-image pre-2.0）を呼び出します。すべての処理は Mac 上で完結し、サブスクリプションなしで使用できます。

キャッチコピー: **「Mac の画像編集を、シンプルに強く。」**

### 1.2 対象ユーザー

- macOS で画像素材を日常的に生成・管理したい個人ユーザー
- Web・印刷・SNS 用の画像制作に AI を活用したいクリエイター
- 商用利用も可（利用規約の範囲内）

### 1.3 動作環境

| 項目 | 要件 |
|------|------|
| OS | macOS 14 Sonoma 以降 |
| アーキテクチャ | Apple Silicon（arm64）・Intel（x86_64）両対応 |
| 必須ソフトウェア | Codex CLI（別途インストール） |
| インターネット | 画像生成・アカウント認証・ライセンス検証に必要。背景除去・ベクター化はオフラインで動作 |

---

## 2. ユーザー向け機能仕様

### 2.1 AI 画像生成

プロンプトテキストを入力し、Codex App Server 経由で gpt-image を呼び出して画像を生成します。

**パラメータ:**

- **プロンプト**: 自由テキスト（日本語・英語どちらも対応）
- **生成指示の言語**: 設定画面で「英語固定」または「入力言語を維持」を選択。デフォルトは「英語固定」で、日本語入力でも内部の画像生成ブリーフを英語に正規化してから Codex に渡す
- **count**: 生成枚数。UI 上は 1〜8 枚から選択
- **concurrency**: 並列実行数。count 以下で、セマフォとして機能
- **アスペクト比**: 以下から選択

| 値 | 比率 | 用途例 |
|----|------|--------|
| 自動（auto） | auto | モデル任せ |
| 正方形（square） | 1:1 | SNS投稿 |
| ポートレート（portrait） | 3:4 | 縦向き |
| ストーリー（story） | 9:16 | Instagram/TikTok |
| 横長（landscape） | 4:3 | 一般横向き |
| ワイドスクリーン（wide） | 16:9 | デスクトップ壁紙・映像 |

- **参照画像（添付画像）**: 1 枚まで添付可能。生成の視覚的ガイドとして利用
- **モデル選択**: 利用可能モデルは Codex から動的取得（GPT-5.5 / gpt-5.4 / GPT-5.4-Mini / gpt-5.3-codex / gpt-5.2）
- **Reasoning Effort**: `low` / `medium`（デフォルト） / `high`

**ジョブ管理:**

生成ジョブは `GenerationJob` として管理され、ステータスは `queued → running → succeeded / failed` の順に遷移します。ジョブ失敗時はエラーメッセージと詳細ログが記録されます。

**レート制限・動的並行制御:**

生成実行中にレート制限（API クォータ超過）を検知すると、以下の仕組みが自動的に動作します。

- `RateLimitClassifier`（`CodexAppServerClient.swift`）が JSON-RPC エラーレスポンスを解析し、レート制限起因かを分類
- `actor ConcurrencyController`（`GenerationCoordinator.swift`）がレート制限検知時に並行数を自動縮減し、`RateLimitConfirmation` を生成してユーザーへ確認を提示
- 対象ジョブの `hitRateLimitDuringRun` フラグが `true` になり、ログに記録
- ユーザーが縮減を承認すると生成を継続。キャンセルした場合は残ジョブを失敗扱いにして終了

**Codex バージョン依存:**

DraftCanvas は画像生成の実行を Codex App Server に完全委任します。利用可能なモデル一覧・画像品質・解像度・処理能力はすべて **インストールされている Codex のバージョン**に依存します。DraftCanvas 自体のアップデートとは独立しており、Codex を更新するだけで使えるモデルや生成品質が変わる可能性があります。DraftCanvas 側が制御できるのはプロンプト・`reasoningEffort`・モデル選択のみです。

### 2.2 画像編集

生成済み・インポート済みの画像を元画像として AI 編集を実行します。

**全体編集（Edit）:**

元画像を参照画像として渡し、ユーザーが入力した編集指示（例:「空を夕焼けに変えて」）に従って新しい画像を生成します。元画像の有用な部分が保持されます。

**インペイント（Inpaint）:**

1. 画像をクリックして選択 → キャンバス左側のアクションパネルから「マスクして編集」または「マスクして除去」をクリック
2. ブラシツールでマスク領域を描く
3. 編集モード（edit / remove）を指定してから生成を実行

- **edit モード**: マスク領域に指示テキストの内容を生成（透明領域=再生成箇所として Codex に渡す）
- **remove モード**: マスク領域のオブジェクトを自然背景で埋める（指示テキスト不要）

マスクファイルと合成画像は `masks/` ディレクトリに保存されます（`{itemID}_mask.png` / `{itemID}_composite.png`）。

### 2.3 プロンプト強化

「✨ 強化」ボタン（PromptPanel）を押すと、入力中のプロンプトを AI が自動的に詳細化します。

- 設定画面の「生成指示の言語」に従い、「英語固定」では英語出力、「入力言語を維持」では日本語入力→日本語出力
- 構図・色彩・照明・雰囲気・テクスチャ・視点・アートスタイルの詳細を追加
- 元の主題・意図を変えず 2〜4 文に拡張
- Codex に新しいスレッドを開いて強化プロンプトを取得（非同期、排他制御あり）

### 2.4 後処理機能

後処理は有料ライセンスまたはトライアル期間中のみ利用可能（EntitlementGate で制限）。

#### 背景除去

Apple Vision Framework を使用してオフラインで背景を除去します。処理した画像は PNG として `items/` に上書き保存され、`isBackgroundRemoved = true` フラグが立ちます。プレビューシート（`BackgroundRemovalPreviewSheet`）で確認してから適用できます。

#### アップスケール

選択した画像を参照画像として Codex に渡し、高解像度版を生成します。

- プロンプト: 元プロンプトを利用（インポート画像の場合は `"imported asset"` として扱う）
- 処理中は元のキャンバスカードにオーバーレイ表示
- 完了後はキャンバスに新しいカードとして追加（元画像は保持）

#### ベクター化（SVG 変換）

vtracer-ffi ライブラリ経由で PNG をラスターからベクターへ変換します。変換オプション（精度・スペックル除去・コーナー閾値など）は `VectorizationOptions` で管理されます。変換結果の SVG は `items/{itemID}.svg` として保存され、`hasSVG = true` フラグが立ちます。処理中はキャンバスカードにスピナーが表示されます。

**VectorizationOptions デフォルト値:**

| パラメータ | 値 | 意味 |
|-----------|-----|------|
| colorPrecision | 6 | 色精度 |
| filterSpeckle | 4 | スペックル除去 |
| cornerThreshold | 60 | コーナー検出閾値 |
| lengthThreshold | 4.0 | パスの最小長 |
| spliceThreshold | 45 | スプライス閾値 |
| layerDifference | 16 | レイヤー差分 |
| mode | 0（spline） | 変換モード |

#### マテリアル抽出

選択した画像からマテリアル・テクスチャを抽出し、新しいプロジェクトアイテムとして保存します（`MaterialExtractor` / `MaterialExtractionSheet`）。

### 2.5 キャンバス操作

| 操作 | 方法 |
|------|------|
| ズームイン/アウト | ピンチジェスチャ または Ctrl + スクロール |
| ズームコントロール | 右下のズームコントロールバー |
| アイテム移動 | ドラッグ |
| アイテムコピー移動 | Option + ドラッグ |
| 複数選択 | マーキー選択（ドラッグで範囲指定）またはクリック |
| 選択解除 | キャンバス余白をクリック |
| 拡大表示 | キャンバスカードをダブルクリック（`ExpandedImageSheet`） |
| アクションパネル | 画像をクリックして選択するとキャンバス左側に縦並びのアクションボタンが表示（`canvasActionPanel`）。再編集・マスク編集・除去・背景除去・素材分離・高解像度化・ベクター化・複製・エクスポート・Finder表示・削除 |
| 自動スクロール | 生成完了時に新しいカードへ自動スクロール（`CanvasAutoScroller`） |
| ソート | TopBar から「作成日 古い順」「作成日 新しい順」を選択 |

### 2.6 プロジェクト管理

**サイドバーの種別:**

| 種別 | 説明 |
|------|------|
| プロジェクト | 通常プロジェクト。生成された画像の集合体 |
| フィルタリングプロジェクト | 保存された検索クエリ。条件に一致するアイテムを横断表示 |
| すべての画像 | 全プロジェクトのアイテムを一覧 |
| 検索 | サイドバー検索ボックスに入力すると自動遷移。250ms デバウンス |

プロジェクトの表示名は最初の生成プロンプトの先頭 20 文字から自動生成されます（`ProjectNaming.summarize`）。ユーザーが手動でリネームすると `isAutoNamed = false` になります。

**プロジェクトに対する操作:**

- 作成・削除・リネーム
- お気に入り登録（`isFavorite`）
- モデル・ReasoningEffort の設定（プロジェクトごとに保存）
- アイテムの別プロジェクトへの移動

**タグ:**

アイテムにはタグを複数付与できます。タグはキャッシュ（`allTagsCache`）に集約され、検索や FilteringProject のクエリに利用できます。

### 2.7 エクスポート

**エクスポート形式:**

| 形式 | 説明 |
|------|------|
| PNG | ロスレス。最適化オプションあり（高速圧縮 / 最大圧縮〈ロッシー〉） |
| JPEG | 品質: 高(98) / 中(80) / 低(60) |
| SVG | ベクター化済みアイテムのみ選択可能 |

**リサイズ:**

幅・高さを指定したリサイズが可能（`ExportSettings.resizeEnabled`）。

**ファイル命名規則:**

`{プロジェクト名}-{2桁の連番}.{拡張子}` 形式（例: `夕焼けの海-01.png`）。ファイル名に使用できない文字は `_` に置換され、64 文字で切り捨て。

**一括エクスポート:**

選択した複数アイテムを ZIP アーカイブとして一括書き出しできます（`ZipExportPipeline`）。

**保存先:**

初回はフォルダ選択ダイアログが表示され、以後は同じフォルダを使用します。設定は UserDefaults に Security-Scoped Bookmark として保存。

### 2.8 インポート

ローカルの PNG・JPEG・WebP ファイルをキャンバスにドロップまたはダイアログで読み込めます（`DraftCanvasViewModel+CanvasImport`）。インポートしたアイテムは `isImported = true` フラグが立ち、prompt は空文字列になります。

### 2.9 通知と使用量カウンタ

**完了通知:**

生成完了時にシステム通知を送信します（`UserNotifications`）。通知許可は起動時に要求。完了時のサウンドは設定から選択できます（`CompletionSoundOption.glass` がデフォルト）。

**使用量カウンタ（Codex アカウント連携）:**

5時間ウィンドウと週次ウィンドウの使用量ピル（`usagePill`）が TopBar に常時表示されます。各ピルには「アイコン・使用量ラベル・残量プログレスバー・あと何日何時間（`resetText`）」が並びます。

TopBar のアカウントアイコン（`AccountPopover`）をクリックすると詳細ポップオーバーが開き、以下を確認できます:

- アカウント種別（ChatGPT / API Key / Amazon Bedrock / 未ログイン）
- アカウントメールアドレス（ChatGPT の場合）
- プラン名

カウンタはセッション内でも追跡され、AppStorage に永続化されます（`session5hCount`、`sessionWeeklyCount`）。

---

## 3. ライセンス・課金

### 3.1 価格と提供形態

| 項目 | 内容 |
|------|------|
| 価格 | ¥2,000（買い切り） |
| ライセンス台数 | 1ライセンスにつき最大 2台 |
| アップデート | v1.x 系は無料。v2.0 は優待価格予定 |
| 決済 | Lemon Squeezy（Stripe 経由） |
| 返金 | 購入から 30日以内に全額返金対応 |

### 3.2 トライアル

- 期間: 14日間（クレジットカード不要）
- トライアル中はすべての機能が利用可能
- 残り日数は `EntitlementGate.status = .trial(daysLeft: N)` で管理
- 時計の巻き戻しは `LicenseStore.detectClockRollback()` で検出。検出時は `expired` へ遷移

### 3.3 EntitlementGate（ライセンス管理）

`EntitlementGate.shared` は `ObservableObject` としてアプリ全体で共有されます。

**ステータス:**

| ステータス | 条件 |
|-----------|------|
| `.trial(daysLeft: N)` | トライアル期間中（N > 0） |
| `.licensed` | ライセンスキー・インスタンス ID が Keychain に存在 |
| `.expired` | トライアル期限切れ、またはライセンス検証失敗 |

**評価フロー（`evaluate()`）:**

1. Keychain にライセンスキーとインスタンス ID が存在 → `licensed`（バックグラウンドで検証）
2. 時計巻き戻し検出 → `expired`
3. トライアル開始日から経過日数を計算 → 残り日数を算出

**有料機能ゲート（`requireUnlocked()`）:**

- `.trial` または `.licensed` → `true`（操作続行）
- `.expired` → `false`（ライセンスプロンプトを表示）

**ゲートが有効な機能:**

- 背景除去
- アップスケール
- ベクター化（SVG変換）
- インペイント
- マテリアル抽出

### 3.4 ライセンス認証（Lemon Squeezy API）

`LicenseClient` が以下の API を叩きます。

| メソッド | エンドポイント | 用途 |
|---------|--------------|------|
| activate | `POST /v1/licenses/activate` | ライセンスキー + ホスト名でアクティベート。インスタンス ID を取得 |
| validate | `POST /v1/licenses/validate` | ライセンスキー + インスタンス ID で有効性を検証（バックグラウンド） |

ライセンスキーとインスタンス ID は `LicenseStore`（Keychain）に保存します。アクティベーションエラー種別: `invalidKey` / `activationLimitReached` / `alreadyActivated` / `network`

Lemon Squeezy のチェックアウト URL 等の購入導線定数は `PurchaseConfig.swift` で一元管理されており、`LicenseSheet` および `TrialExpiredView` から参照します。

---

## 4. プライバシー・利用規約

### 4.1 収集データ

| データ | 収集方法 | 保存場所 |
|-------|---------|---------|
| 購入情報（氏名・メールアドレス） | Lemon Squeezy 経由。カード番号は保持しない | Lemon Squeezy サーバー |
| Mac の UUID（ハッシュ化） | ライセンス台数管理のため | Lemon Squeezy サーバー |
| クラッシュレポート | Apple の標準クラッシュレポート機能 | Apple サーバー |
| ライセンスキー・インスタンス ID | アプリが Keychain に保存 | ローカル Keychain |

### 4.2 第三者提供

| 提供先 | 目的 |
|-------|------|
| Lemon Squeezy（決済・ライセンス管理） | 購入処理・ライセンス認証 |
| Stripe（Lemon Squeezy の決済パートナー） | クレジットカード処理 |

画像データ・プロンプトの内容は Codex App Server 経由で OpenAI に送信されます。Codex アカウントのプライバシーポリシーが適用されます。

### 4.3 利用規約要点

| 項目 | 内容 |
|------|------|
| 個人利用 | 可 |
| 商用利用 | 可 |
| 再配布・転売 | 禁止 |
| 改変・リバースエンジニアリング | 禁止 |
| 保証 | 現状有姿提供、免責 |
| 準拠法 | 日本法 |
| 連絡先 | spade3yasui@gmail.com |
| 開発者 | Yuichiro Yasui |

---

## 5. アーキテクチャ

### 5.1 全体図

```
DraftCanvasApp.swift
├── DraftCanvasViewModel (@MainActor ObservableObject)
│   ├── ViewModel/DraftCanvasViewModel+Account.swift      — Codexアカウント・使用量
│   ├── ViewModel/DraftCanvasViewModel+Attachments.swift  — 添付画像管理
│   ├── ViewModel/DraftCanvasViewModel+CanvasImport.swift — 画像インポート
│   ├── ViewModel/DraftCanvasViewModel+Computed.swift     — 派生プロパティ
│   ├── ViewModel/DraftCanvasViewModel+Export.swift       — エクスポート
│   ├── ViewModel/DraftCanvasViewModel+FilteringProjects.swift — フィルタリングPJ
│   ├── ViewModel/DraftCanvasViewModel+Generation.swift   — 生成ループ
│   ├── ViewModel/DraftCanvasViewModel+ItemActions.swift  — アイテム操作
│   ├── ViewModel/DraftCanvasViewModel+Items.swift        — アイテムCRUD
│   ├── ViewModel/DraftCanvasViewModel+MaterialExtract.swift — マテリアル抽出
│   ├── ViewModel/DraftCanvasViewModel+Projects.swift     — プロジェクトCRUD
│   ├── ViewModel/DraftCanvasViewModel+PromptEnhance.swift — プロンプト強化
│   ├── ViewModel/DraftCanvasViewModel+Upscale.swift      — アップスケール
│   └── ViewModel/DraftCanvasViewModel+Vectorize.swift   — ベクター化
│
├── GenerationCoordinator (Sendable)
│   └── CodexGenerationRunner : GenerationRunning
│       └── CodexAppServerClient (JSON-RPC stdio)
│
├── ProjectStore (永続化)
│   └── ~/Library/Application Support/Draft Canvas/
│
├── EntitlementGate (ライセンス)
├── LocalizationManager (言語切り替え)
└── SparkleUpdaterController (自動更新)
```

### 5.2 画面構成

メインウィンドウは 3ペイン構成です。

```
┌─────────────────────────────────────────────────────────────────┐
│  TopBar (ContentView+TopBar.swift)                              │
│  [アカウント使用量] [ログ] [設定] [ソート] [ライセンス]              │
├──────────────┬──────────────────────────────────────────────────┤
│              │                                                  │
│  Sidebar     │  Canvas Area (ContentView+Canvas.swift)          │
│  (ContentView│  · ProjectItem カードグリッド                     │
│  +Sidebar)   │  · マーキー選択オーバーレイ                        │
│              │  · ErrorToast                                    │
│  ・Projects  │  · 生成中: GenerationProgressView                │
│  ・Filtering │                                                  │
│  ・All Images│                                                  │
│  ・Search    │                                                  │
│              ├──────────────────────────────────────────────────┤
│              │  PromptPanel (ContentView+PromptPanel.swift)     │
│              │  · プロンプト入力 (PromptTextView)                │
│              │  · count / concurrency                          │
│              │  · アスペクト比                                  │
│              │  · 添付画像 (AttachedImageThumbnail)             │
│              │  · ✨強化 / 生成ボタン                           │
└──────────────┴──────────────────────────────────────────────────┘
```

**別ウィンドウ:**

| ウィンドウ ID | ファイル | サイズ |
|-------------|---------|-------|
| `"logs"` | `Views/LogWindow.swift` | 760 × 520 |
| `"licenses"` | `Views/LicensesWindow.swift` | 760 × 520 |

モーダルシート: `TrialExpiredView` / `LicenseSheet` / `BackgroundRemovalPreviewSheet` / `UpscalePreviewSheet` / `VectorizingOverlay` / `MaterialExtractionSheet` / `InpaintingMaskEditor` / `ExpandedImageSheet` / `ExportOptionsSheet` / `FilteringProjectCreationSheet`

`SettingsView` は `Settings` シーンとして登録されており、アプリメニュー「設定…」から開きます（言語・外観・保存先・サウンド）。

### 5.3 ファイル/モジュール対応表

| 機能 | 主要ファイル |
|------|------------|
| JSON-RPC 通信 | `CodexAppServerClient.swift`, `JSONRPCCodec.swift` |
| 生成調整 | `GenerationCoordinator.swift` |
| プロンプト組み立て | `GenerationCoordinator.swift` — `PromptFactory` |
| ベクター化 | `ImageVectorizer.swift`, `vtracer-ffi/` |
| 背景除去 | `BackgroundRemover.swift` |
| アップスケール | `ImageUpscaler.swift` |
| SVG ラスタライズ | `SVGRasterizer.swift` |
| エクスポート | `Export/ExportPipeline.swift`, `Export/ZipExportPipeline.swift` |
| エクスポート設定 | `Export/ExportSettings.swift` |
| 画像エンコード | `Export/ImageEncoder.swift` |
| バイナリ実行 | `Export/BinaryRunner.swift`（pngquant / oxipng） |
| ライセンス認証 | `License/LicenseClient.swift`, `License/LicenseStore.swift` |
| ライセンスゲート | `License/EntitlementGate.swift` |
| 言語管理 | `Localization/LocalizationManager.swift` |
| サムネイル | `CanvasThumbnailStore.swift` |
| 元画像ストア | `CanvasOriginalImageStore.swift` |
| CanvasMetrics | `CanvasMetrics.swift` |

---

## 6. ドメインモデル

ソース: `DraftCanvas/Models.swift`

### 6.1 Project

```swift
struct Project: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var isAutoNamed: Bool        // true = プロンプト先頭20文字から自動生成
    let createdAt: Date
    var updatedAt: Date
    var model: String            // Codex モデル ID
    var reasoningEffort: String  // "low" | "medium" | "high"
    var isFavorite: Bool
}
```

### 6.2 ProjectItem

```swift
struct ProjectItem: Identifiable, Equatable, Codable {
    let id: UUID
    var projectID: UUID
    let prompt: String
    let revisedPrompt: String?      // Codex が返した改訂済みプロンプト
    let aspectRatio: GenerationAspectRatio
    let actualAspectRatio: CGFloat?
    let createdAt: Date
    let errorMessage: String?
    var editedFromItemID: UUID?     // 編集元アイテム
    let hasSVG: Bool
    let isBackgroundRemoved: Bool
    let isImported: Bool
    var tags: [String]
}
```

ファイルパス: `{rootDirectory}/items/{id}.png`（SVG: `{id}.svg`）

### 6.3 GenerationJob

```swift
struct GenerationJob: Identifiable, Equatable {
    let id: UUID
    let index: Int
    var prompt: String
    var aspectRatio: GenerationAspectRatio
    var status: GenerationJobStatus   // .queued / .running / .succeeded / .failed
    var imageData: Data?
    var revisedPrompt: String?
    var logs: [String]
    var errorMessage: String?
    var hitRateLimitDuringRun: Bool   // レート制限ヒットを検知すると true
}
```

### 6.4 GenerationRequest

```swift
struct GenerationRequest: Equatable {
    var prompt: String
    var count: Int               // UI 上限: 4。normalizedCount で 1〜24 にクランプ（サーバー側バリデーション）
    var concurrency: Int         // 正規化後: 1〜count
    var aspectRatio: GenerationAspectRatio
    var editSource: GenerationEditSource?
    var attachedImagePath: String?
    var model: String
    var reasoningEffort: String
}
```

### 6.5 GenerationEditSource

```swift
struct GenerationEditSource: Equatable {
    var projectItemID: UUID
    var filePath: String
    var originalPrompt: String
    var maskFilePath: String?
    var compositeFilePath: String?
    var inpaintPurpose: InpaintPurpose   // .edit / .remove
    
    var isInpainting: Bool { maskFilePath != nil }
}
```

### 6.6 FilteringProject

```swift
struct FilteringProject: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var searchQuery: String
    let createdAt: Date
    var updatedAt: Date
}
```

### 6.7 SidebarSelection

```swift
enum SidebarSelection: Codable, Equatable, Hashable {
    case project(UUID)
    case filtering(UUID)
    case allImages
    case search          // 永続化されない（起動時は .none にフォールバック）
    case none
}
```

### 6.8 ProjectStore.Snapshot

永続化の単位。`projects.json` への JSON エンコード/デコードに使用。

```swift
struct Snapshot: Codable {
    var projects: [Project]
    var items: [ProjectItem]
    var filteringProjects: [FilteringProject]
    var sidebarSelection: SidebarSelection
    var expandedSections: [String: Bool]
}
```

### 6.9 CodexModel

```swift
struct CodexModel: Identifiable, Equatable {
    let id: String
    let displayName: String
    let supportedReasoningEfforts: [String]
    let defaultReasoningEffort: String
    let isDefault: Bool
    let rating: ModelRating?
}

struct ModelRating: Equatable {
    let cost: String    // "low" | "mid" | "high"
    let smart: String
    let speed: String
}
```

既知のモデル評価:

| displayName | cost | smart | speed |
|-------------|------|-------|-------|
| GPT-5.5 | high | high | high |
| gpt-5.4 | mid | high | high |
| GPT-5.4-Mini | low | mid | high |
| gpt-5.3-codex | low | mid | high |
| gpt-5.2 | low | low | mid |

### 6.10 CodexAccountUsageStatus

```swift
struct CodexAccountUsageStatus: Equatable {
    var accountLabel: String
    var planLabel: String
    var primaryUsageLabel: String      // 5時間ウィンドウ
    var secondaryUsageLabel: String    // 週次ウィンドウ
    var primaryUsageRemainingFraction: Double?
    var secondaryUsageRemainingFraction: Double?
    var accountEmail: String?
    var accountKind: AccountKind       // .chatgpt / .apiKey / .amazonBedrock / .unauthenticated / .unknown
    var primaryResetText: String?      // 「あと3時間」等の相対表示文字列
    var secondaryResetText: String?
    var primaryResetDate: Date?
    var secondaryResetDate: Date?
}
```

### 6.11 ExportSettings

```swift
struct ExportSettings: Equatable {
    var format: ExportFormat             // .png / .jpeg / .svg
    var jpegQuality: JPEGQualityPreset   // .high98 / .mid80 / .low60
    var pngOptimize: Bool
    var pngLevel: PNGOptimizationLevel   // .fast / .max（ロッシー）
    var resizeEnabled: Bool
    var resizeWidth: Int
    var resizeHeight: Int
}
```

### 6.12 EntitlementStatus

```swift
enum EntitlementStatus: Equatable {
    case trial(daysLeft: Int)
    case licensed
    case expired
}
```

### 6.13 RateLimitConfirmation

レート制限到達時にユーザーへ並行数縮減を提案するための情報構造体。`GenerationCoordinator` から生成され、UI に渡される。

```swift
struct RateLimitConfirmation: Identifiable {
    let id: UUID
    let remainingPercent: Int   // 残クォータ比率（0〜100）
    let concurrency: Int        // 縮減後の推奨並行数
    let resume: () -> Void      // 承認時に呼び出すクロージャ
}
```

---

## 7. 外部依存

### 7.1 Codex App Server

**起動:**

```bash
# codex バイナリが存在する場合
{node} {codex} app-server --listen stdio://

# PATH 上の場合
/usr/bin/env codex app-server --listen stdio://
```

`CodexAppServerClient` が `Process` でサブプロセスを起動し、stdin/stdout を JSON-RPC チャンネルとして使用します。

**JSON-RPC メソッド（主要）:**

| メソッド | 方向 | 用途 |
|---------|------|------|
| `initialize` | → | 起動・ネゴシエーション（`clientInfo.name = "draftcanvas"`、`capabilities.experimentalApi: true`） |
| `thread/start` | → | 新しい会話スレッドを開始。model と reasoningEffort を渡す。threadID を返す |
| `turn/start` | → | threadID・プロンプト・参照画像パスを渡して画像生成を実行 |
| `model/list` | → | 利用可能モデル一覧を取得 |
| `account/read` | → | アカウント種別・プラン情報を取得 |
| `account/rateLimits/read` | → | 5時間・週次のレート制限情報を取得 |
| `account/logout` | → | ログアウト |

**接続管理:**

- 起動は遅延（初回生成・アカウント確認時に `start()` を呼ぶ）
- `startupTask` によって同時に複数回 `start()` が呼ばれても 1 回だけ起動
- `DispatchQueue` ベースのスレッドセーフ設計

### 7.2 vtracer-ffi（SVG ベクター化）

Swift から C 関数インターフェースで呼び出します。

- ライブラリ: `vtracer-ffi/` ディレクトリ（Rust FFI）
- ブリッジヘッダ: `DraftCanvas-Bridging-Header.h`
- 主要関数: `vtracer_convert(ptr, len, params, outPtr, outLen)` / `vtracer_free(ptr, len)`
- 変換は `Task.detached(priority: .userInitiated)` でバックグラウンド実行

### 7.3 pngquant / oxipng（PNG 最適化）

バイナリは `DraftCanvas/Resources/bin/` に同梱（arm64 + x86_64 fat バイナリ）。

| ツール | バージョン | 動作 |
|-------|-----------|------|
| pngquant | 3.0.4 | ロッシー PNG 圧縮（`PNGOptimizationLevel.max` 時） |
| oxipng | 10.1.1 | ロスレス PNG 最適化（`PNGOptimizationLevel.fast` 時） |

動的依存は `/usr/lib/` のみ（libz, libiconv, libSystem）。追加インストール不要。
`BinaryRunner` 経由でサブプロセスとして実行します。

### 7.4 Sparkle（自動更新）

`SparkleUpdaterController` が `SPUStandardUpdaterController` をラップし、アプリメニューから「アップデートを確認…」を実行できます。

### 7.5 Apple Vision（背景除去）

`BackgroundRemover.swift` が `VNGenerateForegroundInstanceMaskRequest` を使用してオフラインで背景を除去します。ネットワーク接続不要。画像データは端末の外に出ません。

### 7.6 UserNotifications

生成完了時にシステム通知を送信。許可は `requestNotificationPermission()` で起動時に要求。

---

## 8. 永続化レイアウト

### 8.1 アプリサポートディレクトリ

```
~/Library/Application Support/Draft Canvas/
├── projects.json          # メタデータ（ProjectStore.Snapshot）
├── items/
│   ├── {itemID}.png       # 生成・インポートした画像
│   ├── {itemID}.jpg       # JPEG でインポートした場合
│   └── {itemID}.svg       # ベクター化済み SVG
├── masks/
│   ├── {itemID}_mask.png      # インペイント用マスク
│   └── {itemID}_composite.png # マスク合成済み画像（Codex への参照画像）
└── attachments/
    └── {attachmentID}.png  # 添付画像（一時的）
```

旧アプリ名 `Image Creator` からのデータ移行は `CanvasImport` で対応しています。

### 8.2 UserDefaults

| キー | 型 | 説明 |
|-----|----|------|
| `appAppearance` | String | `"light"` / `"dark"` |
| `appLanguage` | String | `"ja"` / `"en"` / `"system"`（OS設定追従） |
| `canvasSortOrder` | String | `CanvasSortOrder` rawValue |
| `completionSound` | String | `CompletionSoundOption` rawValue |
| `totalGeneratedImages` | Int | 累計生成枚数 |
| `session5hCount` | Int | 5時間ウィンドウのセッション内カウント |
| `sessionWeeklyCount` | Int | 週次ウィンドウのセッション内カウント |
| `session5hResetEpoch` | Double | 5時間ウィンドウのリセット epoch |
| `sessionWeeklyResetEpoch` | Double | 週次ウィンドウのリセット epoch |
| `exportFormat` | String | `ExportFormat` rawValue |
| `exportJPEGQuality` | Int | `JPEGQualityPreset` rawValue |
| `exportPNGOptimize` | Bool | PNG 最適化の有効/無効 |
| `exportPNGLevel` | Int | `PNGOptimizationLevel` rawValue |
| `exportResizeEnabled` | Bool | リサイズの有効/無効 |
| `exportResizeWidth` | Int | リサイズ幅 |
| `exportResizeHeight` | Int | リサイズ高さ |
| `preferredSaveFolderBookmark` | Data | Security-Scoped Bookmark |
| `lastTrialWarningDaysLeft` | Int | 直近のトライアル残日数警告で表示した値 |

### 8.3 Keychain

| アカウント | 内容 |
|-----------|------|
| `licenseKey` | Lemon Squeezy ライセンスキー |
| `instanceID` | アクティベーション時に取得したインスタンス ID |

---

## 9. ビルド・配布

### 9.1 ビルドコマンド

```bash
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build
```

**ルール:**

- `SYMROOT` は常に `_build`、`OBJROOT` は常に `_build/obj`
- `-derivedDataPath` は使用しない
- 上記以外のパスにビルド成果物を作成した場合は即削除する

### 9.2 成果物

```
_build/Debug/DraftCanvas.app
```

### 9.3 外部バイナリ管理（pngquant / oxipng）

**現在（フェーズ1）:** バイナリを git で直接管理

```bash
# 初回: リポジトリに fat バイナリが含まれているのでビルドのみ
xcodebuild ...
```

**将来（フェーズ2）:** GitHub Releases + CI/CD へ移行

- バイナリを `.gitignore` に追加
- GitHub Release アセットにアップロード
- `scripts/fetch-tools.sh` でダウンロード
- GitHub Actions で署名・Notarize・DMG 生成

**バイナリ更新手順（フェーズ1）:**

```bash
# oxipng
cargo install oxipng --root /tmp/oxipng-arm64 --target aarch64-apple-darwin
cargo install oxipng --root /tmp/oxipng-x86  --target x86_64-apple-darwin
lipo -create /tmp/oxipng-arm64/bin/oxipng /tmp/oxipng-x86/bin/oxipng \
     -output DraftCanvas/Resources/bin/oxipng

# pngquant
git clone --depth 1 https://github.com/kornelski/pngquant.git /tmp/pngquant
cd /tmp/pngquant && git submodule update --init
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
lipo -create target/aarch64-apple-darwin/release/pngquant \
             target/x86_64-apple-darwin/release/pngquant \
     -output /path/to/repo/DraftCanvas/Resources/bin/pngquant

chmod +x DraftCanvas/Resources/bin/oxipng DraftCanvas/Resources/bin/pngquant
```

---

## 10. ローカライズ

対応言語: **日本語（ja）** / **英語（en）**

`LocalizationManager.shared` がアプリ全体の言語を管理します。OS の言語設定から初期言語を選択し、アプリ内設定から変更できます。設定は `UserDefaults` の `appLanguage` キーに保存。

翻訳文字列は `DraftCanvas/Localization/Localizable.xcstrings` で一元管理されています。

UI 文字列は `String(localized:)` を直接利用します。

`AppLanguage` は `ja` / `en` / `system`（OS設定追従）の 3 ケースを持ちます。`SettingsView` から変更でき、`UserDefaults` の `appLanguage` キーに保存されます。

---

## 11. 参考資料

| 資料 | パス |
|------|------|
| プロジェクト設定（Claude Code 用） | `CLAUDE.md` |
| エージェントルール | `AGENTS.md` |
| ランディングページ | `lp/index.html` |
| プライバシーポリシー（全文） | `lp/privacy.html` |
| 利用規約（全文） | `lp/terms.html` |
| 外部バイナリ管理ワークフロー | `_docs/external-binaries-workflow.md` |
| 画像生成モデル調査（2026-05-09） | `_docs/画像生成モデル調査_2026-05-09.md` |
| ドメインモデル実装 | `DraftCanvas/Models.swift` |
| 生成ロジック | `DraftCanvas/GenerationCoordinator.swift` |
| Codex 通信クライアント | `DraftCanvas/CodexAppServerClient.swift` |
| ViewModel（メイン） | `DraftCanvas/DraftCanvasViewModel.swift` |
| ViewModel 拡張 | `DraftCanvas/ViewModel/` |
| View 実装 | `DraftCanvas/Views/` |
| ライセンス実装 | `DraftCanvas/License/` |
| エクスポート実装 | `DraftCanvas/Export/` |
