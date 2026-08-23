#lang info

(define collection "makejail")
(define version "0.1.0")
(define pkg-desc "A Language-Oriented Programming (LOP) DSL for FreeBSD Jail automation")
(define pkg-authors '("Hiroki Kato (bluehive)" "Gemini (design/spec)"))
(define license 'BSD-2-Clause)

(define deps '("base"))
(define build-deps '("rackunit-lib"))

(define raco-commands
  '(("makejail" makejail/raco "Build and manage FreeBSD Jails via DSL" #f)))
