#lang makejail

;; nginx — 0.4 個体 + 手順語彙（種族フォームなし）

(from zfs "zroot/jails/base@clean")
(option network vnet-default)

(instance #:name "web-nginx")

(pkg "nginx")
(sysrc "nginx_enable" "YES")
(copy "templates/nginx.conf" "/usr/local/etc/nginx/nginx.conf")
(service nginx start)
