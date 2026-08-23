#lang makejail

;; Samba ファイルサーバー（スタンドアロン）
;; FreeBSD 15 / Samba 4.20 想定。NetBIOS 等のため network host（MVP）。
;; 本番は thin-vnet（Issue #3）を検討。平文パスワードは実験用 — 本番は arg 注入を推奨。

(name "samba-fileserver")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/samba-fileserver")
(option network host)

(pkg "samba420")

(copy "files/smb4.conf" "/usr/local/etc/smb4.conf")

; ホスト側で事前に: mkdir -p /zroot/samba-share
(volume "/zroot/samba-share" "/mnt/share")

(cmd "pw" "groupadd" "-n" "smbgrp" "-g" "2000")
(cmd "pw" "useradd" "-n" "smbuser" "-u" "2000" "-g" "smbgrp" "-m" "-s" "/usr/sbin/nologin" "-d" "/mnt/share/smbuser")

; 実験用の平文例。本番は (arg samba-password ...) 等で外部注入すること
(cmd "/bin/sh" "-c" "echo 'smbuser:password123' | /usr/local/bin/smbpasswd -s -a smbuser")

(sysrc "samba_server_enable" "YES")
(service samba_server start)
