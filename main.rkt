#lang racket/base

(require (for-syntax racket/base
                     syntax/parse)
         racket/list)

(provide (rename-out [makejail-module-begin #%module-begin])
         #%app
         #%datum
         #%top
         #%top-interaction
         jail-spec
         vnet
         mount
         expose
         zfs:clone
         pkg:install
         sysrc:set
         service:start
         file:copy
         exec:run
         ;; =========================================================
         ;; [STUB]: 将来的な拡張構文のエクスポート予定地
         ;; =========================================================
         ;; build-arg
         ;; when:step
         ;; unless:step
         (struct-out vnet-config)
         (struct-out jail-plan)
         (struct-out mount-spec)
         (struct-out step-pkg)
         (struct-out step-sysrc)
         (struct-out step-service)
         (struct-out step-copy)
         (struct-out step-exec))

;; --- Prefab 構造体（AST） ---
(struct vnet-config (bridge ip4 gw) #:prefab)
(struct mount-spec (host-path jail-path ro?) #:prefab)
(struct jail-plan (name from-snap dataset vnet-cfg mounts exposes steps)
  #:prefab)

(struct step-pkg (pkgs) #:prefab)
(struct step-sysrc (var val) #:prefab)
(struct step-service (action name) #:prefab)
(struct step-copy (src dst) #:prefab)
(struct step-exec (cmd args) #:prefab)

;; --- プリミティブ関数 ---
(define (vnet #:bridge bridge #:ip4 ip4 #:gw gw)
  (vnet-config bridge ip4 gw))

(define (mount host-path jail-path #:readonly? [ro? #f])
  (mount-spec host-path jail-path ro?))

(define (expose . ports)
  (flatten ports))

;; Placeholder for documentation / future zfs step form
(define (zfs:clone from-snap dataset)
  (list 'zfs:clone from-snap dataset))

(define (pkg:install . pkgs)
  (step-pkg (flatten pkgs)))

(define (sysrc:set var val)
  (step-sysrc var val))

(define (service:start name)
  (step-service 'start name))

(define (file:copy src dst)
  (step-copy src dst))

(define (exec:run cmd . args)
  (step-exec cmd args))

;; =================================================================
;; [STUB]: 条件分岐やパラメータ化（Build Arguments）用スタブ
;; =================================================================
;; (struct step-when (condition steps) #:prefab)
;; (define-syntax-rule (when:step cond-expr body ...)
;;   (step-when cond-expr (list body ...)))

;; --- 構文定義 ---
(define-syntax (jail-spec stx)
  (syntax-parse stx
    [(_ name:str
        (~alt (~once (~seq #:from from-snap:str))
              (~once (~seq #:dataset dataset:str))
              (~once (~seq #:network net-expr:expr))
              (~optional
               (~seq #:mounts (mount-expr:expr ...))
               #:defaults ([(mount-expr 1) null]))
              (~optional
               (~seq #:expose (port-expr:expr ...))
               #:defaults ([(port-expr 1) null])))
        ...
        body-step:expr ...)
     #'(jail-plan name
                  from-snap
                  dataset
                  net-expr
                  (list mount-expr ...)
                  (list port-expr ...)
                  (list body-step ...))]))

(define-syntax (makejail-module-begin stx)
  (syntax-parse stx
    [(_ form:expr ...+)
     #'(#%module-begin
        (provide current-plan)
        (define current-plan
          (begin form ...)))]))
