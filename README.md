# tottok-plugin

[tottok](https://github.com/brc-yamagishi/tottok) 用の Claude Code plugin **デモ用の公開配布リポジトリ**。

backend 本体 (`brc-yamagishi/tottok`) は private ですが、Claude Code から接続するための plugin manifest と CLI runtime archive はここで public に配布しています。これにより `gh` 認証なしで `claude plugin install` が通ります。

## 機能

- **SessionStart hook**: 直近 7 日分の memory digest を AI の context に自動注入
- **Stop hook**: 会話 turn を `claude -p` headless (Haiku 4.5) で要約してメモリに自動保存
- **`/tottok-setup`**: 初期セットアップ (CLI runtime 取得 / PAT 登録 / MCP 接続) を対話で支援

## インストール

### 前提

- **OS**: Linux / macOS / WSL (Windows ネイティブは現状非対応 — WSL を使用)
- [Claude Code](https://docs.claude.com/claude-code) v2.x 以降
- [`uv`](https://docs.astral.sh/uv/getting-started/installation/) (CLI runtime の依存解決に使用)
- `~/.local/bin` が PATH に含まれていること (uv 標準セットアップなら通常デフォルト)
- tottok backend へのアクセス権 (社内ユーザに付与される PAT)

### 手順

```bash
# 1. marketplace を登録 (1 回限り)
claude plugin marketplace add brc-yamagishi/tottok-plugin

# 2. plugin install
claude plugin install tottok@tottok

# 3. 初期セットアップ (CLI runtime のダウンロード + PAT 設定 + MCP 登録)
/tottok-setup
```

セットアップ完了後、次の Claude Code セッションから自動的に動作します。

## permissions.allow の登録 (推奨)

毎回 `Do you want to proceed?` 確認を出さないために `~/.claude/settings.json` または `.claude/settings.local.json` に以下を追加:

```json
{
  "permissions": {
    "allow": [
      "Bash(tottok *)"
    ]
  }
}
```

`/tottok-setup` 中の `tottok setup ...` も日常の `tottok list` / `tottok search` 等もすべてこのルール 1 行で allow される。`tottok` shim は SessionStart hook が `~/.local/bin/tottok` に自動配置する。

## 仕組み

```
Claude Code session
  ├─ SessionStart hook ─→ ${HOME}/.tottok/cli の uv run python -m cli hook session-start
  │                       └─→ tottok MCP server (HTTP) から memory digest を取得 → context に注入
  └─ Stop hook ─────────→ ${HOME}/.tottok/cli の uv run python -m cli hook stop
                          └─→ claude -p (Haiku 4.5) で抽出 → tottok MCP に store
```

`~/.tottok/cli/` には CLI 実行物 (`cli/` + `tottok_core/` + 最小依存の `pyproject.toml`) のみ展開されます (~64KB)。tottok backend 全体の clone は不要。

## アップデート

```bash
/tottok-setup
```

を再実行すると `~/.tottok/cli/` の CLI runtime が最新版に置き換わります (PAT / MCP 登録は維持)。

## アンインストール

```bash
claude plugin uninstall tottok
claude mcp remove tottok
rm -rf ~/.tottok/cli ~/.tottok/config.toml
```

## 他 memory plugin との共存

claude-mem 等の他 memory 系 plugin を併用すると SessionStart digest や Stop hook auto-capture が重複します。本 plugin はこの併用を意図的にブロックしません (= ユーザ責任)。気になる場合は片方を `claude plugin disable` してください。

## ファイル配布での代替インストール

GitHub release 経由が使えない閉鎖環境向け。リポジトリ管理者から `tottok-cli.tar.gz` を直接受け取り:

```bash
mkdir -p ~/.tottok/cli
tar xz -C ~/.tottok/cli --strip-components=1 < tottok-cli.tar.gz
cd ~/.tottok/cli && uv sync
```

その上で `/tottok-setup` の step 4 (PAT 登録) 以降を進めます。

plugin 自体も file path で marketplace add 可能:

```bash
claude plugin marketplace add /path/to/tottok-plugin-dir
```

## 環境変数

`/tottok-setup` 実行後、必要に応じて以下を環境変数で上書き可能 (default は `~/.tottok/config.toml`):

| 変数 | 役割 |
|---|---|
| `TOTTOK_PAT` | PAT (rmcp_xxx) |
| `TOTTOK_BASE_URL` | tottok backend URL |
| `TOTTOK_WORKSPACE` | workspace 識別子 |
| `TOTTOK_HOOK_SESSION_START_CONSOLE` | SessionStart 時の人間向け digest 表示 (`summary` / `off`、default `summary`) |
| `TOTTOK_HOOK_STOP_MIN_CHARS` | Stop hook 自動キャプチャ最小文字数 (default 300) |
| `TOTTOK_HOOK_STOP_DEDUP_WINDOW_SEC` | 重複キャプチャ抑制 window (default 600) |
| `TOTTOK_EXTRACTOR_MODE` | `claude_headless` / `off` |
| `TOTTOK_EXTRACTOR_CLAUDE_MODEL` | default `claude-haiku-4-5` |

## 開発

このリポジトリは [tottok backend](https://github.com/brc-yamagishi/tottok) の plugin 部分を public mirror しています。CLI source (`cli/`, `tottok_core/`) は backend 側で開発し、release 時に archive (`tottok-cli.tar.gz`) を本リポジトリの GitHub Release に upload する運用です。

plugin manifest / hooks / commands / scripts への変更は本リポジトリで直接 PR を作成可能です。
