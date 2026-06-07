# Draft Canvas — フル仕様書

> 対象読者: ユーザー（機能・対応環境・ライセンス）および開発者（アーキテクチャ・ドメインモデル・外部依存・ビルド）
>
> 更新: 2026-06-02  
> ブランチ: dev

---

## 目次

1. [概要](#1-概要)
2. [ユーザー向け機能仕様](#2-ユーザー向け機能仕様)
   - 2.10 [設定変更時の再起動](#210-設定変更時の再起動)
   - 2.11 [終了時タスク保護](#211-終了時タスク保護)
   - 2.12 [ラフ描画（Sketch）](#212-ラフ描画sketch)
   - 2.13 [Aurora アニメーション（生成中プレースホルダ）](#213-aurora-アニメーション生成中プレースホルダ)
   - 2.14 [プロンプトテンプレート](#214-プロンプトテンプレート)
   - 2.15 [プロンプト履歴](#215-プロンプト履歴)
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
| インターネット | 画像生成・アカウント認証に必要。背景除去・ベクター化はオフラインで動作 |
| 対応アカウント | ChatGPT Plus 以上のサブスクリプション（Free プラン・OpenAI API Key・Amazon Bedrock は未サポート） |

---

## 2. ユーザー向け機能仕様

### 2.1 AI 画像生成

プロンプトテキストを入力し、Codex App Server 経由で gpt-image を呼び出して画像を生成します。

**パラメータ:**

- **プロンプト**: 自由テキスト（日本語・英語どちらも対応）
- **生成指示の言語**: 設定画面「生成指示を英語に翻訳」Toggle で制御。デフォルト `false`（入力言語維持）。オン時のみ画像生成ブリーフを英語に正規化してから Codex に渡す。`@AppStorage("translateToEnglish")` Bool で永続化
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
- **モデル選択**: 利用可能モデルは Codex App Server の `model/list` から動的取得
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

Draft Canvas は画像生成の実行を Codex App Server に完全委任します。利用可能なモデル一覧・画像品質・解像度・処理能力はすべて **インストールされている Codex のバージョン**に依存します。Draft Canvas 自体のアップデートとは独立しており、Codex を更新するだけで使えるモデルや生成品質が変わる可能性があります。Draft Canvas 側が制御できるのはプロンプト・`reasoningEffort`・モデル選択のみです。

**サポート対象アカウント:**

Draft Canvas は ChatGPT サブスクリプション（Plus 以上）専用です。OpenAI API Key・Amazon Bedrock は未サポートです。

| accountKind | 対応状況 |
|-------------|---------|
| `.chatgpt` + Plus 以上 | 対応（全機能利用可） |
| `.chatgpt` + Free | 未対応（画像生成ブロック） |
| `.apiKey` | 未サポート（AccountPopover に警告表示） |
| `.amazonBedrock` | 未サポート（AccountPopover に警告表示） |
| `.unauthenticated` / `.unknown` | 未ログイン扱い |

**ChatGPT Free プラン制限:**

`accountKind == .chatgpt` かつ `planLabel.lowercased() == "free"` のとき生成をブロックします（`CodexAccountUsageStatus.isChatGPTFreePlan`）。`startGeneration()` 冒頭で判定し `pendingFreeAccountBlock = true` で早期 return。

UI 表示 3 箇所:

- PromptPanel 上部の常駐警告バー（`exclamationmark.triangle.fill` オレンジ）
- 生成試行時の `confirmationDialog`（タイトル + メッセージ、OK のみ）
- `AccountPopover` 内の警告キャプション

アップグレード CTA リンクなし、テキスト案内のみ。

**API Key / Bedrock 構成:**

`isUnsupportedAccountKind` (`accountKind == .apiKey || .amazonBedrock`) が `true` のとき、AccountPopover に警告キャプションを表示し ChatGPT ログインへ誘導します。生成ブロックは行いません（Codex CLI 側が実行を管理するため）。

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

**アウトペイント（Outpaint）:**

画像の外側を AI で拡張し、既存のシーンを自然に継続させます。

1. 画像をクリックして選択 → キャンバス左側のアクションパネルから「アウトペイント」をクリック
2. `OutpaintEditorSheet` が開き、上下左右の拡張量（`OutpaintInsets`）をスライダーで指定
3. 2つの実行方法を選択:
   - **「拡張して生成」**: 元のプロンプト + `reasoningEffort: "low"` で即時生成
   - **「プロンプト入力して拡張」**: エディタを閉じてプロンプトパネルに戻り、カスタムプロンプトで生成

内部処理: `OutpaintCompositor` が元画像を拡張キャンバスの中央に配置し、透明領域を持つ composite 画像と白黒マスク（白=生成領域、黒=保持領域）の 2 枚を生成。最大拡張サイズは 2048px。`InpaintPurpose.outpaint` として既存のインペイントパイプラインを再利用します。


**関連ファイル:** `Editors/Outpaint/OutpaintEditorSheet.swift` / `Editors/Outpaint/OutpaintInsets.swift` / `OutpaintCompositor.swift` / `ViewModel/DraftCanvasViewModel+Outpaint.swift`

**生成失敗の分類:**

生成ジョブが失敗した場合、`GenerationJob.failureKind: GenerationFailureKind?` に原因を格納します。

| 種別 | 表示アイコン | 意味 |
|------|------------|------|
| `.rateLimited` | `bolt.slash` | API クォータ超過・並列失敗 |
| `.timeout` | `clock.badge.exclamationmark` | タイムアウト（`DraftCanvasError.timeout`）|
| `.other` | `exclamationmark.triangle` | その他エラー |

### 2.3 プロンプト強化

「✨ 強化」ボタン（PromptPanel）を押すと、入力中のプロンプトを AI が自動的に詳細化します。

- 設定の「生成指示を英語に翻訳」がオンなら英語出力、オフなら入力言語維持
- 構図・色彩・照明・雰囲気・テクスチャ・視点・アートスタイルの詳細を追加
- 元の主題・意図を変えず 2〜4 文に拡張
- Codex に新しいスレッドを開いて強化プロンプトを取得（非同期、排他制御あり）

### 2.4 後処理機能

後処理は
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
| アクションパネル | 画像をクリックして選択するとキャンバス左側に縦並びのアクションボタンが表示（`canvasActionPanel`）。再編集・マスク編集・除去・アウトペイント・背景除去・素材分離・高解像度化・ベクター化・複製・Finder表示・削除・エクスポート（`isAccent: true` で塗りアクセント強調、最下段配置） |
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
| WebP | `cwebp` バイナリ経由。品質: 高(90) / 中(75) / 低(50)。メタデータ自動削除 |
| SVG | ベクター化済みアイテムのみ選択可能 |
| TIFF | LZW 圧縮（可逆・アルファ保持）。DPI 埋め込み |
| PDF | 1 ページ PDF。圧縮: lossless（Flate）/ jpegHigh(q=0.9) / jpegMedium(q=0.7) |

**DPI:**

TIFF / PDF でのみ `ExportDPI`（72 / 150 / 300 / 600）を指定可能。デフォルト 300 dpi。`TIFFXResolution` / `TIFFYResolution` および PDF MediaBox（`px / dpi * 72`）に反映。

**関連ファイル:**

`Export/TIFFEncoder.swift` / `Export/PDFEncoder.swift` / `Export/WebPEncoder.swift` / `Export/ExportSettings.swift` / `Export/ExportOptionsSheet.swift` / `Export/ExportOptionsViewModel.swift`

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

5時間ウィンドウと週次ウィンドウの使用量ピル（`usagePill`）が TopBar に表示されます。**表示は `shouldShowUsagePills == true`（`accountKind == .chatgpt`）のときのみ**。API Key・Bedrock・未ログイン時は非表示。各ピルには `prefix`（「5h」または「weekly」）・⚡・`percentLabel`（残量%、未取得時「-」）・残量プログレスバー・`resetText` が並びます。アイコンは廃止されました。データ型: `primaryUsagePrefix` / `primaryUsagePercentLabel`（secondary も同様）。

TopBar のアカウントボタンはアカウント状態によりアイコンが変化します（認証済: `person.crop.circle` / 未認証: `person.crop.circle.badge.minus` / 取得失敗: `person.crop.circle.badge.exclamationmark`）。クリックすると詳細ポップオーバーが開き、以下を確認できます:

**認証済み:**
- メールアドレス + プラン表示（`planDisplay`。例: "ChatGPT Plus"）
- `arrow.clockwise` アカウント再取得ボタン（Codex app-server を再起動して情報を再取得）
- フッタに Codex バージョン
- ChatGPT Free プランの場合は警告キャプション表示

**未認証:**
- 「未ログイン」 + `codex login` 実行ガイダンス
- 取得失敗時は「再試行」ボタン

TopBar のリフレッシュボタン（アカウント使用量更新）は生成中（`!generatingProjectIDs.isEmpty`）は disabled になります。

生成枚数は PromptPanel で選択。サイドバーの「すべての画像」行にはアイテム総数の Capsule が表示されます（`AllImagesRow`）。

カウンタはセッション内でも追跡され、AppStorage に永続化されます（`session5hCount`、`sessionWeeklyCount`）。

### 2.10 設定変更時の再起動

アプリの表示言語を変更した場合のみ、Draft Canvas の再起動が必要です。

**再起動実装:**

`LocalizationManager.relaunch()` が `NSWorkspace.shared.openApplication(at:configuration:)` + `createsNewApplicationInstance = true` で新インスタンスを起動後、`NSApp.terminate(nil)` で終了します。

**SettingsView の再起動アラート:**

| 状態 | ボタン | 挙動 |
|------|--------|------|
| 進行中作業なし | 「再起動」 | 即座に relaunch |
| `hasInFlightWork == true` | 「中断して再起動」(destructive) | `cancelInFlightWorkForRelaunch()` 後に relaunch |

`hasInFlightWork`: `generatingProjectIDs` / `vectorizingItemIDs` / `upscalingItemIDs` / `isEnhancingPrompt` / `importProgress` / `batchExportProgress` / `exportingProjectID` / `backgroundRemovalPreview` / `materialExtractionPreview` / `upscalePreview` / `inpaintingTarget` を集約判定。

`cancelInFlightWorkForRelaunch()`: 全 Task を `cancel()` → 進行フラグ全リセット → `saveState()`。

**Task 追跡辞書（生成）:** `generationTasks: [UUID(projectID): [UUID(runID): Task<Void, Never>]]`（ネスト辞書化）。`vectorizationTasks` / `upscalingTasks` は `[UUID: Task<Void, Never>]` のまま。各 Task は完了時に `defer` で辞書から自身を削除。

`finishRun(runID:projectID:results:)` / `cancelProjectRuns(projectID:)` で並列実行を一元管理。生成中の停止ボタンは `cancelProjectRuns(projectID:)` を呼ぶ（旧ラベル「全停止」→「停止」）。

**スケッチエディタと `hasInFlightWork`:** スケッチエディタ編集中は `hasInFlightWork` に含まれない。言語変更による再起動ダイアログを表示しても、スケッチエディタは自動的には閉じない（UI 側の警告なし）。

### 2.11 終了時タスク保護

進行中の作業がある状態でアプリを終了しようとすると、確認ダイアログを表示して処理を保護します（`AppDelegate.applicationShouldTerminate`）。

**保護対象（`hasProtectedInFlightWork`）:**

- `generatingProjectIDs` が空でない（画像生成中）
- `exportingProjectID != nil`（エクスポート中）
- `batchExportProgress != nil`（バッチエクスポート中）

**終了フロー:**

1. 保護対象なし → `.terminateNow`（即座に終了）
2. 保護対象あり → `terminationRequested = true` をセット → `.terminateLater`（UIで確認待ち）
3. ユーザーが「終了する」→ `confirmTermination()` → 進行中タスクキャンセル → `reply(toApplicationShouldTerminate: true)`
4. ユーザーが「キャンセル」→ `cancelTermination()` → `reply(toApplicationShouldTerminate: false)`

**終了時クリーンアップ（`applicationWillTerminate`）:** `saveState()` + `stopServer()` を実行。

> `hasProtectedInFlightWork` はエクスポートも含むが、§2.10 の再起動用 `hasInFlightWork` はベクター化・アップスケール・インペイント等も含む別プロパティ。

### 2.12 ラフ描画（Sketch）

プロンプトパネル下部の `scribble.variable` ボタンから NSView ベースのスケッチエディタを開き、白背景に手描きしたラフを `AttachmentKind.sketch` の参照画像として生成に渡します。再編集中（`editSource != nil`）は disabled。

**スケッチエディタ仕様（`SketchEditor.swift`）:**

| 機能 | 詳細 |
|------|------|
| ブラシ径 | 5〜80px スライダー。`[` / `]` キーで変更 |
| 色プリセット | 黒・赤・青・緑・紫（`CodableColor.presets`）。`1`〜`5` キーで切替 |
| 消しゴム | ツールバーボタン または `e` キー |
| Undo / Redo | ⌘Z / ⌘⇧Z |
| Clear | 確認ダイアログあり |
| キャンセル / 完了 | Esc / ⌘Return |
| ズーム / パン | ピンチ / スクロール |
| 最小ウィンドウ | 800×620 |
| 背景 | チェッカーボード |

**レンダリング（`SketchCompositor.swift`）:**

`SketchCompositor.renderPNG` が白背景に円を補間描画して PNG 化。長辺 1024px 固定。`aspectRatio` から `canvasPixelSize` を算出（`DraftCanvasViewModel+Sketch.swift`: `openSketchEditor()`）。

**永続化:**

| ファイル | パス | 内容 |
|---------|------|------|
| 添付 PNG | `attachments/<id>_sketch.png` | エディタ出力画像 |
| ストローク JSON | `attachments/<id>_strokes.json` | ストロークデータ（再編集用） |
| 生成後参照 | `masks/<itemID>_sketch.png` | `ProjectStore.saveSketchSource` で保存。`ProjectItem.sketchSourcePath` に反映 |

`cleanupMaskFiles` で `<id>_sketch.png` も削除対象。

**ViewModel API（`ViewModel/DraftCanvasViewModel+Sketch.swift`）:**

- `openSketchEditor()` — `aspectRatio` から `canvasPixelSize` 算出してシート起動
- `openSketchEditorForReedit(_:)` — 既存ストロークをロードして再編集
- `applySketch(strokes:canvasPixelSize:existingID:)` — PNG レンダリング → 保存 → 添付反映
- `loadSketchStrokes(for:)` — ストローク JSON 復元

**UI:**

- プロンプト折りたたみ時: sketch 添付中は `scribble.variable` アイコン表示
- `ItemDetailPopover`: 「ラフ」セクション（120px 高）で生成時の参照ラフを表示

**ライセンスゲート:** なし（添付画像と同等扱い）。

### 2.13 生成中プレースホルダアニメーション

`GenerationProgressView` 内 `PlaceholderAnimationView(style:seed:)` が生成中ジョブのプレースホルダとして表示されます。表示スタイルは設定画面の「アニメーション」で選択でき、`ランダム` は生成ジョブの `seed` を使って具体スタイルを振り分けます。

**スタイル:**

| スタイル | View |
|----------|------|
| オーロラ | `AuroraPlaceholderView` |
| グリッドウェーブ | `GridWavePlaceholderView` |
| ワイヤーフレーム | `WireframeRotationPlaceholderView` |
| パーティクル | `ParticleFlowPlaceholderView` |
| スキャンライン | `ScanlineSweepPlaceholderView` |
| モザイク | `MosaicPulsePlaceholderView` |

**Reduce Motion（`@Environment(\.accessibilityReduceMotion)`）:**

| 状態 | 動作 |
|------|------|
| ON | `TimelineView` を使わず `t=0` の静止フレーム + `ProgressView()` オーバーレイ |
| OFF | 30fps `TimelineView(.animation)` でアニメーション |

### 2.14 プロンプトテンプレート

プロンプト入力を補助するテンプレート機能。PromptPanel からテンプレートパネル（`PromptTemplatePanel`）を開いて選択すると、テンプレートのテキストがプロンプトに挿入されます。

**カテゴリ（`PromptTemplateCategory`）:**

| カテゴリ | 説明 | テンプレート数 |
|---------|------|-------------|
| `.style`（画風・スタイル） | 水彩画風・油絵風・ピクセルアート等 | 10 |
| `.photo`（写真・カメラ） | ポートレート・マクロ・ゴールデンアワー等 | 10 |
| `.lighting`（ライティング・雰囲気） | シネマティック・ネオン・ムーディー等 | 10 |
| `.user`（マイテンプレート） | ユーザーが作成したカスタムテンプレート | 可変 |

**パネル UI:**

- ビルトインカテゴリ: 4列サムネイルグリッド（`LazyVGrid`）で表示。各テンプレートにサムネイル画像（`template-{category}-{番号}`）
- マイテンプレート: リスト表示。作成・編集・削除が可能

**永続化:** ユーザーテンプレート（`isBuiltIn == false`）のみ `prompt_templates.json` に保存（`PromptTemplateStore`）。ビルトインテンプレートはコードに定義（`PromptTemplate.builtIns`）。

**関連ファイル:** `Models/PromptTemplate.swift` / `Stores/PromptTemplateStore.swift` / `Views/PromptTemplatePanel.swift` / `ViewModel/DraftCanvasViewModel+Templates.swift`

### 2.15 プロンプト履歴

過去に使用したプロンプトを記録し、再利用できる機能。PromptPanel から履歴パネル（`PromptHistoryPanel`）を開いて選択すると、プロンプトテキストが復元されます。

**データモデル（`PromptHistoryEntry`）:**

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `id` | `UUID` | 識別子 |
| `promptText` | `String` | プロンプト本文 |
| `useCount` | `Int` | 使用回数 |
| `lastUsedAt` | `Date` | 最終使用日時 |

**パネル UI:** カード形式で表示。ホバー時に削除ボタン、「適用」ボタンでプロンプトに反映。2件以上の場合「全削除」ボタン表示。

**永続化:** `prompt_history.json` に保存（`PromptHistoryStore`）。

**関連ファイル:** `Models/PromptHistoryEntry.swift` / `Stores/PromptHistoryStore.swift` / `Views/PromptHistoryPanel.swift` / `ViewModel/DraftCanvasViewModel+History.swift`

---

## 3. ライセンス

Draft Canvas はオープンソース (MIT License) で無料です。全機能を制限なく利用できます。

| 項目 | 内容 |
|------|------|
| ライセンス | MIT |
| 価格 | 無料 |
| 商用利用 | 可 |
| スポンサー | [GitHub Sponsors](https://github.com/sponsors/5umm3r) / [Polar](https://polar.sh/spade3) |

---

## 4. プライバシー・利用規約

### 4.1 収集データ

| データ | 収集方法 | 保存場所 |
|-------|---------|---------|
| クラッシュレポート | Apple の標準クラッシュレポート機能 | Apple サーバー |

### 4.2 第三者提供

画像データ・プロンプトの内容は Codex App Server 経由で OpenAI に送信されます。ChatGPT アカウントのプライバシーポリシーが適用されます。

### 4.3 利用規約要点

| 項目 | 内容 |
|------|------|
| 個人利用 | 可 |
| 商用利用 | 可 |
| 再配布・改変 | MIT License に準拠 |
| 保証 | 現状有姿提供、免責 |

---

## 5. アーキテクチャ

### 5.1 全体図

```
DraftCanvasApp.swift
├── DraftCanvasViewModel (@MainActor ObservableObject)
│   ├── ViewModel/DraftCanvasViewModel+Account.swift      — Codexアカウント・使用量
│   ├── ViewModel/DraftCanvasViewModel+Attachments.swift  — 添付画像管理
│   ├── ViewModel/DraftCanvasViewModel+CanvasImport.swift — 画像インポート
│   ├── ViewModel/DraftCanvasViewModel+CanvasNavigation.swift — キャンバスナビゲーション
│   ├── ViewModel/DraftCanvasViewModel+Computed.swift     — 派生プロパティ
│   ├── ViewModel/DraftCanvasViewModel+Crop.swift         — クロップ
│   ├── ViewModel/DraftCanvasViewModel+Export.swift       — エクスポート
│   ├── ViewModel/DraftCanvasViewModel+FilteringProjects.swift — フィルタリングPJ
│   ├── ViewModel/DraftCanvasViewModel+Generation.swift   — 生成ループ
│   ├── ViewModel/DraftCanvasViewModel+History.swift      — プロンプト履歴
│   ├── ViewModel/DraftCanvasViewModel+ItemActions.swift  — アイテム操作
│   ├── ViewModel/DraftCanvasViewModel+Items.swift        — アイテムCRUD
│   ├── ViewModel/DraftCanvasViewModel+MaterialExtract.swift — マテリアル抽出
│   ├── ViewModel/DraftCanvasViewModel+Outpaint.swift     — アウトペイント
│   ├── ViewModel/DraftCanvasViewModel+Projects.swift     — プロジェクトCRUD
│   ├── ViewModel/DraftCanvasViewModel+PromptEnhance.swift — プロンプト強化
│   ├── ViewModel/DraftCanvasViewModel+Sketch.swift       — ラフ描画
│   ├── ViewModel/DraftCanvasViewModel+Templates.swift    — プロンプトテンプレート
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
├── LocalizationManager (言語切り替え)
└── SparkleUpdaterController (自動更新)
```

### 5.2 画面構成

メインウィンドウは 3ペイン構成です。

```
┌─────────────────────────────────────────────────────────────────┐
│  TopBar (ContentView+TopBar.swift)                              │
│  [アカウント使用量] [ログ] [設定] [ソート] [アカウント]              │
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

> OSS クレジットはアプリ標準の About パネル（`Credits.rtf`）で提供。`scripts/generate-credits.py` で `Resources/Licenses/*.txt` から再生成。

モーダルシート: `TrialExpiredView` / `LicenseSheet` / `BackgroundRemovalPreviewSheet` / `UpscalePreviewSheet` / `VectorizingOverlay` / `MaterialExtractionSheet` / `InpaintingMaskEditor` / `OutpaintEditorSheet` / `ExpandedImageSheet` / `ExportOptionsSheet` / `FilteringProjectCreationSheet`

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
| エクスポート設定 | `Export/ExportSettings.swift`, `Export/ExportOptionsViewModel.swift` |
| 画像エンコード | `Export/ImageEncoder.swift`, `Export/TIFFEncoder.swift`, `Export/PDFEncoder.swift` |
| バイナリ実行 | `Export/BinaryRunner.swift`（pngquant / oxipng） |
| 言語管理 | `Localization/LocalizationManager.swift` |
| サムネイル | `CanvasThumbnailStore.swift` |
| 元画像ストア | `CanvasOriginalImageStore.swift` |
| CanvasMetrics | `CanvasMetrics.swift` |
| OSS クレジット | `Resources/Credits.rtf`（`scripts/generate-credits.py` で再生成） |
| Sketch エディタ | `SketchEditor.swift`, `SketchCompositor.swift`, `SketchModels.swift`, `ViewModel/DraftCanvasViewModel+Sketch.swift` |
| アウトペイント | `Editors/Outpaint/OutpaintEditorSheet.swift`, `Editors/Outpaint/OutpaintInsets.swift`, `OutpaintCompositor.swift`, `ViewModel/DraftCanvasViewModel+Outpaint.swift` |
| プロンプトテンプレート | `Models/PromptTemplate.swift`, `Stores/PromptTemplateStore.swift`, `Views/PromptTemplatePanel.swift`, `ViewModel/DraftCanvasViewModel+Templates.swift` |
| プロンプト履歴 | `Models/PromptHistoryEntry.swift`, `Stores/PromptHistoryStore.swift`, `Views/PromptHistoryPanel.swift`, `ViewModel/DraftCanvasViewModel+History.swift` |
| 生成プレースホルダ | `Views/PlaceholderAnimationView.swift`, `Views/GenerationProgressView.swift` |

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
    let isCropped: Bool
    let isImported: Bool
    var tags: [String]
    var sketchSourcePath: String?   // 生成時の参照ラフ（masks/<id>_sketch.png の相対パス）
    let modelName: String?          // 生成に使用したモデルの表示名
    let reasoningEffort: String?    // 生成時の推論強度
    let generationDuration: TimeInterval?  // 生成所要時間（秒）
}
```

生成メタデータ（`modelName` / `reasoningEffort` / `generationDuration`）は生成完了時に記録され、`ItemDetailPopover` で確認できます。

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
    var isFreeAccountBlocked: Bool   // Free プランによるブロック
    var failureKind: GenerationFailureKind?  // 失敗原因の分類
    var runID: UUID?                 // 所属する生成ランの ID
    var scheduledAt: Date            // ジョブキュー投入時刻
}
```

完了・失敗したジョブは即座に `jobsByProject` から削除されます（`removeJob(id:from:)`）。生成開始時に `cleanupStaleJobs(for:)` がアクティブでない run に属する孤立ジョブを一括除去します。

### 6.4 GenerationRequest

```swift
struct GenerationRequest: Equatable {
    var prompt: String
    var count: Int               // UI 上限: 4。normalizedCount で 1〜24 にクランプ（サーバー側バリデーション）
    var concurrency: Int         // 正規化後: 1〜count
    var aspectRatio: GenerationAspectRatio
    var editSource: GenerationEditSource?
    var attachedImagePath: String?
    var attachedImageKind: AttachmentKind  // 添付画像の種別（.regular / .sketch）
    var model: String
    var reasoningEffort: String
    var translateToEnglish: Bool // 生成前に英語に翻訳するか
    var normalizedPrompt: String?  // 翻訳済みプロンプトのキャッシュ
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
    var inpaintPurpose: InpaintPurpose   // .edit / .remove / .outpaint
    
    var isInpainting: Bool { maskFilePath != nil }
    var isOutpainting: Bool { inpaintPurpose == .outpaint && maskFilePath != nil }
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
}
```

利用可能なモデル一覧は Codex App Server の `model/list` から動的に取得されます。モデル評価（`ModelRating`）は廃止されました。

### 6.10 CodexAccountUsageStatus

```swift
struct CodexAccountUsageStatus: Equatable {
    var accountLabel: String
    var planLabel: String
    var primaryUsagePrefix: String       // 5時間ウィンドウ識別子（"5h"）
    var primaryUsagePercentLabel: String // 残量パーセント表示（"-" または "XX%"）
    var secondaryUsagePrefix: String     // 週次ウィンドウ識別子（"weekly"）
    var secondaryUsagePercentLabel: String
    var primaryUsageRemainingFraction: Double?
    var secondaryUsageRemainingFraction: Double?
    var accountEmail: String?
    var accountKind: AccountKind         // .chatgpt / .apiKey / .amazonBedrock / .unauthenticated / .unknown
    var primaryResetText: String?        // 「あと3時間」等の相対表示文字列
    var secondaryResetText: String?
    var primaryResetDate: Date?
    var secondaryResetDate: Date?

    var isChatGPTFreePlan: Bool {        // accountKind == .chatgpt && planLabel == "free"
        accountKind == .chatgpt && planLabel.lowercased() == "free"
    }
}
```

### 6.11 ExportSettings

```swift
struct ExportSettings: Equatable {
    var format: ExportFormat             // .png / .jpeg / .webp / .svg / .tiff / .pdf
    var jpegQuality: JPEGQualityPreset   // .high98 / .mid80 / .low60
    var webpQuality: WebPQualityPreset   // .high90 / .mid75 / .low50
    var pngOptimize: Bool
    var pngLevel: PNGOptimizationLevel   // .fast / .max（ロッシー）
    var tiffCompression: TIFFCompression // .lzw（固定）
    var pdfCompression: PDFImageCompression // .lossless / .jpegHigh / .jpegMedium
    var dpi: ExportDPI                   // .dpi72 / .dpi150 / .dpi300 / .dpi600
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

### 6.14 GenerationFailureKind

```swift
enum GenerationFailureKind: String, Codable {
    case rateLimited   // API クォータ超過
    case timeout       // DraftCanvasError.timeout
    case other         // その他
}
```

### 6.15 AttachmentKind / SketchStroke / CodableColor

ソース: `DraftCanvas/SketchModels.swift`

```swift
enum AttachmentKind: String, Codable, Equatable {
    case regular   // 通常の参照画像
    case sketch    // ラフ描画画像
}

struct SketchStroke: Equatable, Codable {
    // ストローク座標・色・径・消しゴムフラグ等
}

struct CodableColor: Equatable, Codable {
    // Codable ラップカラー
    static let presets: [CodableColor]  // 黒・赤・青・緑・紫
}
```

### 6.16 ExportFormat（拡張後）

```swift
enum ExportFormat: String, CaseIterable, Codable {
    case png
    case jpeg
    case webp
    case svg
    case tiff
    case pdf
}

enum WebPQualityPreset: Int, CaseIterable, Codable {
    case high90 = 90
    case mid75 = 75
    case low50 = 50
}
```

### 6.17 ExportDPI / TIFFCompression / PDFImageCompression

ソース: `DraftCanvas/Export/ExportSettings.swift`

```swift
enum ExportDPI: Int, CaseIterable {
    case dpi72 = 72
    case dpi150 = 150
    case dpi300 = 300   // デフォルト
    case dpi600 = 600
}

enum TIFFCompression: String {
    case lzw   // kCGImagePropertyTIFFCompression=5（可逆）
}

enum PDFImageCompression: String {
    case lossless    // CGDataConsumer + Flate（デフォルト）
    case jpegHigh    // JPEG q=0.9
    case jpegMedium  // JPEG q=0.7
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

### 7.3 pngquant / oxipng / cwebp（画像最適化バイナリ）

バイナリは `DraftCanvas/Resources/bin/` に同梱（arm64 + x86_64 fat バイナリ）。

| ツール | バージョン | 動作 |
|-------|-----------|------|
| pngquant | 3.0.4 | ロッシー PNG 圧縮（`PNGOptimizationLevel.max` 時） |
| oxipng | 10.1.1 | ロスレス PNG 最適化（`PNGOptimizationLevel.fast` 時） |
| cwebp | - | WebP エンコード（`WebPEncoder` が `-q` / `-metadata none` で呼び出す。タイムアウト 60秒） |

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
├── prompt_templates.json  # ユーザー作成テンプレート（PromptTemplateStore）
├── prompt_history.json    # プロンプト使用履歴（PromptHistoryStore）
├── items/
│   ├── {itemID}.png       # 生成・インポートした画像
│   ├── {itemID}.jpg       # JPEG でインポートした場合
│   └── {itemID}.svg       # ベクター化済み SVG
├── masks/
│   ├── {itemID}_mask.png      # インペイント用マスク
│   ├── {itemID}_composite.png # マスク合成済み画像（Codex への参照画像）
│   └── {itemID}_sketch.png    # 生成成功時の参照ラフ（ProjectStore.saveSketchSource）
└── attachments/
    ├── {attachmentID}.png         # 通常の添付画像
    ├── {attachmentID}_sketch.png  # Sketch 添付画像（SketchCompositor 出力）
    └── {attachmentID}_strokes.json # ストロークデータ（再編集用）
```

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
| `exportWebPQuality` | Int | `WebPQualityPreset` rawValue |
| `exportPNGOptimize` | Bool | PNG 最適化の有効/無効 |
| `exportPNGLevel` | Int | `PNGOptimizationLevel` rawValue |
| `exportResizeEnabled` | Bool | リサイズの有効/無効 |
| `exportResizeWidth` | Int | リサイズ幅 |
| `exportResizeHeight` | Int | リサイズ高さ |
| `exportDPI` | Int | `ExportDPI` rawValue（72 / 150 / 300 / 600） |
| `exportTIFFCompression` | String | `TIFFCompression` rawValue |
| `exportPDFCompression` | String | `PDFImageCompression` rawValue |
| `preferredSaveFolderBookmark` | Data | Security-Scoped Bookmark |

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

バイナリは git で直接管理。`DraftCanvas/Resources/bin/` に同梱済み（arm64 + x86_64 fat バイナリ）。

**バイナリ更新手順:**

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

`AppLanguage` は `ja` / `en` / `system`（OS設定追従）の 3 ケースを持ちます。デフォルト初期値は `.system`（起動時に OS の言語設定に追従）。`SettingsView` から変更でき、`UserDefaults` の `appLanguage` キーに保存されます。言語変更は再起動が必要です（→ §2.10）。

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
| エディタ実装 | `DraftCanvas/Editors/` |
| ストア実装 | `DraftCanvas/Stores/` |
| View 実装 | `DraftCanvas/Views/` |
| ライセンス実装 | `DraftCanvas/License/` |
| エクスポート実装 | `DraftCanvas/Export/` |
