#lang racket/base

(require rackunit
         rackunit/text-ui
         "../main.rkt")

(define dsl-tests
  (test-suite
   "makejail DSL AST Generation Tests"

   (test-case "Basic jail-spec macro expansion"
     (define plan
       (jail-spec "test-proxy"
         #:from "zroot/base@14.1"
         #:dataset "zroot/jails/test-proxy"
         #:network (vnet #:bridge "bridge0"
                         #:ip4 "192.168.1.10/24"
                         #:gw "192.168.1.1")
         #:mounts ((mount "/host/shared" "/jail/mnt" #:readonly? #t))
         #:expose (80 443)

         (pkg:install "nginx" "curl")
         (sysrc:set "nginx_enable" "YES")
         (service:start "nginx")
         (exec:run "echo" "hello")))

     (check-equal? (jail-plan-name plan) "test-proxy")
     (check-equal? (jail-plan-from-snap plan) "zroot/base@14.1")
     (check-equal? (jail-plan-dataset plan) "zroot/jails/test-proxy")

     (define net (jail-plan-vnet-cfg plan))
     (check-equal? (vnet-config-bridge net) "bridge0")
     (check-equal? (vnet-config-ip4 net) "192.168.1.10/24")
     (check-equal? (vnet-config-gw net) "192.168.1.1")

     (check-equal? (length (jail-plan-mounts plan)) 1)
     (check-equal? (mount-spec-ro? (car (jail-plan-mounts plan))) #t)
     (check-equal? (jail-plan-exposes plan) '(80 443))

     (define steps (jail-plan-steps plan))
     (check-equal? (length steps) 4)
     (check-true (step-pkg? (list-ref steps 0)))
     (check-equal? (step-pkg-pkgs (list-ref steps 0)) '("nginx" "curl"))
     (check-true (step-sysrc? (list-ref steps 1)))
     (check-true (step-service? (list-ref steps 2)))
     (check-true (step-exec? (list-ref steps 3))))))

(module+ test
  (run-tests dsl-tests))
