#lang racket/base

(require rackunit
         rackunit/text-ui
         "../main.rkt")

(define tests
  (test-suite
   "makejail Grok MVP"

   (test-case "from thin + steps assemble"
     (define p
       (assemble-plan
        (list (name "t1")
              (from thin freebsd-14.3)
              (option network host)
              (pkg "nginx" "curl")
              (sysrc "nginx_enable" "YES")
              (service nginx start))))
     (check-equal? (mj-plan-name p) "t1")
     (check-equal? (mj-from-kind (mj-plan-from p)) 'thin)
     (check-equal? (mj-from-ref (mj-plan-from p)) "freebsd-14.3")
     (check-equal? (length (mj-plan-steps p)) 3)
     (define eff (plan->effects p #:phase 'build))
     (check-true (pair? eff))
     (check-true (for/or ([e eff]) (eq? (car e) 'create-thin-jail))))

   (test-case "duplicate from errors"
     (check-exn
      exn:fail?
      (λ ()
        (assemble-plan
         (list (from thin a)
               (from thin b))))))

   (test-case "missing from errors"
     (check-exn
      exn:fail?
      (λ ()
        (assemble-plan (list (name "x") (pkg "y"))))))

   (test-case "zfs effects include clone"
     (define p
       (assemble-plan
        (list (name "z1")
              (from zfs "zroot/base@c")
              (option dataset "zroot/jails/z1")
              (pkg "nginx"))))
     (define eff (plan->effects p))
     (check-true (for/or ([e eff]) (eq? (car e) 'zfs-clone))))

   (test-case "destroy phase"
     (define p
       (assemble-plan
        (list (name "z1")
              (from zfs "zroot/base@c")
              (option dataset "zroot/jails/z1"))))
     (define eff (plan->effects p #:phase 'destroy))
     (check-true (for/or ([e eff]) (eq? (car e) 'zfs-destroy))))))

(module+ test
  (run-tests tests))
