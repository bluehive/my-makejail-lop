#lang racket/base

(require rackunit
         rackunit/text-ui
         racket/hash
         "../main.rkt")

(define tests
  (test-suite
   "P02 agent-safe DSL"

   (test-case "flat assemble + wiki-site expands in effects"
     (define p
       (assemble-plan
        (list (name "w1")
              (from zfs "zroot/base@c")
              (option dataset "zroot/jails/w1")
              (option network vnet-default)
              (arg hostname "wiki.example.com")
              (arg data-host "/zroot/data")
              (wiki-site #:hostname "{{hostname}}"
                         #:data-host "{{data-host}}"))))
     (check-true (agent-plan-ok? p #:bindings (hash)))
     (define eff
       (parameterize ([makejail-mode 'agent]
                      [makejail-arg-bindings (hash)])
         (plan-validate! p #:mode 'agent)
         (plan->effects p)))
     (check-true (for/or ([e eff]) (eq? (car e) 'pkg-install)))
     (check-true (for/or ([e eff]) (eq? (car e) 'template-subst)))
     (check-false (for/or ([e eff]) (eq? (car e) 'jexec-cmd))))

   (test-case "agent rejects cmd"
     (define p
       (assemble-plan
        (list (name "x")
              (from zfs "a@b")
              (option network vnet-default)
              (cmd "echo" "no"))))
     (check-false (agent-plan-ok? p)))

   (test-case "agent rejects host net"
     (define p
       (assemble-plan
        (list (name "x")
              (from zfs "a@b")
              (option network host)
              (pkg "caddy"))))
     (check-false (agent-plan-ok? p)))

   (test-case "missing required arg"
     (define p
       (assemble-plan
        (list (name "x")
              (from zfs "a@b")
              (option network vnet-default)
              (arg hostname)
              (pkg "caddy"))))
     (check-exn exn:fail?
                (λ () (resolve-args p (hash)))))

   (test-case "human allow-cmd permits cmd"
     (define p
       (assemble-plan
        (list (name "x")
              (from zfs "a@b")
              (option network host)
              (cmd "true"))))
     (check-not-exn
      (λ ()
        (plan-validate! p #:mode 'human #:allow-cmd? #t #:allow-host-net? #t))))))

(module+ test
  (run-tests tests))
