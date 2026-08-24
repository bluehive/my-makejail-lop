#lang racket/base

;; =============================================================================
;; main.rkt — `#lang makejail` の言語本体（語彙 → AST → 効果列）
;;
;; 【パイプライン全体】（マクロは AST まで。副作用は executor）
;;   ソース (name)(from)(pkg)…
;;     → マクロ / トップレベル束縛（形の検査）
;;     → mj-plan（prefab AST）
;;     → plan->effects（効果のリスト）
;;     → runtime/executor.rkt（dry-run 表示 or FreeBSD 上で実行）
;;
;; 【設計の要点】
;;   - 平坦構文のみ（旧 jail-spec は受理しない）… Issue #1 / #4
;;   - agent モード既定: (cmd) と network host を禁止（量産の衝突・脱出路）
;;   - ロールバック無しは「実行方針」であり、このファイルのマクロの意味ではない
;;
;; 【参考 Wiki】
;;   lop-and-macros / creating-languages-in-racket / P02-agent-contract
;; =============================================================================

(require (for-syntax racket/base syntax/parse)
         racket/list
         racket/match
         racket/format
         racket/string
         racket/base)

;; -----------------------------------------------------------------------------
;; provide = この言語の「受理集合」の境界
;;   ここに無い識別子は #lang makejail の利用者ファイルから見えない
;;   （define / system などを export しない → エージェントが書けない）
;; -----------------------------------------------------------------------------
(provide
 ;; #%module-begin を差し替え = 「ファイル全体が1つの jail 計画」
 (rename-out [mj-module-begin #%module-begin]
             [mj-top-interaction #%top-interaction])
 #%app #%datum #%top
 ;; (from thin …) (option network host) などで使える記号
 thin zfs snap host
 ;; 表面語彙
 arg from option pkg copy sysrc service cmd human-cmd workdir volume mount
 name wiki-site
 pw-group pw-user smb-password template-subst
 ;; AST と API（raco / テスト / executor が require）
 (struct-out mj-plan)
 (struct-out mj-arg)
 (struct-out mj-from)
 (struct-out mj-option)
 (struct-out mj-step)
 plan-validate!
 plan->effects
 assemble-plan
 flatten-steps
 makejail-mode
 makejail-arg-bindings
 resolve-args
 agent-plan-ok?)

;; -----------------------------------------------------------------------------
;; AST（#:prefab … モジュール境界を越えて read/write・比較しやすい構造体）
;;   マクロ／語彙の最終成果物。実行コマンドそのものではない。
;; -----------------------------------------------------------------------------
(struct mj-arg (name has-default? default-val) #:prefab)
(struct mj-from (kind ref) #:prefab)       ; kind: 'thin | 'zfs-snap
(struct mj-option (key val) #:prefab)      ; name, dataset, network など
(struct mj-step (op args) #:prefab)        ; pkg / copy / wiki-site など1ステップ
(struct mj-plan (name args from options steps) #:prefab) ; ファイル全体の計画

;; 実行モード: 'agent（既定・厳しい）| 'human（--allow-cmd 等が要る）
(define makejail-mode (make-parameter 'agent))
;; --arg key=value や環境変数で埋める束縛
(define makejail-arg-bindings (make-parameter (hash)))

;; (from thin freebsd-14.3) の thin を識別子として書けるようにする値
(define thin 'thin)
(define zfs 'zfs)
(define snap 'zfs-snap)
(define host 'host)

;; =============================================================================
;; マクロ層（展開時 = コンパイル／モジュール読込時に形を触る）
;;   define-syntax + syntax-parse … 「構文オブジェクト → 構文オブジェクト」
;;   ここで落ちるエラーは pkg 失敗ではなく「言語が受理しない」
;; =============================================================================

;; (arg hostname)           … 必須（後で --arg か env が無いと resolve-args がエラー）
;; (arg share-host "/path") … デフォルト付き
(define-syntax (arg stx)
  (syntax-parse stx
    [(_ name:id) #'(mj-arg 'name #f #f)]
    [(_ name:id default-expr:expr) #'(mj-arg 'name #t default-expr)]))

;; (from zfs "pool/ds@snap") / (from thin freebsd-14.3)
;; kind:id と ref:str など、引数の「構文の種類」でパターンを分ける
(define-syntax (from stx)
  (syntax-parse stx
    [(_ kind:id ref:id)
     #'(mj-from (normalize-from-kind 'kind) (symbol->string 'ref))]
    [(_ kind:id ref:str)
     #'(mj-from (normalize-from-kind 'kind) ref)]
    [(_ kind:str ref:str)
     #'(mj-from (normalize-from-kind kind) ref)]))

(define (normalize-from-kind k)
  (define s (if (symbol? k) (symbol->string k) (~a k)))
  (case (string-downcase s)
    [("thin") 'thin]
    [("zfs" "snap" "zfs-snap" "snapshot") 'zfs-snap]
    [else (error 'from "kind must be thin or zfs, got ~a" k)]))

(define-syntax (option stx)
  (syntax-parse stx
    [(_ key:id) #'(mj-option 'key #t)]
    [(_ key:id val:id) #'(mj-option 'key 'val)]
    [(_ key:id val:expr) #'(mj-option 'key val)]
    [(_ key:str val:expr) #'(mj-option (string->symbol key) val)]))

;; (name "web") は内部的には option 'name として持つ
(define-syntax (name stx)
  (syntax-parse stx
    [(_ n:str) #'(mj-option 'name n)]
    [(_ n:id) #'(mj-option 'name (symbol->string 'n))]))

;; =============================================================================
;; 実行時関数の語彙（呼ばれると mj-step を返す）
;;   見た目は DSL だが、静的検査はマクロより弱い（plan-validate! で補う）
;;   LOP 的に「閉じたい」ものほどマクロ or provide 外しへ寄せるのが本筋
;; =============================================================================

(define (pkg . pkgs) (mj-step 'pkg (map ~a (flatten pkgs))))
(define (copy src dst) (mj-step 'copy (list (~a src) (~a dst))))
(define (sysrc var val) (mj-step 'sysrc (list (~a var) (~a val))))

(define-syntax (service stx)
  (syntax-parse stx
    [(_ svc:id) #'(mj-step 'service (list (symbol->string 'svc) 'start))]
    [(_ svc:id act:id) #'(mj-step 'service (list (symbol->string 'svc) 'act))]
    [(_ svc:str) #'(mj-step 'service (list svc 'start))]
    [(_ svc:expr act:expr) #'(mj-step 'service (list (~a svc) act))]))

;; --- 脱出路（Issue #4）: agent 既定では plan-validate! が拒否 ---
(define (cmd c . args)
  (mj-step 'cmd (cons (~a c) (map ~a args))))

(define (human-cmd c . args)
  (mj-step 'human-cmd (cons (~a c) (map ~a args))))

;; --- Samba 等: sh の pw/smbpasswd を語彙化（examples から cmd を消す） ---
(define (pw-group name #:gid gid)
  (mj-step 'pw-group (list (~a name) gid)))

(define (pw-user name
                 #:uid uid
                 #:group grp
                 #:home [home "/var/empty"]
                 #:shell [shell "/usr/sbin/nologin"]
                 #:create-home? [mh #t])
  (mj-step 'pw-user (list (~a name) uid (~a grp) (~a home) (~a shell) mh)))

;; パスワードはテンプレに直書きせず "{{samba-password}}" + --arg で注入
(define (smb-password user pass-or-template)
  (mj-step 'smb-password (list (~a user) (~a pass-or-template))))

(define (template-subst path old new)
  (mj-step 'template-subst (list (~a path) (~a old) (~a new))))

(define (workdir path) (mj-step 'workdir (list (~a path))))
(define (volume h j) (mj-step 'volume (list (~a h) (~a j))))
(define (mount h j #:readonly? [ro? #f]) (mj-step 'mount (list (~a h) (~a j) ro?)))

;; ドメイン語彙: 同一 jail 内 Caddy+DokuWiki（sed/cmd なし）
;; 1 ステップに畳み、flatten-steps で pkg/copy/volume/… に展開する
(define (wiki-site #:hostname hostname
                   #:data-host data-host
                   #:root [root "/usr/local/share/dokuwiki"]
                   #:caddyfile-src [caddy-src "files/Caddyfile"]
                   #:local-php-src [php-src "files/dokuwiki.local.php"]
                   #:php-pkgs [php-pkgs
                               '("php84" "php84-fpm" "php84-gd" "php84-xml" "php84-ctype"
                                 "php84-zlib" "php84-curl" "php84-session" "php84-mbstring"
                                 "php84-iconv" "php84-tokenizer")]
                   #:forbid-install? [forbid #t])
  (mj-step 'wiki-site
           (list (~a hostname)
                 (~a data-host)
                 (~a root)
                 (~a caddy-src)
                 (~a php-src)
                 (map ~a php-pkgs)
                 forbid)))

;; -----------------------------------------------------------------------------
;; 必須 arg の解決（--arg / デフォルト / MAKEJAIL_ARG_* 環境変数）
;; -----------------------------------------------------------------------------
(define (resolve-args plan [bindings (makejail-arg-bindings)])
  (define ht (make-hash))
  (when (hash? bindings)
    (for ([(k v) (in-hash bindings)])
      (hash-set! ht k v)))
  (for ([a (mj-plan-args plan)])
    (define n (mj-arg-name a))
    (cond
      [(hash-has-key? ht n) (void)]
      [(mj-arg-has-default? a) (hash-set! ht n (mj-arg-default-val a))]
      [else
       (define env-key (string-append "MAKEJAIL_ARG_" (symbol->string n)))
       (define ev (getenv env-key))
       (if ev
           (hash-set! ht n ev)
           (error 'makejail "missing required arg: ~a (use --arg or ~a)" n env-key))]))
  ht)

(define (network-is-host? opts)
  (for/or ([o opts])
    (and (memq (mj-option-key o) '(network virtualnet))
         (let ([v (mj-option-val o)])
           (or (eq? v 'host) (equal? v "host") (eq? v host))))))

(define (plan-has-cmd? plan)
  (for/or ([s (mj-plan-steps plan)])
    (and (mj-step? s) (memq (mj-step-op s) '(cmd human-cmd exec)))))

;; wiki-site → 具体ステップ列（マクロではなく実行時展開でも「計画の一部」）
(define (expand-wiki-site-step step)
  (match-define (mj-step 'wiki-site (list hn data root caddy-src php-src php-pkgs forbid)) step)
  (append
   (list (mj-step 'pkg (cons "caddy" (cons "dokuwiki" php-pkgs)))
         (mj-step 'copy (list caddy-src "/usr/local/www/Caddyfile"))
         (mj-step 'copy (list php-src (string-append root "/conf/local.php")))
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

(define (flatten-steps steps)
  (append*
   (for/list ([s steps])
     (match s
       [(mj-step 'wiki-site _) (expand-wiki-site-step s)]
       [else (list s)]))))

;; -----------------------------------------------------------------------------
;; 言語規則の実行時ゲート（agent/human）
;;   理想は provide 分離や #lang makejail/agent。現状はここで受理を切る。
;; -----------------------------------------------------------------------------
(define (plan-validate! p
                        #:mode [mode (makejail-mode)]
                        #:bindings [bindings (makejail-arg-bindings)]
                        #:allow-host-net? [allow-host? #f]
                        #:allow-cmd? [allow-cmd? #f])
  (unless (mj-plan? p) (error 'makejail "not a plan"))
  (unless (mj-from? (mj-plan-from p))
    (error 'makejail "missing (from thin|zfs ...)"))
  ;; 必須 arg
  (void (resolve-args p bindings))
  (define opts (mj-plan-options p))
  (define steps (mj-plan-steps p))
  (when (and (eq? mode 'agent) (plan-has-cmd? p) (not allow-cmd?))
    (error 'makejail
           "agent mode forbids (cmd)/(human-cmd)/(exec) — use wiki-site / pkg / volume / sysrc / service / pw-* / smb-password / template-subst only"))
  (when (and (eq? mode 'agent) (network-is-host? opts) (not allow-host?))
    (error 'makejail
           "agent mode forbids (option network host) for mass production — use thin-vnet (Issue #3) or human --allow-host-net"))
  (when (and (eq? mode 'human) (plan-has-cmd? p) (not allow-cmd?))
    (error 'makejail "(cmd)/(human-cmd) requires --allow-cmd (human escape hatch)"))
  p)

(define (agent-plan-ok? p #:bindings [b (makejail-arg-bindings)])
  (with-handlers ([exn:fail? (λ (_) #f)])
    (plan-validate! p #:mode 'agent #:bindings b)
    #t))

;; =============================================================================
;; plan->effects — AST → 効果列（まだホストは触らない）
;;   各効果は '(タグ 引数…) のリスト。executor が解釈する。
;;   phase: build | start | stop | destroy
;;   {{arg名}} は subst-str で --arg 束縛に置換
;; =============================================================================
(define (plan->effects p #:phase [phase 'build] #:bindings [bindings (makejail-arg-bindings)])
  (define args-h (resolve-args p bindings))
  (define name (mj-plan-name p))
  (define fr (mj-plan-from p))
  (define opts (mj-plan-options p))
  (define steps (flatten-steps (mj-plan-steps p)))
  (define effects '())
  (define (push! . xs) (set! effects (append effects (list xs))))
  (define (subst-str s)
    (for/fold ([acc (~a s)]) ([(k v) (in-hash args-h)])
      (string-replace acc (format "{{~a}}" k) (~a v) #:all? #t)))

  (case phase
    [(build)
     (push! 'info (format "plan=~a phase=build mode=~a" name (makejail-mode)))
     (for ([(k v) (in-hash args-h)])
       (push! 'arg k v))
     (match fr
       [(mj-from 'thin ref)
        (push! 'fetch-release ref)
        (push! 'create-thin-jail name ref)]
       [(mj-from 'zfs-snap ref)
        (define ds
          (or (for/or ([o opts] #:when (eq? (mj-option-key o) 'dataset))
                (~a (mj-option-val o)))
              (format "zroot/jails/~a" name)))
        (push! 'zfs-clone ref ds)
        (push! 'jail-create-path name (format "/~a" ds))])
     (for ([o opts] #:unless (memq (mj-option-key o) '(name dataset)))
       (case (mj-option-key o)
         [(nat) (push! 'net-nat name)]
         ;; 偽の expose 成功は出さない（Issue #1）
         [(expose) (push! 'net-expose-UNIMPLEMENTED name (mj-option-val o))]
         [(virtualnet) (push! 'net-virtualnet-frozen name (mj-option-val o))]
         [(network)
          (push! 'network-mode (mj-option-val o))
          (when (network-is-host? (list o))
            (push! 'warn-host-net "port collision risk if mass-producing"))]
         [(start) (push! 'jail-start name)]
         [else (push! 'option (mj-option-key o) (mj-option-val o))]))
     (for ([s steps])
       (match s
         [(mj-step 'workdir (list path)) (push! 'workdir name path)]
         [(mj-step 'pkg pkgs) (push! 'pkg-install name pkgs)]
         [(mj-step 'copy (list src dst))
          (push! 'copy-in name (subst-str src) (subst-str dst))]
         [(mj-step 'template-subst (list path old new))
          (push! 'template-subst name path old (subst-str new))]
         [(mj-step 'sysrc (list var val)) (push! 'sysrc name var (subst-str val))]
         [(mj-step 'service (list svc act)) (push! 'service name svc act)]
         [(mj-step 'cmd (list* c as)) (push! 'jexec-cmd name c as)]
         [(mj-step 'human-cmd (list* c as)) (push! 'jexec-cmd name c as)]
         [(mj-step 'pw-group (list g gid)) (push! 'pw-group name g gid)]
         [(mj-step 'pw-user (list u uid grp home shell mh))
          (push! 'pw-user name u uid grp (subst-str home) shell mh)]
         [(mj-step 'smb-password (list u pw))
          (push! 'smb-password name u (subst-str pw))]
         [(mj-step 'volume (list h j)) (push! 'volume name (subst-str h) (subst-str j))]
         [(mj-step 'mount (list h j ro?)) (push! 'mount name h j ro?)]
         [(mj-step 'wiki-harden (list root)) (push! 'wiki-harden name root)]
         [_ (push! 'unknown s)]))
     (push! 'done-build name)]
    [(start) (push! 'jail-start name) (push! 'done-start name)]
    [(stop) (push! 'jail-stop name) (push! 'done-stop name)]
    [(destroy)
     (push! 'jail-stop name)
     (match fr
       [(mj-from 'zfs-snap _)
        (define ds
          (or (for/or ([o opts] #:when (eq? (mj-option-key o) 'dataset))
                (~a (mj-option-val o)))
              (format "zroot/jails/~a" name)))
        (push! 'zfs-destroy ds)]
       [(mj-from 'thin _) (push! 'destroy-thin-jail name)])
     (push! 'done-destroy name)]
    [else (error 'plan->effects "bad phase ~a" phase)])
  effects)

;; -----------------------------------------------------------------------------
;; モジュール言語の心臓: #%module-begin の置き換え
;;   #lang makejail ファイルの全フォームを assemble-plan し current-plan を provide
;;   REPL 用 #%top-interaction は mj-module-begin に流さない
;; -----------------------------------------------------------------------------
(define-syntax (mj-top-interaction stx)
  (syntax-parse stx
    [(_ . form) #'(#%expression (begin . form))]))

(define-syntax (mj-module-begin stx)
  (syntax-parse stx
    [(_ form:expr ...)
     #'(#%module-begin
        (provide current-plan)
        (define current-plan (assemble-plan (list form ...)))
        (void))]))

;; トップレベル値の列 → 1 つの mj-plan
;;   二重 (from)、未知フォーム、from 欠落をここで拒否（平坦構文のみ）
(define (assemble-plan forms)
  (define nm #f)
  (define args '())
  (define fr #f)
  (define opts '())
  (define steps '())
  (define seen? #f)
  (for ([f forms])
    (cond
      [(or (void? f) (number? f) (eof-object? f) (not f)) (void)]
      [(mj-arg? f) (set! seen? #t) (set! args (append args (list f)))]
      [(mj-from? f)
       (set! seen? #t)
       (when fr (error 'makejail "duplicate (from ...) — flat syntax only, one from"))
       (set! fr f)]
      [(mj-option? f)
       (set! seen? #t)
       (set! opts (append opts (list f)))
       (when (eq? (mj-option-key f) 'name) (set! nm (~a (mj-option-val f))))]
      [(mj-step? f) (set! seen? #t) (set! steps (append steps (list f)))]
      [else (error 'makejail "unsupported top-level form (flat syntax only, no jail-spec): ~v" f)]))
  (unless seen?
    (set! fr (mj-from 'thin "unset"))
    (set! nm "empty"))
  (when (and seen? (not fr))
    (error 'makejail "missing (from thin|zfs ...) — required exactly once"))
  (mj-plan (or nm "jail0") args fr opts steps))
