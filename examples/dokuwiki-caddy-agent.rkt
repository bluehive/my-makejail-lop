#lang makejail

;; Agent-safe 0.4 — same shape as dokuwiki-caddy.rkt

(from zfs "zroot/jails/base@clean")
(option network vnet-default)

(instance
 #:name "dokuwiki-caddy"
 #:hostname "{{hostname}}"
 #:data-host "{{data-host}}")

(arg hostname)
(arg data-host)

(wiki-site #:forbid-install? #t)
