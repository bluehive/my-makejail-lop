#lang makejail

;; Agent-safe DokuWiki + Caddy (same jail). Issue #4 / P02.
;; No (cmd). No host network. Required args must be supplied via --arg.

(name "dokuwiki-caddy")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/dokuwiki-caddy")

;; thin-vnet placeholder until Issue #3 is implemented (not host)
(option network vnet-default)

(arg hostname)
(arg data-host)

(wiki-site #:hostname "{{hostname}}"
           #:data-host "{{data-host}}"
           #:forbid-install? #t)
