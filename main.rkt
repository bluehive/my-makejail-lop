#lang racket/base

;; makejail 0.2 — Grok-order MVP prototype
;; Issue #1: pivot from Gemini VNET-first pipeline.
;; Beautiful Racket: domain concepts as syntax; cheap experiments.

(require (for-syntax racket/base
                     syntax/parse
                     racket/syntax)
         racket/list
         racket/match
         racket/format
         racket/string)

(provide
 (rename-out [mj-module-begin #%module-begin]
             [mj-top-interaction #%top-interaction])
 #%app #%datum #%top
 ;; keywords usable as bare ids in from/option
 thin zfs snap host
 ;; surface
 arg from option pkg copy sysrc service cmd workdir volume mount
 name
 ;; API
 (struct-out mj-plan)
 (struct-out mj-arg)
 (struct-out mj-from)
 (struct-out mj-option)
 (struct-out mj-step)
 ;; current-plan is provided by each #lang makejail module
 plan-validate!
 plan->effects
 assemble-plan)

(struct mj-arg (name has-default? default-val) #:prefab)
(struct mj-from (kind ref) #:prefab)
(struct mj-option (key val) #:prefab)
(struct mj-step (op args) #:prefab)
(struct mj-plan (name args from options steps) #:prefab)

;; bare tokens for (from thin freebsd-14.3)
(define thin 'thin)
(define zfs 'zfs)
(define snap 'zfs-snap)
(define host 'host)

(define-syntax (arg stx)
  (syntax-parse stx
    [(_ name:id)
     #'(mj-arg 'name #f #f)]
    [(_ name:id default-expr:expr)
     #'(mj-arg 'name #t default-expr)]))

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
    [(_ key:id)
     #'(mj-option 'key #t)]
    [(_ key:id val:id)
     #'(mj-option 'key 'val)]
    [(_ key:id val:expr)
     #'(mj-option 'key val)]
    [(_ key:str val:expr)
     #'(mj-option (string->symbol key) val)]))

(define-syntax (name stx)
  (syntax-parse stx
    [(_ n:str) #'(mj-option 'name n)]
    [(_ n:id) #'(mj-option 'name (symbol->string 'n))]))

(define (pkg . pkgs)
  (mj-step 'pkg (map ~a (flatten pkgs))))

(define (copy src dst)
  (mj-step 'copy (list (~a src) (~a dst))))

(define (sysrc var val)
  (mj-step 'sysrc (list (~a var) (~a val))))

(define-syntax (service stx)
  (syntax-parse stx
    [(_ svc:id)
     #'(mj-step 'service (list (symbol->string 'svc) 'start))]
    [(_ svc:id act:id)
     #'(mj-step 'service (list (symbol->string 'svc) 'act))]
    [(_ svc:str)
     #'(mj-step 'service (list svc 'start))]
    [(_ svc:expr act:expr)
     #'(mj-step 'service (list (~a svc) act))]))

(define (cmd c . args)
  (mj-step 'cmd (cons (~a c) (map ~a args))))

(define (workdir path)
  (mj-step 'workdir (list (~a path))))

(define (volume h j)
  (mj-step 'volume (list (~a h) (~a j))))

(define (mount h j #:readonly? [ro? #f])
  (mj-step 'mount (list (~a h) (~a j) ro?)))

(define (plan-validate! p)
  (unless (mj-plan? p)
    (error 'makejail "not a plan"))
  (unless (mj-from? (mj-plan-from p))
    (error 'makejail "missing (from thin|zfs ...) — required exactly once"))
  p)

(define (plan->effects p #:phase [phase 'build])
  (plan-validate! p)
  (define name (mj-plan-name p))
  (define fr (mj-plan-from p))
  (define opts (mj-plan-options p))
  (define steps (mj-plan-steps p))
  (define effects '())
  (define (push! . xs) (set! effects (append effects (list xs))))

  (case phase
    [(build)
     (push! 'info (format "plan=~a phase=build" name))
     (for ([a (mj-plan-args p)])
       (push! 'arg (mj-arg-name a)
              (if (mj-arg-has-default? a) (mj-arg-default-val a) #f)))
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
     (for ([o opts]
           #:unless (memq (mj-option-key o) '(name dataset)))
       (case (mj-option-key o)
         [(nat) (push! 'net-nat name)]
         [(expose) (push! 'net-expose name (mj-option-val o))]
         [(virtualnet) (push! 'net-virtualnet-frozen name (mj-option-val o))]
         [(start) (push! 'jail-start name)]
         [(overwrite) (push! 'overwrite (mj-option-val o))]
         [(network) (push! 'network-mode (mj-option-val o))]
         [else (push! 'option (mj-option-key o) (mj-option-val o))]))
     (define wd #f)
     (for ([s steps])
       (match s
         [(mj-step 'workdir (list path))
          (set! wd path)
          (push! 'workdir name path)]
         [(mj-step 'pkg pkgs) (push! 'pkg-install name pkgs)]
         [(mj-step 'copy (list src dst))
          (push! 'copy-in name src dst)]
         [(mj-step 'sysrc (list var val)) (push! 'sysrc name var val)]
         [(mj-step 'service (list svc act)) (push! 'service name svc act)]
         [(mj-step 'cmd (list* c as)) (push! 'jexec name c as)]
         [(mj-step 'volume (list h j)) (push! 'volume name h j)]
         [(mj-step 'mount (list h j ro?)) (push! 'mount name h j ro?)]
         [_ (push! 'unknown s)]))
     (push! 'done-build name)]
    [(start)
     (push! 'jail-start name)
     (push! 'done-start name)]
    [(stop)
     (push! 'jail-stop name)
     (push! 'done-stop name)]
    [(destroy)
     (push! 'jail-stop name)
     (match fr
       [(mj-from 'zfs-snap _)
        (define ds
          (or (for/or ([o opts] #:when (eq? (mj-option-key o) 'dataset))
                (~a (mj-option-val o)))
              (format "zroot/jails/~a" name)))
        (push! 'zfs-destroy ds)]
       [(mj-from 'thin _)
        (push! 'destroy-thin-jail name)])
     (push! 'done-destroy name)]
    [else (error 'plan->effects "bad phase ~a" phase)])
  effects)

(define-syntax (mj-top-interaction stx)
  (syntax-parse stx
    [(_ . form)
     ;; REPL / test harness must NOT go through mj-module-begin
     #'(#%expression (begin . form))]))

(define-syntax (mj-module-begin stx)
  (syntax-parse stx
    [(_ form:expr ...)
     #'(#%module-begin
        (provide current-plan)
        (define current-plan
          (assemble-plan (list form ...)))
        (void))]))

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
       (when fr (error 'makejail "duplicate (from ...)"))
       (set! fr f)]
      [(mj-option? f)
       (set! seen? #t)
       (set! opts (append opts (list f)))
       (when (eq? (mj-option-key f) 'name)
         (set! nm (~a (mj-option-val f))))]
      [(mj-step? f) (set! seen? #t) (set! steps (append steps (list f)))]
      [else (error 'makejail "bad top-level form: ~v" f)]))
  ;; Harness may call language hooks with empty body — ignore
  (unless seen?
    (set! fr (mj-from 'thin "unset"))
    (set! nm "∅"))
  (plan-validate!
   (mj-plan (or nm "jail0") args fr opts steps)))
