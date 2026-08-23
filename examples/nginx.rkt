#lang makejail

;; Grok-style surface (MVP). Default path: dry-run on any host.
;; Real apply: FreeBSD + --apply (zfs from recommended until thin is done).

(name "web-nginx")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/web-nginx")
(option network host)
;; virtualnet / nat / expose are accepted but frozen/TODO in executor (Issue #1)

(pkg "nginx")
(sysrc "nginx_enable" "YES")
(copy "templates/nginx.conf" "/usr/local/etc/nginx/nginx.conf")
(service nginx start)
