#lang racket/base

(require racket/cmdline
         racket/file
         racket/path
         racket/match
         racket/string
         racket/hash
         "main.rkt"
         "runtime/executor.rkt")

(define dry-run? #t)
(define phase 'build)
(define mode 'agent)
(define allow-cmd? #f)
(define allow-host-net? #f)

(define (parse-argv argv)
  (define args (vector->list argv))
  (define bindings (hash))
  (define positional '())
  (let loop ([xs args])
    (match xs
      ['() (void)]
      [(list* "--dry-run" rest) (set! dry-run? #t) (loop rest)]
      [(list* "--apply" rest) (set! dry-run? #f) (loop rest)]
      [(list* "--agent" rest) (set! mode 'agent) (loop rest)]
      [(list* "--human" rest) (set! mode 'human) (loop rest)]
      [(list* "--allow-cmd" rest) (set! allow-cmd? #t) (loop rest)]
      [(list* "--allow-host-net" rest) (set! allow-host-net? #t) (loop rest)]
      [(list* "--phase" ph rest) (set! phase (string->symbol ph)) (loop rest)]
      [(list* "--arg" kv rest)
       (match (string-split kv "=")
         [(list k v)
          (set! bindings (hash-set bindings (string->symbol k) v))]
         [_ (error 'makejail "--arg needs key=value")])
       (loop rest)]
      [(list* s rest)
       (set! positional (append positional (list s)))
       (loop rest)]))
  (values bindings positional))

(define (load-plan path)
  (define complete (path->complete-path path))
  (define root (path-only complete))
  (define raw (dynamic-require complete 'current-plan))
  (values raw (or root (current-directory))))

(define (run-local plan root ph dry? bindings)
  (parameterize ([makejail-mode mode]
                 [makejail-arg-bindings bindings])
    (plan-validate! plan
                    #:mode mode
                    #:bindings bindings
                    #:allow-host-net? allow-host-net?
                    #:allow-cmd? allow-cmd?)
    (define plan2
      (struct-copy
       mj-plan plan
       [steps
        (for/list ([s (mj-plan-steps plan)])
          (match s
            [(mj-step 'copy (list src dst))
             (define p (build-path root src))
             (cond
               [(file-exists? p)
                (mj-step 'copy (list (file->string p) dst))]
               [(file-exists? src)
                (mj-step 'copy (list (file->string src) dst))]
               [else s])]
            [else s]))]))
    (execute-plan! plan2 #:phase ph #:dry-run? dry? #:bundle-root root
                   #:bindings bindings)
    (void)))

(define (usage)
  (eprintf "Usage: raco makejail <plan|check|build|start|stop|destroy> FILE\n")
  (eprintf "  --agent (default) | --human\n")
  (eprintf "  --allow-cmd | --allow-host-net\n")
  (eprintf "  --arg key=value   (repeatable; anywhere on argv)\n")
  (eprintf "  --dry-run | --apply | --phase build|start|stop|destroy\n")
  (exit 1))

(define (main)
  (define-values (bindings positional)
    (parse-argv (current-command-line-arguments)))
  (match positional
    [(list sub spec)
     (define-values (plan root) (load-plan spec))
     (case sub
       [("plan" "check")
        (run-local plan root 'build #t bindings)]
       [("build")
        (run-local plan root phase dry-run? bindings)]
       [("start") (run-local plan root 'start dry-run? bindings)]
       [("stop") (run-local plan root 'stop dry-run? bindings)]
       [("destroy") (run-local plan root 'destroy dry-run? bindings)]
       [else (usage)])]
    [_ (usage)]))

(module+ main (main))
