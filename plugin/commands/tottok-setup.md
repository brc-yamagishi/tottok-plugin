---
description: tottok の初期セットアップ — CLI runtime ダウンロード + PAT 登録 + MCP 接続登録を対話で支援する
allowed-tools: ["Bash", "Read", "Write", "Edit"]
---

# /tottok-setup — tottok 初期セットアップ

このセットアップでは以下を順に行います。各ステップで進捗をユーザに報告し、必要な入力を質問してください。エラーが出たらその場で stop して原因を一緒に確認します。

## 1. backend URL の確認

ユーザに「tottok backend の URL を教えてください (default: `http://localhost:8000`)」と聞く。回答に応じて以降のステップで使う ``BASE_URL`` を決める。社内 hostname 等の場合もそのまま受け取る。

## 2. CLI runtime のダウンロード + 展開

`~/.tottok/cli/` に最新 archive を展開する。既存があっても上書きで OK:

```bash
mkdir -p ~/.tottok/cli
curl -fsSL https://github.com/brc-yamagishi/tottok-plugin/releases/latest/download/tottok-cli.tar.gz \
  | tar xz -C ~/.tottok/cli --strip-components=1
```

成功したら ``ls ~/.tottok/cli`` で `cli/`, `tottok_core/`, `pyproject.toml` が見えることを確認して報告する。

`curl` コマンドが失敗する場合は archive がまだ release されていない可能性がある。リポジトリ管理者に確認する。

## 3. uv sync (依存解決)

```bash
cd ~/.tottok/cli && uv sync --quiet
```

エラーが出たら uv 自体が install されているか (`command -v uv`) も確認する。未 install なら https://docs.astral.sh/uv/getting-started/installation/ を案内。

## 4. PAT の取得案内

ユーザに以下を表示:

> tottok admin UI (例: ``http://<BASE_URL のホスト部分>:3000/settings/api-keys``) を開き、PAT を発行してコピーしてください。
> 発行された PAT は `rmcp_` で始まる文字列です。

ユーザが PAT を貼り付けたら ``tottok config set`` 相当を実行:

```bash
cd ~/.tottok/cli && uv run --quiet python -m cli config set --pat "<PAT>" --base-url "<BASE_URL>"
```

## 5. MCP 接続登録

Claude Code に tottok HTTP MCP server を登録する:

```bash
PAT=$(grep '^pat' ~/.tottok/config.toml | head -1 | cut -d'"' -f2)
BASE_URL=$(grep '^base_url' ~/.tottok/config.toml | head -1 | cut -d'"' -f2)
claude mcp add --scope user --transport http tottok "${BASE_URL%/}/mcp/" --header "Authorization: Bearer ${PAT}"
```

実行後 ``claude mcp list`` で ``tottok`` が含まれているか確認させる。

## 6. 疎通確認

```bash
cd ~/.tottok/cli && uv run --quiet python -m cli teams
```

team 一覧が返れば成功。エラーなら PAT / URL を再確認。

## 7. 完了報告

成功したら以下を返す:

> tottok セットアップ完了です。
> - SessionStart hook で過去 7 日間の memory digest が AI の context に注入されます
> - Stop hook で会話 turn が自動キャプチャされます (`~/.tottok/cli` の CLI が `claude -p` で抽出)
> - 次の Claude Code セッションから動作します
> - 追加で AI に手動 store させたい時は `mcp__tottok__store_memory` を直接呼ぶことも可能

## 注意

claude-mem 等の他 memory 系 plugin を併用している場合、両方の SessionStart / Stop hook が発火し digest や auto-capture が重複する可能性があります。tottok 側はこの併用を意図的に防ぎません (ユーザ責任)。気になる場合は片方を `claude plugin disable` してください。

## アップデート

新しい version の CLI runtime が出た時は ``/tottok-setup`` を再実行すれば step 2-3 で archive が更新されます。PAT / MCP 登録は維持されます。
