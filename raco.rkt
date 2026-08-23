#lang racket/base

(require racket/cmdline
         racket/file
         racket/path
         racket/match
         racket/system
         racket/port
         "main.rkt"
         "runtime/executor.rkt")

(define dry-run? #t)
(define phase 'build)

(define (bundle-copies plan root)
  (define new-steps
    (for/list ([s (mj-plan-steps plan)])
      (match s
        [(mj-step 'copy (list src dst))
         (define p (build-path root src))
         (define content
           (cond
             [(file-exists? p) (file->string p)]
             [(file-exists? src) (file->string src)]
             [else (error 'makejail "copy source not found: ~a (root=~a)" src root)]))
         (mj-step 'copy (list content dst))]
        [else s])))
  (struct-copy mj-plan plan [steps new-steps]))

(define (load-plan path)
  (define complete (path->complete-path path))
  (define root (path-only complete))
  (define raw (dynamic-require complete 'current-plan))
  (values (bundle-copies raw (or root (current-directory)))
          (or root (current-directory))))

(define (run-local plan root ph dry?)
  (execute-plan! plan #:phase ph #:dry-run? dry? #:bundle-root root)
  (void))

(define (run-ssh plan host ph dry?)
  (when dry?
    (printf "SSH dry-run: showing local effect list (remote not contacted).\n")
    (run-local plan (current-directory) ph #t)
    (printf "Remote would be: ~a\n" host)
    (exit 0))
  (printf "SSH execute -> ~a phase=~a\n" host ph)
  (define remote
    (format
     "ssh ~a 'racket -e \"(require makejail/runtime/executor makejail) (execute-plan! (read) #:phase (quote ~a) #:dry-run? #f)\"'"
     host ph))
  (match-define (list in out _pid err ctrl) (process remote))
  (write plan out)
  (close-output-port out)
  (copy-port in (current-output-port))
  (copy-port err (current-error-port))
  (exit (or (ctrl 'exit-code) 0)))

(define (main)
  (define sub #f)
  (define spec #f)
  (define host #f)
  (command-line
   #:program "raco makejail"
   #:once-each
   [("--dry-run") "Print effects only (default)"
                  (set! dry-run? #t)]
   [("--apply") "Really execute on FreeBSD host"
                (set! dry-run? #f)]
   [("--phase") ph "build|start|stop|destroy (default build)"
                (set! phase (string->symbol ph))]
   #:args (subcommand spec-path . rest)
   (set! sub subcommand)
   (set! spec spec-path)
   (when (pair? rest) (set! host (car rest))))

  (define-values (plan root) (load-plan spec))
  (case sub
    [("plan" "build")
     (when (equal? sub "plan") (set! dry-run? #t))
     (if host
         (run-ssh plan host phase dry-run?)
         (run-local plan root phase dry-run?))]
    [("start")
     (if host (run-ssh plan host 'start dry-run?) (run-local plan root 'start dry-run?))]
    [("stop")
     (if host (run-ssh plan host 'stop dry-run?) (run-local plan root 'stop dry-run?))]
    [("destroy")
     (if host (run-ssh plan host 'destroy dry-run?) (run-local plan root 'destroy dry-run?))]
    [else
     (eprintf "Usage: raco makejail <plan|build|start|stop|destroy> FILE.rkt [user@host]\n")
     (eprintf "  --dry-run (default) | --apply   --phase build|start|stop|destroy\n")
     (exit 1)]))

(module+ main
  (main))
