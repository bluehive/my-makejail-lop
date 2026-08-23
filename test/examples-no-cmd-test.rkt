#lang racket/base

(require rackunit
         rackunit/text-ui
         "../main.rkt")

(define samba
  (assemble-plan
   (list (name "samba-fileserver")
         (from zfs "zroot/jails/base@clean")
         (option dataset "zroot/jails/samba-fileserver")
         (option network vnet-default)
         (arg samba-password "x")
         (arg share-host "/zroot/samba-share")
         (pkg "samba420")
         (pw-group "smbgrp" #:gid 2000)
         (pw-user "smbuser" #:uid 2000 #:group "smbgrp")
         (smb-password "smbuser" "{{samba-password}}")
         (sysrc "samba_server_enable" "YES")
         (service samba_server start))))

(define wiki
  (assemble-plan
   (list (name "dokuwiki-caddy")
         (from zfs "zroot/jails/base@clean")
         (option dataset "zroot/jails/dokuwiki-caddy")
         (option network vnet-default)
         (arg hostname "h.example")
         (arg data-host "/zroot/d")
         (wiki-site #:hostname "{{hostname}}" #:data-host "{{data-host}}"))))

(module+ test
  (run-tests
   (test-suite
    "examples without cmd"
    (test-case "samba agent-ok and effects"
      (check-true (agent-plan-ok? samba #:bindings (hash)))
      (define eff
        (plan->effects samba
                       #:bindings (hash 'samba-password "x"
                                        'share-host "/z")))
      (check-true (for/or ([e eff]) (eq? (car e) 'pw-user)))
      (check-true (for/or ([e eff]) (eq? (car e) 'smb-password)))
      (check-false (for/or ([e eff]) (eq? (car e) 'jexec-cmd))))
    (test-case "dokuwiki agent-ok no cmd"
      (check-true (agent-plan-ok? wiki #:bindings (hash)))
      (define eff
        (plan->effects wiki
                       #:bindings (hash 'hostname "h" 'data-host "/d")))
      (check-true (for/or ([e eff]) (eq? (car e) 'template-subst)))
      (check-false (for/or ([e eff]) (eq? (car e) 'jexec-cmd)))))))
