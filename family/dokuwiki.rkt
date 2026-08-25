#lang racket/base

;; =============================================================================
;; family/dokuwiki.rkt — 種族「dokuwiki」の展開表（Issue #9 / 0.4）
;;
;; 編集点はここ 1 ファイル（種族軸 ρ=1）。
;; 個体スロット（hostname / data-host）は呼び出し側 wiki-site / instance から渡る。
;; main.rkt は dynamic-require で本モジュールを読む（循環回避）。
;; =============================================================================

(require racket/match
         racket/format
         racket/list
         (only-in "../main.rkt"
                  mj-step
                  mj-step?
                  mj-step-op
                  mj-step-args))

(provide expand-wiki-site-step
         dokuwiki-default-php-pkgs
         dokuwiki-default-root)

(define dokuwiki-default-root "/usr/local/share/dokuwiki")

(define dokuwiki-default-php-pkgs
  '("php84" "php84-fpm" "php84-gd" "php84-xml" "php84-ctype"
    "php84-zlib" "php84-curl" "php84-session" "php84-mbstring"
    "php84-iconv" "php84-tokenizer"))

;; mj-step 'wiki-site args:
;;   (hostname data-host root caddy-src php-src php-pkgs forbid)
(define (expand-wiki-site-step step)
  (unless (and (mj-step? step) (eq? (mj-step-op step) 'wiki-site))
    (error 'family/dokuwiki "not a wiki-site step: ~a" step))
  (match-define (mj-step 'wiki-site (list hn data root caddy-src php-src php-pkgs forbid)) step)
  (append
   (list (mj-step 'pkg (cons "caddy" (cons "dokuwiki" php-pkgs)))
         (mj-step 'copy (list caddy-src "/usr/local/www/Caddyfile"))
         (mj-step 'copy (list php-src (string-append root "/conf/local.php")))
         ;; hostname 単一ソース → 言語が template-subst を生成（利用側 sed 禁止）
         (mj-step 'template-subst (list "/usr/local/www/Caddyfile" "{{HOSTNAME}}" hn))
         (mj-step 'volume (list data (string-append root "/data")))
         (mj-step 'sysrc (list "php_fpm_enable" "YES"))
         (mj-step 'sysrc (list "caddy_enable" "YES"))
         (mj-step 'sysrc (list "caddy_config" "/usr/local/www/Caddyfile"))
         (mj-step 'service (list "php-fpm" 'start))
         (mj-step 'service (list "caddy" 'start)))
   (if forbid
       (list (mj-step 'wiki-harden (list root)))
       '())))
