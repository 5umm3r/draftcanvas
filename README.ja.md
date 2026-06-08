**日本語** | [English](README.md)

# Draft Canvas

Mac で AI 画像を生成・編集するデスクトップアプリ。テキストプロンプトから画像生成し、インペイント・背景除去・高解像度化・ベクター化をプロジェクト単位のキャンバスで管理。

## 主な機能

- **AI 画像生成** — テキストプロンプトから画像を生成 (Codex CLI + OpenAI gpt-image 経由)
- **インペイント / アウトペイント** — マスク編集で部分再生成・画像の拡張
- **背景除去** — Vision API によるオンデバイス処理
- **高解像度化** — AI アップスケール
- **ベクター化** — ラスター画像を SVG に変換 (vtracer)
- **素材抽出** — 画像内オブジェクトの自動検出・切り抜き
- **トリミング / ラフ描画** — キャンバス上での編集ツール
- **プロジェクト管理** — 複数プロジェクトで画像をまとめて管理
- **プロンプトテンプレート / 履歴** — よく使うプロンプトの保存・再利用

## 動作環境

| 項目 | 要件 |
|------|------|
| OS | macOS 14 Sonoma 以降 |
| アーキテクチャ | Apple Silicon / Intel 両対応 |
| 必須 | [Codex CLI](https://github.com/openai/codex) (別途インストール) |
| アカウント | ChatGPT Plus 以上のサブスクリプション |

## インストール

### ビルド済みアプリ

[**Download DraftCanvas.dmg**](https://github.com/5umm3r/draftcanvas/releases/latest/download/DraftCanvas.dmg) — 最新版を直接ダウンロード

### ソースからビルド

```bash
# リポジトリをクローン
git clone https://github.com/5umm3r/draftcanvas.git
cd draftcanvas

# Rust FFI ライブラリをビルド (初回のみ)
cd vtracer-ffi
./build_universal.sh
cd ..

# アプリをビルド
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' \
  SYMROOT=_build OBJROOT=_build/obj build
```

**ビルド要件:**
- Xcode 16+
- Rust toolchain (`rustup` 経由でインストール)

## 使い方

詳細は [USER_GUIDE.md](USER_GUIDE.md) を参照。

## 貢献

Issue や PR を歓迎します。詳しくは [CONTRIBUTING.md](CONTRIBUTING.md) を参照。

## スポンサー

Draft Canvas はオープンソースで無料です。開発を応援してくれる方は:

- [GitHub Sponsors](https://github.com/sponsors/5umm3r)
- [Polar](https://buy.polar.sh/polar_cl_fZgIt4TMaHLTt1ah2aYDWoI9BGoY2KEuTx5fC0G2ehc)

## ライセンス

[MIT](LICENSE)
