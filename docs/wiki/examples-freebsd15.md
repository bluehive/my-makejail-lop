# 同一 Jail 内 Caddy + DokuWiki / Samba 例（FreeBSD 15）

> 記述: DeepSeek  
> ライセンス: BSD-2-Clause  
> 前提: FreeBSD 15。パッケージは PHP 8.4（`php84-*`）、Samba 4.20（`samba420`）想定。  
> 量産ネット: [Issue #3 thin-vnet](https://github.com/bluehive/my-makejail-lop/issues/3)（**同一 jail 内 Caddy+DokuWiki**）

---

## 1. Caddy + DokuWiki（同一 Jail 内）

ファイル: [`examples/dokuwiki-caddy.rkt`](https://github.com/bluehive/my-makejail-lop/blob/main/examples/dokuwiki-caddy.rkt)

```racket
#lang makejail

(name "dokuwiki-caddy")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/dokuwiki-caddy")

; MVP: ホスト共有。本番は thin-vnet（Issue #3）推奨
(option network host)

(pkg "caddy")
(pkg "php84")
(pkg "php84-fpm")
(pkg "php84-gd")
(pkg "php84-xml")
(pkg "php84-ctype")
(pkg "php84-zlib")
(pkg "php84-curl")
(pkg "php84-session")
(pkg "php84-mbstring")
(pkg "php84-iconv")
(pkg "php84-tokenizer")
(pkg "dokuwiki")

(copy "files/Caddyfile" "/usr/local/www/Caddyfile")
(copy "files/dokuwiki.local.php" "/usr/local/share/dokuwiki/conf/local.php")

(cmd "sed" "-i" "" "s/{{HOSTNAME}}/wiki.example.com/g" "/usr/local/www/Caddyfile")

; ホスト側で事前: mkdir -p /zroot/dokuwiki-data
(volume "/zroot/dokuwiki-data" "/usr/local/share/dokuwiki/data")

(sysrc "php_fpm_enable" "YES")
(sysrc "caddy_enable" "YES")
(sysrc "caddy_config" "/usr/local/www/Caddyfile")

(service php-fpm start)
(service caddy start)
```

---

## 2. Samba（スタンドアロン）

ファイル: [`examples/samba.rkt`](https://github.com/bluehive/my-makejail-lop/blob/main/examples/samba.rkt)

```racket
#lang makejail

(name "samba-fileserver")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/samba-fileserver")
(option network host)

(pkg "samba420")
(copy "files/smb4.conf" "/usr/local/etc/smb4.conf")
(volume "/zroot/samba-share" "/mnt/share")

(cmd "pw" "groupadd" "-n" "smbgrp" "-g" "2000")
(cmd "pw" "useradd" "-n" "smbuser" "-u" "2000" "-g" "smbgrp" "-m" "-s" "/usr/sbin/nologin" "-d" "/mnt/share/smbuser")
; 実験用平文。本番は (arg ...) 注入を推奨
(cmd "/bin/sh" "-c" "echo 'smbuser:password123' | /usr/local/bin/smbpasswd -s -a smbuser")

(sysrc "samba_server_enable" "YES")
(service samba_server start)
```

---

## 3. テンプレート（`files/`）

### 3.1 `files/Caddyfile`

`{{HOSTNAME}}` は `.rkt` 内の `sed` で置換。

```
{{HOSTNAME}} {
    root * /usr/local/share/dokuwiki
    php_fastcgi localhost:9000
    file_server
}
```

### 3.2 `files/dokuwiki.local.php`

```php
<?php
$conf['savedir'] = '/usr/local/share/dokuwiki/data';
```

### 3.3 `files/smb4.conf`

```
[global]
workgroup = WORKGROUP
server string = Samba Server (FreeBSD 15 Jail)
security = user
map to guest = Bad User

[share]
path = /mnt/share
valid users = smbuser
read only = no
guest ok = no
create mask = 0644
directory mask = 0755
```

---

## 4. ディレクトリ構成

```
my-makejail-lop/
├── examples/
│   ├── dokuwiki-caddy.rkt
│   ├── samba.rkt
│   └── nginx.rkt
└── files/
    ├── Caddyfile
    ├── dokuwiki.local.php
    └── smb4.conf
```

---

## 5. ビルド＆実行（FreeBSD 15 ホスト）

### 5.1 ホスト側ディレクトリ

```sh
sudo mkdir -p /zroot/dokuwiki-data
sudo mkdir -p /zroot/samba-share
```

### 5.2 Dry-run

```sh
raco makejail build examples/dokuwiki-caddy.rkt --dry-run
raco makejail build examples/samba.rkt --dry-run
```

### 5.3 適用

```sh
raco makejail build examples/dokuwiki-caddy.rkt --apply
raco makejail build examples/samba.rkt --apply
```

### 5.4 停止・破棄

```sh
raco makejail stop examples/dokuwiki-caddy.rkt --apply
raco makejail destroy examples/dokuwiki-caddy.rkt --apply

raco makejail stop examples/samba.rkt --apply
raco makejail destroy examples/samba.rkt --apply
```

---

## 6. FreeBSD 15 移行の注意（必読）

| 注意 | 内容 |
|------|------|
| パッケージ版 | PHP は `php84-*`、Samba は `samba420` 想定。無い場合は `pkg search php` / `pkg search samba` で読み替え |
| ネットワーク | `(option network host)` は 80/443・SMB(139/445) がホストと競合しうる。本番は **thin-vnet（#3）** で独立 IP を |
| 平文パスワード | Samba の例は実験用。本番は `(arg …)` で外部注入 |
| ZFS スナップ | `zroot/jails/base@clean` が無いと失敗。`zfs list -t snapshot` で確認し、無ければ `zfs snapshot …` |
| パッケージ | 未リンクならプロジェクトルートで `raco pkg install --link .` |

### 平文を避ける例（概念）

```racket
(arg samba-password "defaultpass")
; 実際の注入は executor / 環境に合わせて安全に組み立てること
```

---

## 7. コードの意図（LOP）

| 観点 | 内容 |
|------|------|
| 宣言的 | bsd-apps の「手順」ではなく「何を」に焦点 |
| AST | `(pkg …)` `(service …)` → 構造体 → executor が展開 |
| 移植性 | 同じ DSL で Caddy/DokuWiki/Samba を統一的に定義 |

全コード再掲はリポジトリの `examples/` と `files/` を参照。FreeBSD 15 では **pkg 版**と **ZFS スナップショット名**を中心に確認してください。

---

## 関連

- [Overview](Overview)  
- [使い方](使い方)  
- [bsd-appsと比較](bsd-appsと比較)  
- [Issue #3 thin-vnet](https://github.com/bluehive/my-makejail-lop/issues/3)  
EOF
