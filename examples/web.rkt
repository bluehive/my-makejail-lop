#lang makejail

(jail-spec "web-proxy"
  #:from "zroot/jails/base@14.1-clean"
  #:dataset "zroot/jails/web-proxy"
  #:network (vnet #:bridge "bridge0"
                  #:ip4 "192.168.1.50/24"
                  #:gw "192.168.1.1")
  #:mounts ((mount "/host/data" "/mnt/data" #:readonly? #t))
  #:expose (80 443)

  (pkg:install "nginx" "curl")
  (sysrc:set "nginx_enable" "YES")
  (file:copy "examples/templates/nginx.conf" "/usr/local/etc/nginx/nginx.conf")
  (service:start "nginx"))
