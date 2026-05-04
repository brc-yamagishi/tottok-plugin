#!/usr/bin/env bash
# tottok plugin: 統合 install スクリプト。
#
# 役割は 2 つ:
#   (a) ~/.local/bin/tottok shim を idempotent に配置する (Setup / SessionStart
#       hook から ``--shim-only`` で呼ばれる)
#   (b) shim 経由 ``tottok setup`` の "実体" として、CLI runtime DL +
#       uv sync + PAT 登録 + claude mcp add + 疎通確認をまとめる
#
# /tottok-setup は shim が既に PATH に入っていれば ``tottok setup``、
# 入っていなければこの install.sh を直接呼ぶ。どちらでも結果は同じ。
#
# usage:
#   install.sh --shim-only        # shim だけ配置、setup はしない
#   install.sh <BASE_URL> <PAT>   # shim 配置 + setup 実行
set -euo pipefail

ARCHIVE_URL="https://github.com/brc-yamagishi/tottok-plugin/releases/latest/download/tottok-cli.tar.gz"
CLI_DIR="${HOME}/.tottok/cli"
SHIM_PATH="${HOME}/.local/bin/tottok"

deploy_shim() {
  mkdir -p "$(dirname "${SHIM_PATH}")"
  cat > "${SHIM_PATH}" <<'SHIM_EOF'
#!/usr/bin/env bash
# tottok shim — Claude Code plugin tottok-plugin が deploy した汎用 entry。
# ``tottok setup <URL> <PAT>`` で初期セットアップ、それ以外の引数は
# CLI (~/.tottok/cli) にパススルーする。
#
# 全 invocation が ``Bash(tottok:*)`` permission allow rule 1 行で済む。
set -euo pipefail

CLI_DIR="${HOME}/.tottok/cli"
ARCHIVE_URL="https://github.com/brc-yamagishi/tottok-plugin/releases/latest/download/tottok-cli.tar.gz"

if [ "${1:-}" = "setup" ]; then
  shift
  BASE_URL="${1:?usage: tottok setup <BASE_URL> <PAT>}"
  PAT="${2:?usage: tottok setup <BASE_URL> <PAT>}"

  command -v uv >/dev/null 2>&1 || {
    echo "ERROR: uv 未 install。https://docs.astral.sh/uv/getting-started/installation/" >&2
    exit 1
  }
  command -v claude >/dev/null 2>&1 || {
    echo "ERROR: claude CLI 未 install (Claude Code 本体が PATH 上にあるか確認)。" >&2
    exit 1
  }

  echo "[1/4] CLI runtime をダウンロード + 展開 (${CLI_DIR})..."
  mkdir -p "${CLI_DIR}"
  curl -fsSL "${ARCHIVE_URL}" | tar xz -C "${CLI_DIR}" --strip-components=1

  echo "[2/4] 依存解決 (uv sync)..."
  ( cd "${CLI_DIR}" && uv sync --quiet )

  echo "[3/4] PAT を ~/.tottok/config.toml に書き込み..."
  ( cd "${CLI_DIR}" && uv run --quiet python -m cli config set --pat "${PAT}" --base-url "${BASE_URL}" )

  echo "[4/4] Claude Code に MCP server を登録..."
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
  exit 0
fi

# Default: CLI passthrough
if [ ! -f "${CLI_DIR}/pyproject.toml" ]; then
  echo "ERROR: ~/.tottok/cli が未 install。'tottok setup <BASE_URL> <PAT>' を実行してください。" >&2
  exit 1
fi
exec uv run --quiet --directory "${CLI_DIR}" python -m cli "$@"
SHIM_EOF
  chmod +x "${SHIM_PATH}"
}

# Mode 1: hook 等から呼ばれる shim-only deploy
if [ "${1:-}" = "--shim-only" ]; then
  deploy_shim
  # 静かに終了 (hook の SessionStart JSON output を汚染しないため)
  exit 0
fi

# Mode 2: shim 配置 + setup 実行
deploy_shim

# shim 経由で setup を呼ぶ。これにより setup ロジックの実体は shim 内に
# 集約され、install.sh と shim でロジック重複を避けられる。
"${SHIM_PATH}" setup "$@"
