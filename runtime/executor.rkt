#lang racket/base

(require racket/system
         racket/format
         racket/string
         racket/port
         "../main.rkt")

(provide execute-jail-plan
         destroy-jail-plan)

(define (execute-jail-plan plan)
  (define name (jail-plan-name plan))
  (define from-snap (jail-plan-from-snap plan))
  (define dataset (jail-plan-dataset plan))
  (define vnet (jail-plan-vnet-cfg plan))
  (define mounts (jail-plan-mounts plan))

  ;; 1. ZFS クローン
  (printf "===> [1/5] ZFS クローン作成: ~a -> ~a\n" from-snap dataset)
  (system* "/sbin/zfs" "clone" from-snap dataset)

  ;; 2. nullfs マウント
  (for ([m mounts])
    (define full-dst (format "/~a~a" dataset (mount-spec-jail-path m)))
    (system* "/bin/mkdir" "-p" full-dst)
    (if (mount-spec-ro? m)
        (system* "/sbin/mount_nullfs" "-o" "ro"
                 (mount-spec-host-path m) full-dst)
        (system* "/sbin/mount_nullfs"
                 (mount-spec-host-path m) full-dst))
    (printf "===> [Mount] ~a -> ~a\n"
            (mount-spec-host-path m) full-dst))

  ;; 3. 動的 VNET 設定
  (printf "===> [2/5] ネットワーク動的設定 (VNET: ~a)\n" name)
  (define epair-out
    (string-trim
     (with-output-to-string
       (lambda () (system* "/sbin/ifconfig" "epair" "create")))))
  (define epair-a epair-out)
  (define epair-b (regexp-replace #rx"a$" epair-a "b"))

  (define bridge (vnet-config-bridge vnet))
  (system* "/sbin/ifconfig" bridge "addm" epair-a "up")
  (system* "/sbin/ifconfig" epair-a "up")

  ;; 4. VNET Jail 起動
  (printf "===> [3/5] VNET Jail 起動: ~a\n" name)
  (system* "/usr/sbin/jail" "-c"
           (format "name=~a" name)
           (format "path=/~a" dataset)
           "vnet=new"
           (format "vnet.interface=~a" epair-b)
           "persist")

  (system* "/usr/sbin/jexec" name "/sbin/ifconfig" epair-b
           (vnet-config-ip4 vnet) "up")
  (system* "/usr/sbin/jexec" name "/sbin/route" "add" "default"
           (vnet-config-gw vnet))

  ;; エラーログ初期化
  (system* "/usr/sbin/jexec" name "/bin/sh" "-c"
           "> /var/log/makejail-error.log")

  ;; 5. ステップ順次実行
  (printf "===> [4/5] ステップ実行開始\n")
  (for ([step (jail-plan-steps plan)]
        [idx (in-naturals 1)])
    (printf "\n--- Step [~a] ---\n" idx)
    (run-step name step))

  (when (pair? (jail-plan-exposes plan))
    (printf "\n===> [5/5] 公開予定ポート: ~a\n"
            (string-join (map ~a (jail-plan-exposes plan)) ", "))))

(define (destroy-jail-plan plan)
  (define name (jail-plan-name plan))
  (define dataset (jail-plan-dataset plan))

  (printf "===> Jail 停止中: ~a\n" name)
  (system* "/usr/sbin/jail" "-r" name)

  (printf "===> nullfs マウント解除中: ~a\n" dataset)
  (for ([m (jail-plan-mounts plan)])
    (define full-dst (format "/~a~a" dataset (mount-spec-jail-path m)))
    (system* "/sbin/umount" "-f" full-dst))

  (printf "===> ZFS データセット破棄中: ~a\n" dataset)
  (system* "/sbin/zfs" "destroy" "-R" dataset)
  (printf "[+] クリーンアップ完了: ~a\n" name))

(define (run-step jail-name step)
  (cond
    [(step-pkg? step)
     (apply run-jexec-with-live-log jail-name
            "/usr/sbin/pkg" "install" "-y" (step-pkg-pkgs step))]
    [(step-sysrc? step)
     (run-jexec-with-live-log
      jail-name "/usr/sbin/sysrc"
      (format "~a=~a" (step-sysrc-var step) (step-sysrc-val step)))]
    [(step-service? step)
     (run-jexec-with-live-log
      jail-name "/usr/sbin/service"
      (step-service-name step)
      (symbol->string (step-service-action step)))]
    [(step-copy? step)
     (define write-cmd
       (format "cat << 'EOF' > ~a\n~a\nEOF"
               (step-copy-dst step)
               (step-copy-src step)))
     (run-jexec-with-live-log jail-name "/bin/sh" "-c" write-cmd)]
    [(step-exec? step)
     (apply run-jexec-with-live-log jail-name
            (step-exec-cmd step) (step-exec-args step))]))

(define (run-jexec-with-live-log jail-name cmd . args)
  (define full-cmd
    (cons "/usr/sbin/jexec" (cons jail-name (cons cmd args))))
  (printf "$ ~a\n" (string-join full-cmd " "))
  (define ok? (apply system* full-cmd))
  (unless ok?
    (define log-cmd
      (format "echo 'FAILED: ~a ~a' >> /var/log/makejail-error.log"
              cmd (string-join (map ~a args) " ")))
    (system* "/usr/sbin/jexec" jail-name "/bin/sh" "-c" log-cmd)
    (eprintf "\n[ERROR] ステップ実行が失敗しました。中断します。\n")
    (eprintf "[INFO] Jail (~a) は稼働状態で保持されています。\n" jail-name)
    (exit 1)))
