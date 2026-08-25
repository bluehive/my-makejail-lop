# P02 — エージェント契約（makejail 0.4）

仕様: [Issue #9](https://github.com/bluehive/my-makejail-lop/issues/9) · [three-axes-isomorphism](https://github.com/bluehive/my-makejail-lop/wiki/three-axes-isomorphism)

## 権限区分

| 役割 | 許可 | 禁止 |
|------|------|------|
| **人間** | フォーム設計、`--apply`、例外的に `--allow-cmd` / `--allow-host-net` | エージェント用テンプレに cmd を残すこと |
| **エージェント** | 個体スロットの穴埋め（`instance` / `arg` / `--arg`）と種族フォームの利用 | SSH、apply、生 Caddyfile 手編集、`(cmd)`、host ネット量産 |
| **実行器** | 効果列の apply / destroy | エージェントから直接呼ばれること |

## エージェントが書いてよい形

```racket
#lang makejail
(from zfs "zroot/jails/base@clean")
(option network vnet-default)
(instance #:name "…" #:hostname "{{hostname}}" #:data-host "{{data-host}}")
(arg hostname)
(arg data-host)
(wiki-site)
```

## CLI

```bash
raco makejail check examples/dokuwiki-caddy.rkt \
  --arg hostname=wiki.example.com \
  --arg data-host=/zroot/dokuwiki-data
```

## 合格条件

1. `raco makejail check` が成功する  
2. 効果列に `jexec-cmd` が無い  
3. `network host` が無い  

## 語彙

**常用:** `instance`, `arg`, `name`, `from`, `option`, `wiki-site`, `pkg`, `volume`, `sysrc`, `service`, `copy`, `pw-group`, `pw-user`, `smb-password`, `template-subst`  

**禁止（agent）:** `cmd`, `human-cmd`, `network host` 量産  
