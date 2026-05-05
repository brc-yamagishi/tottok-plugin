---
description: tottok の初期セットアップ — tottok shim 経由で 1 本のコマンドにまとめる
allowed-tools: ["Bash"]
---

# /tottok-setup — tottok 初期セットアップ

`tottok` shim (= `~/.local/bin/tottok`) は plugin の SessionStart hook で自動配置される。AI は以下のステップで対話する:

## 1. 既存設定の確認 (再 run 検出)

まず ``~/.tottok/config.toml`` が存在するか確認する。存在すれば中身から ``base_url`` と ``pat`` を抽出して **既存値** として保持する (例: ``grep -E '^(base_url|pat)' ~/.tottok/config.toml``)。これは「CLI runtime のアップデートだけしたい再 run」のケースで PAT 再入力を省くため。

- **存在する** → 以降のステップで「Enter で維持」の default として既存値を使う (再 run モード)
- **存在しない** → 初回 install。BASE_URL の default は ``http://localhost:8000``、PAT は必須入力

## 2. backend URL の確認

ユーザに以下のいずれかで質問する:

- **再 run モード**: 「tottok backend の URL を教えてください (現在: ``<existing-base-url>``、Enter で維持)」
- **初回 install**: 「tottok backend の URL を教えてください (default: ``http://localhost:8000``)」

空回答なら既存値 / default を使う。回答 (または既存値) が ``BASE_URL`` になる。

## 3. PAT の取得案内

ユーザに以下のいずれかで質問する:

- **再 run モード**: 「tottok の PAT を貼り付けてください (現在: ``rmcp_xxxxxxxxxxxx…`` 先頭 12 文字、Enter で維持)」と伝える。空回答なら既存 PAT を使う
- **初回 install**: 以下を表示:
  > tottok console (例: ``http://<BASE_URL のホスト部分>:3000/settings/api-keys``) を開き、PAT を発行してコピーしてください。
  > 発行された PAT は ``rmcp_`` で始まる文字列です。

回答 (または既存値) が ``PAT`` になる。

## 4. tottok setup を 1 回だけ実行

**重要**: 以下のチェックと実行は **複数の Bash 呼び出しに分けて** 行うこと。``&&`` / ``;`` 等で複合コマンドにすると Claude Code の Bash permission matcher (例: ``Bash(tottok *)``) が複合コマンド全体に対して match できず、ユーザに毎回承認プロンプトを出してしまう。

### 4-1. `tottok` コマンドの存在確認 (Bash 呼び出し ①)

```bash
command -v tottok
```

出力に path が出れば PATH にある (通常ケース)。何も出なければ PATH に無い (初回 install 直後で SessionStart hook 未発火等)。

### 4-2. 上の結果に応じて、**別の Bash 呼び出しで** setup を実行

- **PATH にある**: 以下を **単独の Bash 呼び出し** で実行 (``&&`` 等で繋がない):
  ```bash
  tottok setup "<BASE_URL>" "<PAT>"
  ```
- **PATH に無い**: plugin 同梱の install.sh で代替 (これも単独の Bash 呼び出し):
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" "<BASE_URL>" "<PAT>"
  ```

どちらも内部で:

1. `~/.tottok/cli/` に CLI runtime をダウンロード + 展開
2. `uv sync --quiet` で依存解決
3. `tottok config set` で PAT / base_url を保存
4. `claude mcp add --transport http` で MCP server を登録 (既存は一度 remove)
5. `tottok teams` で疎通確認

を実行し、最後に「✅ tottok セットアップ完了」を出す。

エラーが出たら出力を確認:

- `uv` 未 install → https://docs.astral.sh/uv/getting-started/installation/ を案内
- `tottok teams` で 401/403 → PAT が違う、もしくは expired
- `tottok teams` で connection error → `BASE_URL` が違う、または backend が起動していない

## 5. 完了報告

成功したら以下を返す:

> tottok セットアップ完了です。
> - SessionStart hook で過去 7 日間の memory digest が AI の context に注入されます
> - Stop hook で会話 turn が自動キャプチャされます (`~/.tottok/cli` の CLI が `claude -p` で抽出)
> - 次の Claude Code セッションから動作します
> - AI が `mcp__tottok__*` MCP tool を直接呼ぶか、`tottok ...` shim 経由で CLI を叩くこともできます

## 確認プロンプトを毎回出さないために (推奨)

`tottok setup` も `tottok list` も `tottok store` も全部 `tottok` コマンドなので、`Bash(tottok:*)` の **1 ルール** で全 invocation を allow できる:

`.claude/settings.local.json` または `~/.claude/settings.json` に追加:

```json
{
  "permissions": {
    "allow": [
      "Bash(tottok:*)"
    ]
  }
}
```

初回 install 直後で shim 未配置のケースが心配な場合は、念のため install.sh も allow しておくとよい:

```json
{
  "permissions": {
    "allow": [
      "Bash(tottok:*)",
      "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh:*)"
    ]
  }
}
```

## 前提

- `~/.local/bin` が PATH に含まれていること (uv 等で modern setup なら通常デフォルト)
- 含まれていない場合は `~/.bashrc` / `~/.zshrc` 等に追加: `export PATH="$HOME/.local/bin:$PATH"`

## 注意

claude-mem 等の他 memory 系 plugin を併用している場合、両方の SessionStart / Stop hook が発火し digest や auto-capture が重複する可能性があります。tottok 側はこの併用を意図的に防ぎません (ユーザ責任)。気になる場合は片方を `claude plugin disable` してください。

## アップデート

新しい version の CLI runtime が出た時は `/tottok-setup` を再実行すれば step 3 で archive が更新されます (PAT / MCP 登録は冪等に上書き)。
