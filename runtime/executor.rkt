#lang racket/base

;; =============================================================================
;; runtime/executor.rkt — 効果列の適用（実行器）
;;
;; 【このファイルの役割】
;;   main.rkt の plan->effects が作った「効果」リストを受け取り、
;;   - dry-run: 表示だけ（どの OS でも安全）
;;   - --apply: FreeBSD 上で zfs / jail / jexec などを実行
;;
;; 【やってはいけないこと（設計）】
;;   - ここで DSL の構文検査をしない（それは main のマクロ / plan-validate!）
;;   - マクロから直接 system を呼ばない（dry-run と検査が黒箱になる）
;;
;; 【失敗時】
;;   自動ロールバックはしない（Issue #1）。ok?/exit がメッセージを出して exit 1。
;;
;; 【呼び出し元】
;;   raco.rkt の plan/build/… が execute-plan! を呼ぶ
;; =============================================================================

(require racket/match
         racket/format
         racket/string
         racket/system
         racket/port
         racket/file
         "../main.rkt")

(provide execute-plan!
         effects->display
         freebsd-host?)

;; 実実行は FreeBSD のみ（開発用に MAKEJAIL_FORCE_FREEBSD=1 も可）
(define (freebsd-host?)
  (define s
    (with-handlers ([exn:fail? (λ (_) "")])
      (string-trim
       (with-output-to-string
         (λ () (system* "/usr/bin/uname" "-s"))))))
  (or (string-ci=? s "FreeBSD")
      (equal? (getenv "MAKEJAIL_FORCE_FREEBSD") "1")))

;; 効果リストを人間向け1行ずつの文字列に
(define (effects->display effects)
  (string-join
   (for/list ([e effects])
     (format "• ~a" (string-join (map ~a e) " ")))
   "\n"))

;; -----------------------------------------------------------------------------
;; 入口: 計画 → 効果 → 表示 →（必要なら）順に run-effect!
;;   bindings: --arg で埋めたハッシュ（plan->effects に渡す）
;; -----------------------------------------------------------------------------
(define (execute-plan! plan
                       #:phase [phase 'build]
                       #:dry-run? [dry-run? #t]
                       #:bundle-root [bundle-root (current-directory)]
                       #:bindings [bindings (hash)])
  (define effects (plan->effects plan #:phase phase #:bindings bindings))
  (printf "==> makejail phase=~a dry-run=~a jail=~a\n"
          phase dry-run? (mj-plan-name plan))
  (displayln (effects->display effects))
  (newline)
  (cond
    [dry-run?
     (printf "[dry-run] no host changes.\n")
     effects]
    [(not (freebsd-host?))
     (eprintf "[error] real execute requires FreeBSD (or MAKEJAIL_FORCE_FREEBSD=1).\n")
     (eprintf "        Re-run with --dry-run on this host.\n")
     (exit 2)]
    [else
     ;; 副作用はここだけ。失敗しても前の効果は戻さない
     (for ([e effects])
       (run-effect! e #:bundle-root bundle-root))
     effects]))

;; -----------------------------------------------------------------------------
;; 1 効果 = 1 マッチ枝
;;   タグ（第1要素）は plan->effects が push! したシンボルと対応
;; -----------------------------------------------------------------------------
(define (run-effect! e #:bundle-root bundle-root)
  (match e
    [(list 'info msg) (printf "INFO ~a\n" msg)]

    ;; --- ベース jail の用意（thin は MVP 未完・zfs clone が実経路） ---
    [(list 'fetch-release ref)
     (printf "TODO fetch-release ~a (use existing base or appjail-style release dir)\n" ref)
     (void)]
    [(list 'create-thin-jail name ref)
     (printf "TODO create-thin-jail name=~a release=~a\n" name ref)
     (eprintf "thin path not fully automated in 0.2 MVP — use (from zfs ...)\n")]
    [(list 'zfs-clone snap ds)
     (ok?/exit (system* "/sbin/zfs" "clone" snap ds)
               (format "zfs clone ~a ~a" snap ds))]
    [(list 'jail-create-path name path)
     (ok?/exit
      (system* "/usr/sbin/jail" "-c"
               (format "name=~a" name)
               (format "path=~a" path)
               "host.hostname" name
               "persist")
      (format "jail -c ~a" name))]
    [(list 'jail-start name)
     (system* "/usr/sbin/service" "jail" "start" name)
     (void)]
    [(list 'jail-stop name)
     (system* "/usr/sbin/jail" "-r" name)
     (void)]

    ;; --- jail 内の設定（いずれも jexec） ---
    [(list 'pkg-install name pkgs)
     (ok?/exit
      (apply system* "/usr/sbin/jexec" name
             "/usr/sbin/pkg" "install" "-y" pkgs)
      (format "pkg install in ~a" name))]
    [(list 'sysrc name var val)
     (ok?/exit
      (system* "/usr/sbin/jexec" name "/usr/sbin/sysrc" (format "~a=~a" var val))
      "sysrc")]
    [(list 'service name svc act)
     (ok?/exit
      (system* "/usr/sbin/jexec" name "/usr/sbin/service" svc (~a act))
      "service")]
    [(list 'copy-in name src dst)
     ;; bundle-root 上のファイル、または plan 側で埋め込んだ本文
     (define content
       (let ([p (build-path bundle-root src)])
         (cond
           [(file-exists? p) (file->string p)]
           [(file-exists? src) (file->string src)]
           [else src])))
     (define script
       (format "cat << 'MAKEJAIL_EOF' > ~a\n~a\nMAKEJAIL_EOF" dst content))
     (ok?/exit
      (system* "/usr/sbin/jexec" name "/bin/sh" "-c" script)
      "copy-in")]
    [(list 'jexec name c as)
     (ok?/exit
      (apply system* "/usr/sbin/jexec" name c as)
      "jexec")]

    ;; --- volume / destroy ---
    [(list 'mount name host jp ro?)
     (define ds-path
       (format "/zroot/jails/~a~a" name jp)) ; パス規約は best-effort
     (system* "/bin/mkdir" "-p" ds-path)
     (if ro?
         (system* "/sbin/mount_nullfs" "-o" "ro" host ds-path)
         (system* "/sbin/mount_nullfs" host ds-path))
     (void)]
    [(list 'volume name host jp)
     (run-effect! (list 'mount name host jp #f) #:bundle-root bundle-root)]
    [(list 'umount name jp) (void)]
    [(list 'zfs-destroy ds)
     (system* "/sbin/zfs" "destroy" "-R" ds)
     (void)]
    [(list 'destroy-thin-jail name)
     (system* "/usr/sbin/jail" "-r" name)
     (void)]

    ;; --- ドメイン効果（P02）: 完全自動化は段階的 ---
    [(list 'template-subst name path old new)
     (printf "template-subst jail=~a path=~a ~a -> ~a\n" name path old new)
     ;; TODO: --apply 時は jexec 内でファイルを書き換え
     (void)]
    [(list 'wiki-harden name root)
     (printf "wiki-harden ~a root=~a (forbid install.php / lock conf — TODO details)\n" name root)]
    [(list 'pw-group name g gid)
     (ok?/exit
      (system* "/usr/sbin/jexec" name "/usr/sbin/pw" "groupadd" "-n" g "-g" (~a gid))
      "pw-group")]
    [(list 'pw-user name u uid grp home shell mh)
     (define base
       (list "/usr/sbin/jexec" name "/usr/sbin/pw" "useradd"
             "-n" u "-u" (~a uid) "-g" grp "-d" home "-s" shell))
     (ok?/exit (apply system* (if mh (append base (list "-m")) base)) "pw-user")]
    [(list 'smb-password name u pw)
     ;; DSL に平文を書かず --arg から渡す想定。apply 時のみ jail 内 smbpasswd
     (define tmp (format "/tmp/mj-smb-~a" u))
     (define body (string-append u "\n" pw "\n" pw "\n"))
     (define script
       (string-append "cat > " tmp " << 'MJEOF'\n" body "MJEOF\n"
                      "/usr/local/bin/smbpasswd -s -a " u " < " tmp "\n"
                      "rm -f " tmp "\n"))
     (ok?/exit
      (system* "/usr/sbin/jexec" name "/bin/sh" "-c" script)
      "smb-password")]
    [(list 'jexec-cmd name c as)
     ;; (cmd …) 由来。agent では plan-validate! が先に拒否する
     (ok?/exit (apply system* "/usr/sbin/jexec" name c as) "jexec-cmd")]

    ;; --- ネット（複雑化は凍結。偽成功は出さない） ---
    [(list 'warn-host-net msg) (printf "WARN host-net: ~a\n" msg)]
    [(list 'net-expose-UNIMPLEMENTED name ports)
     (eprintf "ERROR: expose not implemented (no fake success) jail=~a ports=~a\n" name ports)
     (exit 1)]
    [(list 'net-nat name) (printf "TODO net-nat ~a (pf later)\n" name)]
    [(list 'net-expose name ports) (printf "TODO net-expose ~a ~a\n" name ports)]
    [(list 'net-virtualnet-frozen name v)
     (printf "TODO virtualnet ~a ~a (frozen per Issue #1)\n" name v)]
    [(list 'network-mode m) (printf "network-mode ~a\n" m)]
    [(list 'arg n d) (printf "arg ~a default=~a\n" n d)]
    [(list 'workdir _ path) (printf "WORKDIR ~a\n" path)]
    [(list 'overwrite _ _) (void)]
    [(list 'option k v) (printf "OPTION ~a=~a\n" k v)]
    [(list 'done-build name) (printf "[ok] build planned/executed for ~a\n" name)]
    [(list 'done-start name) (printf "[ok] start ~a\n" name)]
    [(list 'done-stop name) (printf "[ok] stop ~a\n" name)]
    [(list 'done-destroy name) (printf "[ok] destroy ~a\n" name)]
    [(list 'unknown-step s) (eprintf "unknown step ~a\n" s)]
    [_ (printf "skip ~a\n" e)]))

;; system* 等の成否。失敗時はロールバックせず終了（Issue #1 の契約）
(define (ok?/exit ok? msg)
  (unless ok?
    (eprintf "\n[ERROR] failed: ~a\n" msg)
    (eprintf "[INFO] no automatic rollback (see Issue #1). Inspect jail/logs.\n")
    (exit 1))
  #t)
