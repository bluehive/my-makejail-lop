# 同一 Jail 内 Caddy + DokuWiki / Samba 例（FreeBSD 15）

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause  
> 前提: FreeBSD 15 / `php84-*` / `samba420`（無ければ `pkg search` で読み替え）  
> 設計: [three-axes-isomorphism](three-axes-isomorphism) · [使い方](使い方)  
> ネット: [Issue #3 thin-vnet](https://github.com/bluehive/my-makejail-lop/issues/3) · 契約: [P02](https://github.com/bluehive/my-makejail-lop/blob/main/docs/P02-agent-contract.md)

**書き方の要点**

- **個体:** `(instance …)` + `(arg …)`  
- **種族:** `(wiki-site)` — pkg/sed は書かない  
- **運用:** agent 既定（cmd なし、`network host` なし）  
- dataset は name から導出  

---

## 1. Caddy + DokuWiki（同一 Jail）

ファイル: `examples/dokuwiki-caddy.rkt`

```racket
#lang makejail

(from zfs "zroot/jails/base@clean")
(option network vnet-default)

(instance
 #:name "dokuwiki-caddy"
 #:hostname "{{hostname}}"
 #:data-host "{{data-host}}")

(arg hostname)
(arg data-host)

(wiki-site)
```

```bash
sudo mkdir -p /zroot/dokuwiki-data

raco makejail check examples/dokuwiki-caddy.rkt \
  --arg hostname=wiki.example.com \
  --arg data-host=/zroot/dokuwiki-data

raco makejail build examples/dokuwiki-caddy.rkt --dry-run \
  --arg hostname=wiki.example.com \
  --arg data-host=/zroot/dokuwiki-data
```

言語が展開する内容（利用者が並べない）: caddy/dokuwiki/php84 系 pkg、Caddyfile の `{{HOSTNAME}}` 置換、volume、sysrc、service、wiki-harden。展開表は `family/dokuwiki.rkt`。

---

## 2. Samba

ファイル: `examples/samba.rkt`

```racket
#lang makejail

(from zfs "zroot/jails/base@clean")
(option network vnet-default)

(instance #:name "samba-fileserver")

(arg samba-password)
(arg share-host "/zroot/samba-share")

(pkg "samba420")
(copy "files/smb4.conf" "/usr/local/etc/smb4.conf")
(volume "{{share-host}}" "/mnt/share")

(pw-group "smbgrp" #:gid 2000)
(pw-user "smbuser"
         #:uid 2000
         #:group "smbgrp"
         #:home "/mnt/share/smbuser"
         #:shell "/usr/sbin/nologin"
         #:create-home? #t)
(smb-password "smbuser" "{{samba-password}}")

(sysrc "samba_server_enable" "YES")
(service samba_server start)
```

```bash
sudo mkdir -p /zroot/samba-share
raco makejail check examples/samba.rkt \
  --arg samba-password='…' \
  --arg share-host=/zroot/samba-share
```

---

## 3. テンプレート（`files/`）

### Caddyfile

```
{{HOSTNAME}} {
    root * /usr/local/share/dokuwiki
    php_fastcgi localhost:9000
    file_server
}
```

### dokuwiki.local.php / smb4.conf

リポジトリ `files/` を参照。

---

## 4. ディレクトリ

```
my-makejail-lop/
├── examples/
│   ├── dokuwiki-caddy.rkt
│   ├── dokuwiki-caddy-agent.rkt
│   ├── samba.rkt
│   └── nginx.rkt
├── family/
│   └── dokuwiki.rkt          # 種族展開表
└── files/
    ├── Caddyfile
    ├── dokuwiki.local.php
    └── smb4.conf
```

---

## 5. 停止・破棄

```sh
raco makejail stop examples/dokuwiki-caddy.rkt --apply \
  --arg hostname=wiki.example.com --arg data-host=/zroot/dokuwiki-data
raco makejail destroy examples/dokuwiki-caddy.rkt --apply \
  --arg hostname=wiki.example.com --arg data-host=/zroot/dokuwiki-data
```

---

## 6. 注意

| 項目 | 内容 |
|------|------|
| pkg 版 | `php84` / `samba420` が無ければ読み替え |
| ネット | `vnet-default` はプレースホルダ。host は agent 禁止 |
| 秘密 | Samba パスワードは `--arg` のみ |
| ZFS | `zroot/jails/base@clean` が必要 |

---

## 関連

- [Overview](Overview) · [使い方](使い方)  
- [three-axes-isomorphism](three-axes-isomorphism)  
- [dsl-design-principles](dsl-design-principles)  
