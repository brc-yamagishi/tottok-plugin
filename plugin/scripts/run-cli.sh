#!/usr/bin/env bash
# tottok plugin: hook 用ラッパ。
#
# ~/.tottok/cli/ に展開された CLI runtime を呼び出す。未インストール時は
# Claude Code が期待する空 payload を返して fail-silent する (ユーザが
# /tottok-setup を未実行でも plugin install 直後にエラーにならないように)。
#
# usage: run-cli.sh <session-start|stop>
set -e
SUBCOMMAND="${1:-}"
shift || true

CLI_DIR="${HOME}/.tottok/cli"
if [ ! -d "${CLI_DIR}" ] || [ ! -f "${CLI_DIR}/pyproject.toml" ]; then
  case "${SUBCOMMAND}" in
    session-start)
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
      ;;
    *)
      printf '%s\n' '{"continue":true,"suppressOutput":true}'
      ;;
  esac
  exit 0
fi

# uv が PATH にない環境では失敗する。その場合も fail-silent。
if ! command -v uv >/dev/null 2>&1; then
  case "${SUBCOMMAND}" in
    session-start)
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
      ;;
    *)
      printf '%s\n' '{"continue":true,"suppressOutput":true}'
      ;;
  esac
  exit 0
fi

exec uv run --quiet --directory "${CLI_DIR}" python -m cli hook "${SUBCOMMAND}" "$@"
