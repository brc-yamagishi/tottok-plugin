---
description: tottok の初期セットアップ — CLI runtime ダウンロード + PAT 登録 + MCP 接続登録を 1 本のラッパスクリプトで実行する
allowed-tools: ["Bash", "Read"]
---

# /tottok-setup — tottok 初期セットアップ

実際のセットアップ (CLI runtime DL / uv sync / PAT 登録 / claude mcp add) は **1 本のラッパスクリプト** ``plugin/scripts/install.sh`` に集約されているため、Bash 許可ダイアログを 1 回で済ませられる。

AI は以下の 3 ステップでユーザを誘導してください:

## 1. backend URL の確認

ユーザに「tottok backend の URL を教えてください (default: `http://localhost:8000`)」と質問する。回答が `BASE_URL` になる。空回答なら default を使う。

## 2. PAT の取得案内

ユーザに以下を表示:

> tottok console (例: ``http://<BASE_URL のホスト部分>:3000/settings/api-keys``) を開き、PAT を発行してコピーしてください。
> 発行された PAT は `rmcp_` で始まる文字列です。

回答が `PAT` になる。

## 3. ラッパスクリプトを 1 回だけ実行

以下を Bash で **1 度だけ** 実行する:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugin/scripts/install.sh" "<BASE_URL>" "<PAT>"
```

スクリプトが内部で:

1. `~/.tottok/cli/` に CLI runtime をダウンロード + 展開
2. `uv sync --quiet` で依存解決
3. `tottok config set` で PAT / base_url を保存
4. `claude mcp add --transport http` で MCP server を登録 (既存があれば一度 remove してから add)
5. `tottok teams` で疎通確認

の 5 つを順に実行し、最後に「✅ tottok セットアップ完了」を出す。

エラーが出たら出力を確認:

- `uv` 未 install → https://docs.astral.sh/uv/getting-started/installation/ を案内
- `tottok teams` で 401/403 → PAT が違う、もしくは expired
- `tottok teams` で connection error → `BASE_URL` が違う、または backend が起動していない

## 4. 完了報告

成功したら以下を返す:

> tottok セットアップ完了です。
> - SessionStart hook で過去 7 日間の memory digest が AI の context に注入されます
> - Stop hook で会話 turn が自動キャプチャされます (`~/.tottok/cli` の CLI が `claude -p` で抽出)
> - 次の Claude Code セッションから動作します
> - 追加で AI に手動 store させたい時は `mcp__tottok__store_memory` を直接呼ぶことも可能

## 確認プロンプトを毎回出さないために (任意)

毎回 `Do you want to proceed?` が出るのを避けるには、`.claude/settings.local.json` または `~/.claude/settings.json` の `permissions.allow` に以下を追加する:

```json
{
  "permissions": {
    "allow": [
      "Bash(bash ${CLAUDE_PLUGIN_ROOT}/plugin/scripts/install.sh:*)"
    ]
  }
}
```

これで `/tottok-setup` 中の Bash 呼び出しが 1 回限りで承認なしで通る。

## 注意

claude-mem 等の他 memory 系 plugin を併用している場合、両方の SessionStart / Stop hook が発火し digest や auto-capture が重複する可能性があります。tottok 側はこの併用を意図的に防ぎません (ユーザ責任)。気になる場合は片方を `claude plugin disable` してください。

## アップデート

新しい version の CLI runtime が出た時は `/tottok-setup` を再実行すれば step 3 で archive が更新されます (PAT / MCP 登録は冪等に上書き)。
