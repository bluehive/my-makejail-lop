#lang makejail

;; Thin-jail oriented sketch (create-thin still TODO in runtime).
(name "web-thin")
(from thin freebsd-14.3)
(option network host)
(pkg "nginx")
(sysrc "nginx_enable" "YES")
(service nginx)
