# 同一 Jail 内 Caddy + DokuWiki / Samba 例（FreeBSD 15）

> 記述: DeepSeek + P02 更新（**cmd 除去**）  
> ライセンス: BSD-2-Clause  
> 前提: FreeBSD 15 / `php84-*` / `samba420`  
> 量産ネット: [Issue #3](https://github.com/bluehive/my-makejail-lop/issues/3) · エージェント契約: [P02](https://github.com/bluehive/my-makejail-lop/blob/main/docs/P02-agent-contract.md)

**重要 (Issue #4 / PR #5):** 例から `(cmd …)` を廃止。  
- Wiki: `(wiki-site …)` / `template-subst`  
- Samba: `(pw-group)` `(pw-user)` `(smb-password)` + `(arg …)`

---

## 1. Caddy + DokuWiki（同一 Jail）

ファイル: `examples/dokuwiki-caddy.rkt`（agent 版と同形）

```racket
#lang makejail

(name "dokuwiki-caddy")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/dokuwiki-caddy")
(option network vnet-default)

(arg hostname)
(arg data-host)

(wiki-site #:hostname "{{hostname}}"
           #:data-host "{{data-host}}"
           #:forbid-install? #t)
```

```bash
raco makejail check examples/dokuwiki-caddy.rkt \
  --arg hostname=wiki.example.com \
  --arg data-host=/zroot/dokuwiki-data
```

---

## 2. Samba

ファイル: `examples/samba.rkt`

```racket
#lang makejail

(name "samba-fileserver")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/samba-fileserver")
(option network vnet-default)

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

`wiki-site` が `{{HOSTNAME}}` を `template-subst` で置換（**sed/cmd なし**）。

### dokuwiki.local.php / smb4.conf

リポジトリ `files/` を参照。

---

## 4. 実行手順

```sh
sudo mkdir -p /zroot/dokuwiki-data /zroot/samba-share
raco pkg install --link .
raco makejail build examples/dokuwiki-caddy.rkt --dry-run \
  --arg hostname=wiki.example.com --arg data-host=/zroot/dokuwiki-data
# FreeBSD 上のみ:
# raco makejail build examples/dokuwiki-caddy.rkt --apply --arg ...
```

---

## 5. 注意

| 項目 | 内容 |
|------|------|
| pkg 版 | `php84` / `samba420` が無い場合は `pkg search` で読み替え |
| ネットワーク | `vnet-default` は **プレースホルダ**（#3 未実装）。host は agent 禁止 |
| パスワード | Samba は `--arg samba-password=` のみ（DSL に平文を書かない） |
| ZFS | `base@clean` がホストに必要 |

---

## 関連

- [Overview](Overview) · [使い方](使い方) · [bsd-appsと比較](bsd-appsと比較)  
- [Issue #4](https://github.com/bluehive/my-makejail-lop/issues/4)  
