#!/usr/bin/env bash
# tottok plugin: 初期セットアップ用 1-shot スクリプト。
#
# /tottok-setup から呼び出されるか、ユーザが手動で実行する。
# Claude Code の Bash 許可ダイアログを 1 回で済ませるため、4 ステップを
# 1 つの bash 呼び出しにまとめている。
#
# usage: install.sh <BASE_URL> <PAT>
#   BASE_URL: tottok backend URL (例: http://localhost:8000)
#   PAT:      tottok console で発行した rmcp_xxx
#
# 再実行で運用 (例: archive 更新時の /tottok-setup 再実行) も想定。
# config / MCP 登録は冪等に上書きされる。
set -euo pipefail

BASE_URL="${1:?usage: install.sh <BASE_URL> <PAT>}"
PAT="${2:?usage: install.sh <BASE_URL> <PAT>}"

ARCHIVE_URL="https://github.com/brc-yamagishi/tottok-plugin/releases/latest/download/tottok-cli.tar.gz"
CLI_DIR="${HOME}/.tottok/cli"

if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: uv が見つかりません。https://docs.astral.sh/uv/getting-started/installation/ から install してください。" >&2
  exit 1
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: claude CLI が見つかりません。Claude Code 本体が PATH にあるか確認してください。" >&2
  exit 1
fi

echo "[1/4] CLI runtime をダウンロード + 展開 (${CLI_DIR})..."
mkdir -p "${CLI_DIR}"
curl -fsSL "${ARCHIVE_URL}" | tar xz -C "${CLI_DIR}" --strip-components=1

echo "[2/4] 依存解決 (uv sync)..."
( cd "${CLI_DIR}" && uv sync --quiet )

echo "[3/4] PAT を ~/.tottok/config.toml に書き込み..."
( cd "${CLI_DIR}" && uv run --quiet python -m cli config set --pat "${PAT}" --base-url "${BASE_URL}" )

echo "[4/4] Claude Code に MCP server を登録..."
# 既に登録済の場合は claude mcp add が失敗するが、先に remove して冪等化する
claude mcp remove tottok --scope user >/dev/null 2>&1 || true
claude mcp add --scope user --transport http tottok "${BASE_URL%/}/mcp/" \
  --header "Authorization: Bearer ${PAT}"

echo ""
echo "=== 疎通確認 (tottok teams) ==="
( cd "${CLI_DIR}" && uv run --quiet python -m cli teams )

echo ""
echo "✅ tottok セットアップ完了"
echo "   - SessionStart hook: digest 自動注入"
echo "   - Stop hook: 会話 turn の自動キャプチャ"
echo "   次の Claude Code セッションから動作します。"
