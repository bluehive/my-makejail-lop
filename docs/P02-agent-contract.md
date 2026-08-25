# P02 — エージェント契約（Issue #4）

> **0.4 接続:** エージェントが触るのは **個体スロットの穴埋め + 種族フォーム**。運用は言語受理。  
> 展開は言語側（sed 禁止）。host/in-jail セクションは不要（[Issue #9](https://github.com/bluehive/my-makejail-lop/issues/9) · Wiki three-axes-isomorphism）。


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

`name`, `from`, `option dataset`, `arg`（必須可）, `pkg`, `volume`, `sysrc`, `service`, `copy`, **`wiki-site`**, `mount`, **`pw-group`**, **`pw-user`**, **`smb-password`**, **`template-subst`**  
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

## 0.4 三軸（承認後）

| 軸 | エージェント |
|----|----------------|
| 個体 | `--arg` / スロットのみ変更 |
| 種族 | テンプレの `wiki-site` 等を変えず使う（種族メンテは別） |
| 運用 | 書けない（cmd・host ネット量産は受理外へ） |
