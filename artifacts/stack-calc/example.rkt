#lang s-exp "stack-calc.rkt"

;; Postfix only. No (3 + 4), no (+ 3 4), no define/require.

3 4 +          ; [7]
5 *            ; [35]
10 swap /      ; [3.5]
peek

clear
;; (1 + 2) * (3 - 4)  as postfix
1 2 +
3 4 -
*
print
