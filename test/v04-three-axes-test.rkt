#lang racket/base

(require rackunit
         rackunit/text-ui
         racket/hash
         "../main.rkt")

(define (wiki-plan #:hn [hn "{{hostname}}"] #:dh [dh "{{data-host}}"])
  (assemble-plan
   (list (from zfs "zroot/base@c")
         (option network vnet-default)
         (instance #:name "w1" #:hostname hn #:data-host dh)
         (arg hostname)
         (arg data-host)
         (wiki-site))))

(module+ test
  (run-tests
   (test-suite
    "v0.4 three-axes"
    (test-case "dataset derived from name"
      (define p (wiki-plan))
      (define ds
        (for/or ([o (mj-plan-options p)])
          (and (eq? (mj-option-key o) 'dataset) (mj-option-val o))))
      (check-equal? ds "zroot/jails/w1"))
    (test-case "family expand via dynamic-require"
      (define p (wiki-plan))
      (check-true (agent-plan-ok? p #:bindings (hash 'hostname "h.example" 'data-host "/d")))
      (define eff
        (plan->effects p #:bindings (hash 'hostname "h.example" 'data-host "/d")))
      (check-true (for/or ([e eff]) (eq? (car e) 'template-subst)))
      (check-true (for/or ([e eff]) (eq? (car e) 'pkg-install)))
      (check-false (for/or ([e eff]) (eq? (car e) 'jexec-cmd))))
    (test-case "hostname single-source conflict"
      (define p
        (assemble-plan
         (list (from zfs "a@b")
               (option network vnet-default)
               (instance #:name "x" #:hostname "one.example" #:data-host "/d")
               (arg hostname)
               (arg data-host)
               (wiki-site #:hostname "other.example" #:data-host "/d"))))
      (check-exn
       exn:fail?
       (λ ()
         (plan-validate! p #:mode 'agent
                         #:bindings (hash 'hostname "one.example" 'data-host "/d")))))
    (test-case "wiki-site pulls slot templates"
      (define p (wiki-plan))
      (define st
        (for/or ([s (mj-plan-steps p)])
          (and (eq? (mj-step-op s) 'wiki-site) s)))
      (check-equal? (car (mj-step-args st)) "{{hostname}}")))))
