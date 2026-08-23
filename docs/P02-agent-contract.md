# P02 — エージェント契約（Issue #4）

## 権限区分

| 役割 | 許可 | 禁止 |
|------|------|------|
| **人間** | フォーム狭窄、`--apply`、`--allow-cmd`、`--allow-host-net` | エージェントに cmd を残したテンプレを渡すこと |
| **エージェント** | `#lang makejail` の穴埋めのみ（`name`/`from`/`arg`/`wiki-site`/…） | SSH、apply、生 Caddyfile 手書き、`(cmd)` |
| **実行器** | 効果列の apply / destroy | エージェントから直接呼ばれること |

## CLI

```bash
# エージェント成果物の検査（既定 --agent）
raco makejail check examples/dokuwiki-caddy-agent.rkt \
  --arg hostname=wiki.example.com \
  --arg data-host=/zroot/dokuwiki-data

raco makejail plan examples/dokuwiki-caddy-agent.rkt \
  --arg hostname=wiki.example.com \
  --arg data-host=/zroot/dokuwiki-data

# 人間が cmd や host net を使うレガシー例
raco makejail plan examples/dokuwiki-caddy.rkt --human --allow-cmd --allow-host-net
```

## 合格条件（エージェント）

1. `raco makejail check` が成功する  
2. 効果列に `jexec-cmd` が無い  
3. `network host` が無い（`vnet-default` 等）。host が要るなら人間が `--allow-host-net`  

## 語彙（エージェント向け）

`name`, `from`, `option dataset`, `arg`（必須可）, `pkg`, `volume`, `sysrc`, `service`, `copy`, **`wiki-site`**, `mount`  
**禁止:** `cmd`, `human-cmd`, `exec:run`, `jail-spec`（旧構文）

## ロードマップ対応

| #4 段階 | 本 PR |
|---------|--------|
| 1 構文統一 | 平坦構文のみ（jail-spec なし） |
| 2 cmd 外す | agent で禁止 / `--allow-cmd` で人間のみ |
| 3 arg 必須 | `resolve-args` + `--arg` / env |
| 4 テンプレ | `wiki-site` + `dokuwiki-caddy-agent.rkt` |
| 5 host 禁止 | agent で禁止（thin-vnet 実装は #3） |
| 6 穴埋めのみ | 本ドキュメント + check |
