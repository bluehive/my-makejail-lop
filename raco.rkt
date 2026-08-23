#lang racket/base

(require racket/cmdline
         racket/file
         racket/system
         racket/port
         racket/match
         "main.rkt"
         "runtime/executor.rkt")

(define (bundle-plan-files plan)
  (define bundled-steps
    (for/list ([step (jail-plan-steps plan)])
      (if (step-copy? step)
          (step-copy (file->string (step-copy-src step))
                     (step-copy-dst step))
          step)))
  (struct-copy jail-plan plan [steps bundled-steps]))

(define (main)
  (command-line
   #:program "raco makejail"
   #:args (subcommand spec-path . rest-args)
   (define target-host (if (pair? rest-args) (car rest-args) #f))
   (define raw-plan
     (dynamic-require (path->complete-path spec-path) 'current-plan))
   (define plan (bundle-plan-files raw-plan))

   (case subcommand
     [("build")
      (dispatch-action plan target-host 'execute-jail-plan)]
     [("destroy")
      (dispatch-action plan target-host 'destroy-jail-plan)]
     [else
      (eprintf "不明なサブコマンド: ~a (build または destroy)\n" subcommand)
      (exit 1)])))

(define (dispatch-action plan target-host action-fn-sym)
  (if target-host
      (begin
        (printf "SSH 経由で ~a 実行中 -> ~a\n" action-fn-sym target-host)
        (define remote-cmd
          (format
           "ssh ~a 'racket -e \"(require makejail/runtime/executor) (~a (read))\"'"
           target-host
           action-fn-sym))
        (match-define (list p-in p-out _pid p-err p-ctrl)
          (process remote-cmd))
        (write plan p-out)
        (close-output-port p-out)
        (copy-port p-in (current-output-port))
        (copy-port p-err (current-error-port))
        (p-ctrl 'wait))
      (case action-fn-sym
        [(execute-jail-plan) (execute-jail-plan plan)]
        [(destroy-jail-plan) (destroy-jail-plan plan)])))

(module+ main
  (main))
