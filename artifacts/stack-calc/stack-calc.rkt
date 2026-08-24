#lang racket/base

;; stack-calc — #lang stack calculator (vocabulary, not a function library)

(require (for-syntax racket/base
                     syntax/parse)
         (only-in racket/base
                  [+ r+]
                  [- r-]
                  [* r*]
                  [/ r/])
         racket/list
         racket/format
         racket/string)

(provide
 (rename-out [sc-module-begin #%module-begin]
             [sc-top-interaction #%top-interaction]
             [sc-datum #%datum]
             [sc-app #%app]
             [sc-top #%top])
 + - * / neg
 dup drop swap over clear
 print peek show)

(define the-stack '())

(define (push! v)
  (set! the-stack (append the-stack (list v))))

(define (pop!)
  (when (null? the-stack)
    (error 'stack-calc "stack underflow"))
  (define v (last the-stack))
  (set! the-stack (drop-right the-stack 1))
  v)

(define (peek-top)
  (when (null? the-stack)
    (error 'stack-calc "stack empty"))
  (last the-stack))

(define (show-stack)
  (printf "stack: [~a]\n"
          (string-join (map ~a the-stack) " ")))

(define (rneg x) (r- 0 x))

(define (apply-binop rfun)
  (λ ()
    (define b (pop!))
    (define a (pop!))
    (push! (rfun a b))))

(define (apply-unop rfun)
  (λ ()
    (push! (rfun (pop!)))))

;; Identifier macros: bare `+` at top level runs the word; `(+ 1 2)` errors.
(define-syntax (define-stack-word stx)
  (syntax-parse stx
    [(_ name:id expr)
     #'(begin
         (define impl expr)
         (define-syntax (name stx2)
           (syntax-parse stx2
             [_:id #'(impl)]
             [(_) #'(impl)]
             [(_ . _)
              (raise-syntax-error
               'stack-calc
               "stack word takes 0 arguments; use postfix (not parenthesized apply)"
               stx2)])))]))

(define-stack-word + (apply-binop r+))
(define-stack-word - (apply-binop r-))
(define-stack-word * (apply-binop r*))
(define-stack-word / (apply-binop r/))
(define-stack-word neg (apply-unop rneg))
(define-stack-word dup (λ () (push! (peek-top))))
(define-stack-word drop (λ () (void (pop!))))
(define-stack-word swap
  (λ ()
    (define b (pop!))
    (define a (pop!))
    (push! b)
    (push! a)))
(define-stack-word over
  (λ ()
    (define b (pop!))
    (define a (pop!))
    (push! a)
    (push! b)
    (push! a)))
(define-stack-word clear (λ () (set! the-stack '())))
(define-stack-word print (λ () (printf "~a\n" (pop!))))
(define-stack-word peek (λ () (printf "~a\n" (peek-top))))
(define-stack-word show (λ () (show-stack)))

(define-syntax (sc-datum stx)
  (syntax-parse stx
    [(_ . n:number) #'(push! (quote n))]
    [(_ . d)
     (raise-syntax-error 'stack-calc "only numbers may be pushed" #'d)]))

(define-syntax (sc-app stx)
  (syntax-parse stx
    [(_ . _)
     (raise-syntax-error
      'stack-calc
      "no application: postfix only (not (f x) or (3 + 4))"
      stx)]))

(define-syntax (sc-top stx)
  (syntax-parse stx
    [(_ . id:id)
     (raise-syntax-error
      'stack-calc
      (format "unknown word: ~a" (syntax-e #'id))
      #'id)]))

(define-syntax (sc-top-interaction stx)
  (syntax-parse stx
    [(_ . form) #'(#%expression form)]))

(define-syntax (sc-module-begin stx)
  (syntax-parse stx
    [(_ form ...)
     #'(#%module-begin
        form ...
        (printf "stack: [~a]\n"
                (string-join (map ~a the-stack) " ")))]))
