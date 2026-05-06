#!/usr/bin/env bash
# tottok plugin: 統合 install スクリプト。
#
# 役割は 3 つ:
#   (a) ~/.local/bin/tottok shim を idempotent に配置する (Setup / SessionStart
#       hook から ``--shim-only`` で呼ばれる)
#   (b) shim 経由 ``tottok setup`` の "実体" として、CLI runtime DL +
#       uv sync + PAT 登録 + claude mcp add + 疎通確認をまとめる
#   (c) ``--shim-only`` モードで auto-update を実行 — plugin が知ってる
#       ``EXPECTED_CLI_VERSION`` と ``~/.tottok/cli/.tottok-cli-version``
#       (archive 直下から展開される version マーカ) を比較し、mismatch
#       なら silent に CLI runtime を再 DL する。``/plugins Update now``
#       で plugin manifest が refresh された後、次セッション起動時に
#       新 CLI runtime も自動展開される。
#
# /tottok-setup は shim が既に PATH に入っていれば ``tottok setup``、
# 入っていなければこの install.sh を直接呼ぶ。どちらでも結果は同じ。
#
# usage:
#   install.sh --shim-only        # shim 配置 + 必要なら auto-update
#   install.sh <BASE_URL> <PAT>   # shim 配置 + setup 実行
set -euo pipefail

# 本 plugin が期待する CLI runtime version。新 CLI release ごとに必ず
# bump すること (release 後の手動同期手順は backend の RELEASE.md 参照)。
EXPECTED_CLI_VERSION="0.2.3"

ARCHIVE_URL="https://github.com/brc-yamagishi/tottok-plugin/releases/latest/download/tottok-cli.tar.gz"
CLI_DIR="${HOME}/.tottok/cli"
SHIM_PATH="${HOME}/.local/bin/tottok"

# ----------------------------------------------------------------------------
# CLI runtime 操作 helpers (--shim-only auto-update から呼ばれる)
# ----------------------------------------------------------------------------

read_installed_cli_version() {
  if [ -f "${CLI_DIR}/.tottok-cli-version" ]; then
    tr -d '[:space:]' < "${CLI_DIR}/.tottok-cli-version"
  else
    echo "unknown"
  fi
}

# CLI runtime を archive から展開し、依存解決まで行う。失敗時は非 0 終了。
# ``download_and_install_cli >/dev/null 2>&1`` で silent 化できる。
download_and_install_cli() {
  if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv 未 install (CLI runtime 更新には uv が必要)" >&2
    return 1
  fi
  mkdir -p "${CLI_DIR}"
  curl -fsSL "${ARCHIVE_URL}" | tar xz -C "${CLI_DIR}" --strip-components=1
  ( cd "${CLI_DIR}" && uv sync --quiet )
}

# SessionStart hook 経由の auto-update。失敗しても session 起動は阻害
# しない (前 version で続行)。出力は stderr のみ。
auto_update_cli_runtime() {
  # 未 install 状態 (初回 /tottok-setup 前) は何もしない
  if [ ! -f "${CLI_DIR}/pyproject.toml" ]; then
    return 0
  fi
  local installed
  installed="$(read_installed_cli_version)"
  if [ "${installed}" = "${EXPECTED_CLI_VERSION}" ]; then
    return 0
  fi
  echo "[tottok] CLI runtime を ${installed} → ${EXPECTED_CLI_VERSION} に更新中..." >&2
  if ! download_and_install_cli >/dev/null 2>&1; then
    echo "[tottok] CLI runtime auto-update 失敗 (前 version で続行)" >&2
    return 0
  fi
  echo "[tottok] CLI runtime 更新完了 (${EXPECTED_CLI_VERSION})" >&2
}

# ----------------------------------------------------------------------------
# Shim deployment
# ----------------------------------------------------------------------------

deploy_shim() {
  mkdir -p "$(dirname "${SHIM_PATH}")"
  cat > "${SHIM_PATH}" <<'SHIM_EOF'
#!/usr/bin/env bash
# tottok shim — Claude Code plugin tottok-plugin が deploy した汎用 entry。
#
#   tottok setup <URL> <PAT>   初期セットアップ (CLI runtime DL + PAT 登録 + MCP add)
#   tottok update              CLI runtime のみ手動再 DL (PAT / MCP は触らない)
#   tottok <その他>            ``~/.tottok/cli`` の python -m cli にパススルー
#
# 全 invocation が ``Bash(tottok *)`` permission allow rule 1 行で済む。
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

# ``tottok update`` — PAT / MCP には触らず CLI runtime のみ再 DL する
# (release 直後にすぐ最新版を取りたい時の手動 force update)。
if [ "${1:-}" = "update" ]; then
  command -v uv >/dev/null 2>&1 || {
    echo "ERROR: uv 未 install" >&2
    exit 1
  }
  echo "[1/2] CLI runtime をダウンロード + 展開 (${CLI_DIR})..."
  mkdir -p "${CLI_DIR}"
  curl -fsSL "${ARCHIVE_URL}" | tar xz -C "${CLI_DIR}" --strip-components=1

  echo "[2/2] 依存解決 (uv sync)..."
  ( cd "${CLI_DIR}" && uv sync --quiet )

  if [ -f "${CLI_DIR}/.tottok-cli-version" ]; then
    NEW_VER="$(tr -d '[:space:]' < "${CLI_DIR}/.tottok-cli-version")"
    echo "✅ tottok CLI runtime を更新しました (version=${NEW_VER})"
  else
    echo "✅ tottok CLI runtime を更新しました"
  fi
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

# ----------------------------------------------------------------------------
# Entry points
# ----------------------------------------------------------------------------

# Mode 1: hook 等から呼ばれる shim-only deploy (+ auto-update)
if [ "${1:-}" = "--shim-only" ]; then
  deploy_shim
  auto_update_cli_runtime
  # 静かに終了 (hook の SessionStart JSON output を汚染しないため)
  exit 0
fi

# Mode 2: shim 配置 + setup 実行
deploy_shim

# shim 経由で setup を呼ぶ。これにより setup ロジックの実体は shim 内に
# 集約され、install.sh と shim でロジック重複を避けられる。
"${SHIM_PATH}" setup "$@"
