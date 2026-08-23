#lang makejail

;; Samba file server — no (cmd). Issue #4 / PR comment.
;; FreeBSD 15 / samba420. Prefer thin-vnet in production (Issue #3).

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

;; password via --arg samba-password=... (not hardcoded)
(smb-password "smbuser" "{{samba-password}}")

(sysrc "samba_server_enable" "YES")
(service samba_server start)
