#lang makejail

(from thin freebsd-14.3)
(option network vnet-default)
(instance #:name "web-thin")
(pkg "nginx")
(sysrc "nginx_enable" "YES")
(service nginx start)
