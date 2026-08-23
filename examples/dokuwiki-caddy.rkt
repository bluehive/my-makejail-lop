#lang makejail

;; Caddy + DokuWiki (same jail) — no (cmd)/sed.
;; FreeBSD 15 / php84. Use --arg for hostname and data path.

(name "dokuwiki-caddy")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/dokuwiki-caddy")
(option network vnet-default)

(arg hostname)
(arg data-host)

(wiki-site #:hostname "{{hostname}}"
           #:data-host "{{data-host}}"
           #:forbid-install? #t)
