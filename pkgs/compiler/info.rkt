#lang info

(define collection 'multi)

(define deps '("compiler-lib"))
(define implies '("compiler-lib"))

(define pkg-desc "Racket compilation tools, such as `raco exe'")

(define pkg-authors '(mflatt))

(define license
  '(Apache-2.0 OR MIT))
