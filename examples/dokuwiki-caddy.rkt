#lang makejail

;; 0.4: 個体スロット + 種族フォーム（展開は言語側 / family/dokuwiki）
;; host/in-jail セクションは設けない（Issue #9）

(from zfs "zroot/jails/base@clean")
(option network vnet-default)

(instance
 #:name "dokuwiki-caddy"
 #:hostname "{{hostname}}"
 #:data-host "{{data-host}}")

;; dataset は name から導出（二重指定しない）
(arg hostname)
(arg data-host)

(wiki-site)   ; hostname/data-host はスロットから
