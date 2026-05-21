# ビルド手順

## 基本ビルド

```bash
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build
```

成果物: `_build/Debug/DraftCanvas.app`

## 起動

```bash
open _build/Debug/DraftCanvas.app
```

## ビルド → 即起動

```bash
xcodebuild -scheme DraftCanvas -destination 'platform=macOS' SYMROOT=_build OBJROOT=_build/obj build 2>&1 | grep -E '(error:|BUILD)' && open _build/Debug/DraftCanvas.app
```

## ライセンス状態 切替 (DEBUG ビルドのみ)

ENV変数 `DRAFTCANVAS_LICENSE_OVERRIDE` で起動時の状態を強制セット。

| 値 | 状態 |
|----|------|
| `licensed` | ライセンス済 |
| `trial` | トライアル残14日 |
| `trial:N` | トライアル残N日 (`trial:0` = 期限切れ扱い) |
| `expired` | 期限切れ |
| `reset` | Keychain 全消去 → 通常評価 |
| 未設定 | 通常動作 |

```bash
DRAFTCANVAS_LICENSE_OVERRIDE=licensed open _build/Debug/DraftCanvas.app
DRAFTCANVAS_LICENSE_OVERRIDE=trial:3 open _build/Debug/DraftCanvas.app
DRAFTCANVAS_LICENSE_OVERRIDE=expired open _build/Debug/DraftCanvas.app
DRAFTCANVAS_LICENSE_OVERRIDE=reset open _build/Debug/DraftCanvas.app
```

Release ビルドでは ENV変数は無視される。

## About パネルのビルド番号

メニュー → "Draft Canvas について" の表示形式: `Version 1.0.0 (build N)`

- **Debug ビルド**: `CURRENT_PROJECT_VERSION=1` 固定 → `build 1` 表示
- **Release ビルド** (`./scripts/release.sh`): `git rev-list --count HEAD` の値を注入 → `build 123` 等

## 注意

- `SYMROOT` は常に `_build`、`OBJROOT` は常に `_build/obj`
- `-derivedDataPath` は使わない
- 上記以外の場所にビルド成果物を作った場合は即削除
