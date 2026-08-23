#lang info

(define collection "makejail")
(define version "0.3.0")
(define pkg-desc "LOP DSL for FreeBSD Jail automation (P02 agent-safe)")
(define pkg-authors '("Hiroki Kato (bluehive)" "Gemini (0.1 sketch)" "Grok (MVP direction)"))
(define license 'BSD-2-Clause)

(define deps '("base"))
(define build-deps '("rackunit-lib"))

(define raco-commands
  '(("makejail"
     (submod makejail/raco main)
     "Plan/build FreeBSD jails via #lang makejail (P02 agent-safe)"
     #f)))
