#lang info

(define collection "makejail")
(define version "0.2.0")
(define pkg-desc "LOP DSL for FreeBSD Jail app automation (Grok-order MVP)")
(define pkg-authors '("Hiroki Kato (bluehive)" "Gemini (0.1 sketch)" "Grok (MVP direction)"))
(define license 'BSD-2-Clause)

(define deps '("base"))
(define build-deps '("rackunit-lib"))

(define raco-commands
  '(("makejail" makejail/raco "Plan/build/start/stop/destroy FreeBSD jails via #lang makejail" #f)))
