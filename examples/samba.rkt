#lang makejail

;; Samba — 0.4 instance + domain forms (no cmd)

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
