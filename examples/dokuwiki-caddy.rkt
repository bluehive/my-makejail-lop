#lang makejail

;; Caddy + DokuWiki（同一 Jail 内）
;; FreeBSD 15 想定。ベーススナップショット名は環境に合わせて変更。
;; ネットワーク: MVP は host 共有。本番は thin-vnet（Issue #3）推奨。

(name "dokuwiki-caddy")
(from zfs "zroot/jails/base@clean")
(option dataset "zroot/jails/dokuwiki-caddy")
(option network host)

; ---------- パッケージ（FreeBSD 15 / PHP 8.4 想定） ----------
(pkg "caddy")
(pkg "php84")
(pkg "php84-fpm")
(pkg "php84-gd")
(pkg "php84-xml")
(pkg "php84-ctype")
(pkg "php84-zlib")
(pkg "php84-curl")
(pkg "php84-session")
(pkg "php84-mbstring")
(pkg "php84-iconv")
(pkg "php84-tokenizer")
(pkg "dokuwiki")

; ---------- 設定ファイル（ホスト側 files/ を用意） ----------
(copy "files/Caddyfile" "/usr/local/www/Caddyfile")
(copy "files/dokuwiki.local.php" "/usr/local/share/dokuwiki/conf/local.php")

; Caddyfile のプレースホルダ {{HOSTNAME}} を置換
(cmd "sed" "-i" "" "s/{{HOSTNAME}}/wiki.example.com/g" "/usr/local/www/Caddyfile")

; ---------- データ永続化 ----------
; ホスト側で事前に: mkdir -p /zroot/dokuwiki-data
(volume "/zroot/dokuwiki-data" "/usr/local/share/dokuwiki/data")
; (volume "/zroot/dokuwiki-conf" "/usr/local/share/dokuwiki/conf")

(sysrc "php_fpm_enable" "YES")
(sysrc "caddy_enable" "YES")
(sysrc "caddy_config" "/usr/local/www/Caddyfile")

(service php-fpm start)
(service caddy start)
