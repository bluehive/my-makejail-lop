#lang info

(define collection "makejail")
(define version "0.4.0")
(define pkg-desc "LOP DSL for FreeBSD jails (0.4 three-axes, Issue #9)")
(define pkg-authors '("Hiroki Kato (bluehive)" "Gemini (0.1 sketch)" "Grok (MVP direction)"))
(define license 'BSD-2-Clause)

(define deps '("base"))
(define build-deps '("rackunit-lib"))

(define raco-commands
  '(("makejail"
     (submod makejail/raco main)
     "Plan/build FreeBSD jails via #lang makejail (0.4 three-axes)"
     #f)))
