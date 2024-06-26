(module promise '#%kernel
(#%require "define-et-al.rkt" "qq-and-or.rkt" "cond.rkt"
           "more-scheme.rkt"
           "define.rkt"
           (rename "define-struct.rkt" define-struct define-struct*)
           (for-syntax '#%kernel
                       "cond.rkt" "qq-and-or.rkt"
                       "define.rkt"
                       "struct.rkt"
                       "stxcase-scheme.rkt"
                       "name.rkt")
           '#%unsafe)
(#%provide force promise? promise-forced? promise-running?
           (rename lazy* lazy)
           (rename delay* delay)
           ;; provided to create extensions
           (struct promise ()) (protect pref pset!) prop:force reify-result
           promise-forcer
           promise-printer
           (struct running ()) (struct reraise ())
           (for-syntax delayer delayer?)
           prop:running?)

;; This module implements "lazy" (composable) promises and a `force'
;; that is iterated through them.

;; This is similar to the *new* version of srfi-45 -- see the
;; post-finalization discussion at http://srfi.schemers.org/srfi-45/ for
;; more details; specifically, this version is the `lazy2' version from
;; http://srfi.schemers.org/srfi-45/post-mail-archive/msg00013.html.
;; Note: if you use only `force'+`delay' it behaves as in Scheme (except
;; that `force' is identity for non promise values), and `force'+`lazy'
;; are sufficient for implementing the lazy language.

;; unsafe accessors
(define-syntax pref  (syntax-rules () [(_ p  ) (unsafe-struct-ref  p 0  )]))
(define-syntax pset! (syntax-rules () [(_ p x) (unsafe-struct-set! p 0 x)]))

;; ----------------------------------------------------------------------------
;; Forcers

;; `force/composable' iterates on composable promises
;; * (force X) = X for non promises
;; * does not deal with multiple values in the composable case
;; note: measuring time invested divided by the number of lines, this innocent
;; looking piece of code is by far the leader of that competition -- handle
;; with extreme care.
(define (force/composable root)
  (let ([v (pref root)])
    (cond
      [(procedure? v)
       ;; mark the root as running: avoids cycles, and no need to keep banging
       ;; the root promise value; it makes this non-r5rs, but the only
       ;; practical uses of these things could be ones that use state to avoid
       ;; an infinite loop.  (See the generic forcer below.)
       ;; (careful: avoid holding a reference to the thunk, to allow
       ;; safe-for-space loops)
       (pset! root (make-running (object-name v)))
       (call-with-exception-handler
        (lambda (e) (pset! root (make-reraise e)) e)
        (lambda ()
          ;; iterate carefully through chains of composable promises
          (let loop ([v (v)]) ; does not handle multiple values!
            (cond [(composable-promise? v)
                   (let ([v* (pref v)])
                     (pset! v root) ; share with root
                     (cond [(procedure? v*) (loop (v*))]
                           ;; it must be a list of one value (because
                           ;; composable promises never hold multiple values),
                           ;; or a composable promise
                           [(pair? v*) (pset! root v*) (unsafe-car v*)]
                           ;; note: for the promise case we could jump only to
                           ;; the last `let' (for `v*'), but that makes the
                           ;; code heavier, and runs slower (probably goes over
                           ;; some inlining/unfolding threshold).
                           [else (loop v*)]))]
                  ;; reached a non-composable promise: share and force it now
                  [(promise? v) (pset! root v) (force v)]
                  ;; error here for "library approach" (see above URL)
                  [else (pset! root (list v)) v]))))]
      ;; try to make the order efficient, with common cases first
      [(pair? v) (if (null? (unsafe-cdr v)) (unsafe-car v) (apply values v))]
      ;; follow all sharings (and shortcut directly to the right force)
      [(composable-promise? v) (force/composable v)]
      [(null? v) (values)]
      [(promise? v) (force v)] ; non composable promise is forced as usual
      [else (error 'force "composable promise with invalid contents: ~e" v)])))

;; convenient utility for any number of stored values or a raised value.
(define (reify-result v)
  (cond [(pair? v) (if (null? (unsafe-cdr v)) (unsafe-car v) (apply values v))]
        [(null? v) (values)]
        [(reraise? v) (v)]
        [else (error 'force "promise with invalid contents: ~e" v)]))

;; generic force for "old-style" promises -- they're still useful in
;; that they allow multiple values.  In general, this is slower, but has
;; more features.  (They could allow self loops, but this means holding
;; on to the procedure and its resources while it is running, and lose
;; the ability to know that it is running; the second can be resolved
;; with a new kind of `running' value that can be used again, but the
;; first cannot be solved.  I still didn't ever see any use for them, so
;; they're still forbidden -- throw a "reentrant promise" error.)
(define (force/generic promise)
  (reify-result
   (let ([v (pref promise)])
     (if (procedure? v)
       (begin
         (pset! promise (make-running (object-name v)))
         (call-with-exception-handler
          (lambda (e) (pset! promise (make-reraise e)) e)
          (lambda ()
            (let ([vs (call-with-values v list)]) (pset! promise vs) vs))))
       v))))

;; dispatcher for composable promises, generic promises, and other values
(define (force v)
  (let ([forcer (promise-forcer v #f)])
    (if forcer
        (forcer v) ; dispatch to specific forcer
        v))) ; different from srfi-45: identity for non-promises

;; ----------------------------------------------------------------------------
;; Struct definitions

;; generic promise printer
(define (promise-printer promise port write?)
  (let loop ([v (pref promise)])
    (cond
      [(reraise? v)
       (let ([r (reraise-val v)])
         (if (exn? r)
           (fprintf port (if write? "#<promise!exn!~s>" "#<promise!exn!~a>")
                    (exn-message r))
           (fprintf port (if write? "#<promise!raise!~s>" "#<promise!raise!~a>")
                    r)))]
      [(running? v)
       (let ([r (running-name v)])
         (if r
           (fprintf port "#<promise:!running!~a>" r)
           (fprintf port "#<promise:!running>")))]
      [(procedure? v)
       (cond [(object-name v)
              => (lambda (n) (fprintf port "#<promise:~a>" n))]
             [else (display "#<promise>" port)])]
      [(promise? v) (loop (pref v))] ; hide sharing
      ;; values
      [(null? v) (fprintf port "#<promise!(values)>")]
      [(null? (cdr v))
       (fprintf port (if write? "#<promise!~s>" "#<promise!~a>") (car v))]
      [else (display "#<promise!(values" port)
            (let ([fmt (if write? " ~s" " ~a")])
              (for-each (lambda (x) (fprintf port fmt x)) v))
            (display ")>" port)])))

;; property value for the right forcer to use
(define-values [prop:force promise-forcer]
  (let-values ([(prop pred? get) ; no need for the predicate
                (make-struct-type-property 'forcer
                  (lambda (v info)
                    (unless (and (procedure? v)
                                 (procedure-arity-includes? v 1))
                      (raise-argument-error 'prop:force "(any/c . -> . any)" v))
                    v)
                  null #t)])
    (values prop get)))

;; A promise value can hold
;; - (list <value> ...): forced promise (possibly multiple-values)
;;        - composable promises deal with only one value
;; - <promise>: a shared (redirected) promise that points at another one
;;        - possible only with composable promises
;; - <thunk>: usually a delayed promise,
;;        - can also hold a `running' thunk that will throw a reentrant error
;;        - can also hold a raising-a-value thunk on exceptions and other
;;          `raise'd values (actually, applicable structs for printouts)
;; First, a generic struct, which is used for all promise-like values
(define-struct promise ([val #:mutable])
  #:property prop:custom-write promise-printer
  #:property prop:force force/generic)
;; Then, a subtype for composable promises
(define-struct (composable-promise promise) ()
  #:property prop:force force/composable)

  ;; !!!HACK!!!
  ;; stepper-syntax-property : like syntax property, but adds properties to an
  ;; association list associated with the syntax property 'stepper-properties
  ;; Had to re-define this because of circular dependencies
  ;; (also defined in stepper/private/syntax-property.rkt), it should
  ;; either be defined as a generic tool, or removed.
  (define-for-syntax stepper-syntax-property
    (case-lambda 
      [(stx tag) 
       (letrec-values ([(stepper-props) (syntax-property stx 'stepper-properties)])
         (if stepper-props
             (letrec-values ([(table-lookup) (assq tag stepper-props)])
               (if table-lookup
                   (cadr table-lookup)
                   #f))
             #f))]
      [(stx tag new-val) 
       (letrec-values ([(stepper-props) (syntax-property stx 'stepper-properties)])
         (syntax-property stx 'stepper-properties
                          (cons (list tag new-val)
                                (if stepper-props stepper-props '()))))]))

;; template for all delay-like constructs
;; (with simple keyword matching: keywords is an alist with default exprs)
(begin-for-syntax
  (struct delayer (maker keywords)
    #:property prop:procedure
    (lambda (self stx)
      (define keywords (delayer-keywords self))

      (define (parse-exprs+kwds stxs)
        (let loop ([stxs stxs]
                   [exprs '()]
                   [kwds '()])
          (syntax-case stxs ()
            [()
             (values (reverse exprs) (reverse kwds))]
            [(expr . rest)
             (not (keyword? (syntax-e #'expr)))
             (loop #'rest (cons #'expr exprs) kwds)]
            [(kw-stx expr . rest)
             (not (keyword? (syntax-e #'expr)))
             (let ([kw (syntax-e #'kw-stx)])
               (cond
                 [(not (assq kw keywords))
                  (raise-syntax-error #f "unrecognized option" stx #'kw-stx)]
                 [(assq kw kwds)
                  (raise-syntax-error #f "duplicate option" stx #'kw-stx)]
                 [else
                  (loop #'rest exprs (cons (cons kw #'expr) kwds))]))]
            [(kw-stx . rest)
             (raise-syntax-error #f "missing argument for option" stx #'kw-stx)]
            [_
             (raise-syntax-error #f "bad syntax" stx stxs)])))

      (define (unwind-promise stx unwind-recur)
        (syntax-case stx ()
          [(#%plain-lambda () body) (unwind-recur #'body)]))

      (syntax-case stx ()
        [(_ . exprs+kwds)
         (let ()
           (define-values (exprs kwds) (parse-exprs+kwds #'exprs+kwds))
           (with-syntax ([(expr ...) exprs]
                         [(kwd-arg ...) (map (lambda (k)
                                               (cond
                                                 [(assq (car k) kwds) => cdr]
                                                 [else (cdr k)]))
                                             keywords)])
             (with-syntax ([proc 
                            (stepper-syntax-property
                             (syntax-property
                              (syntax/loc stx (lambda () expr ...))
                              'inferred-name (syntax-local-infer-name stx))
                             'stepper-hint unwind-promise)]
                           [make (delayer-maker self)])
               (syntax-protect (syntax/loc stx (make proc kwd-arg ...))))))]))))

;; Creates a composable promise
;;   X = (force (lazy X)) = (force (lazy (lazy X))) = (force (lazy^n X))
(define lazy make-composable-promise)
(define-syntax lazy* (delayer #'lazy '()))

;; Creates a (generic) promise that does not compose
;;   X = (force (delay X)) = (force (lazy (delay X)))
;;                         = (force (lazy^n (delay X)))
;;   X = (force (force (delay (delay X)))) != (force (delay (delay X)))
;; so each sequence of `(lazy^n o delay)^m' requires m `force's and a
;; sequence of `(lazy^n o delay)^m o lazy^k' requires m+1 `force's (for k>0)
;; (This is not needed with a lazy language (see the above URL for details),
;; but provided for regular delay/force uses.)
(define delay make-promise)
(define-syntax delay* (delayer #'delay '()))

;; For simplicity and efficiency this code uses thunks in promise values for
;; exceptions: this way, we don't need to tag exception values in some special
;; way and test for them -- we just use a thunk that will raise the exception.
;; But it's still useful to refer to the exception value, so use an applicable
;; struct for them.  The same goes for a promise that is being forced: we use a
;; thunk that will throw a "reentrant promise" error -- and use an applicable
;; struct so it is identifiable.
(define-struct reraise (val)
  #:property prop:procedure (lambda (this) (raise (reraise-val this))))

(define-values (prop:running? -running?-predicate -running?-ref)
  (make-struct-type-property 'running
   (lambda (v info)
     (unless (and (procedure? v)
                  (procedure-arity-includes? v 1))
       (raise-argument-error 'prop:running? "(any/c . -> . boolean?)" v))
     v)))

(define-struct running (name)
  #:property prop:procedure
  (lambda (this)
    (let ([name (running-name this)])
      (if name
        (error 'force "reentrant promise `~.s'" name)
        (error 'force "reentrant promise"))))
  #:property prop:custom-write
  (lambda (this port write?)
    (fprintf port (if write? "#<running:~s>" "#<running:~a>")
             (running-name this))))

;; ----------------------------------------------------------------------------
;; Utilities

(define (promise-forced? promise)
  (if (promise? promise)
    (let ([v (pref promise)])
      (or (not (procedure? v)) (reraise? v))) ; #f when running
    (raise-argument-error 'promise-forced? "promise?" promise)))

(define (promise-running? promise)
  (if (promise? promise)
    (let ([v (pref promise)])
      (or (running? v)
          (and (-running?-predicate v)
               ((-running?-ref v) v))))
    (raise-argument-error 'promise-running? "promise?" promise)))

)

#|
Simple code for timings:
  (define (c n) (lazy (if (zero? n) (delay 'hey!) (c (sub1 n)))))
  (for ([i (in-range 9)])
    (collect-garbage) (collect-garbage) (collect-garbage)
    (time (for ([i (in-range 10000)]) (force (c 2000)))))
Also, run (force (c -1)) and check constant space
|#
