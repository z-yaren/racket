
(load-relative "loadtest.rktl")

(Section 'hash)

(require racket/hash)

(test #hash([4 . four] [3 . three] [1 . one] [2 . two])
      hash-union #hash([1 . one] [2 . two]) #hash([3 . three] [4 . four]))
(test #hash([four . 4] [three . 3] [one . 1] [two . 2])
      hash-union #hash([one . 1] [two . 1]) #hash([three . 3] [four . 4] [two . 1])
      #:combine +)

(let ()
  (define h (make-hash))
  (hash-union! h #hash([1 . one] [2 . two]))
  (hash-union! h #hash([3 . three] [4 . four]))
  (test #t
        equal?
        (hash-copy
         #hash([1 . one] [2 . two] [3 . three] [4 . four]))
        h))
(let ()
  (define h (make-hash))
  (hash-union! h #hash([one . 1] [two . 1]))
  (err/rt-test (hash-union! h #hash([three . 3] [four . 4] [two . 1])) exn:fail?))
(let ()
  (define h (make-hash))
  (hash-union! h #hash([one . 1] [two . 1]))
  (hash-union! h #hash([three . 3] [four . 4] [two . 1])
               #:combine/key (lambda (k x y) (+ x y)))
  (test #t
        equal?
        (hash-copy
         #hash([one . 1] [two . 2] [three . 3] [four . 4]))
        h))

(let ()
  (define lst1 (build-list 10 values))
  (define lst2 (build-list 10 add1))

  (define ht/immut (make-immutable-hash (map cons lst1 lst2)))
  (define ht/mut (make-hash (map cons lst1 lst2)))
  (define ht/weak (make-weak-hash (map cons lst1 lst2)))
  
(define fake-ht/immut
  (chaperone-hash 
    ht/immut
    (lambda (h k) (values k (lambda (h k v) v))) ; ref-proc
    (lambda (h k v) values k v) ; set-proc
    (lambda (h k) k) ; remove-proc
    (lambda (h k) k))) ; key-proc
(define fake-ht/mut
  (impersonate-hash 
    ht/mut
    (lambda (h k) (values k (lambda (h k v) v))) ; ref-proc
    (lambda (h k v) values k v) ; set-proc
    (lambda (h k) k) ; remove-proc
    (lambda (h k) k))) ; key-proc
(define fake-ht/weak
  (impersonate-hash 
    ht/weak
    (lambda (h k) (values k (lambda (h k v) v))) ; ref-proc
    (lambda (h k v) values k v) ; set-proc
    (lambda (h k) k) ; remove-proc
    (lambda (h k) k))) ; key-proc

  (define ht/immut/seq (in-hash ht/immut))
  (define ht/mut/seq (in-hash ht/mut))
  (define ht/weak/seq (in-hash ht/weak))
  (define ht/immut-pair/seq (in-hash-pairs ht/immut))
  (define ht/mut-pair/seq (in-hash-pairs ht/mut))
  (define ht/weak-pair/seq (in-hash-pairs ht/weak))
  (define ht/immut-keys/seq (in-hash-keys ht/immut))
  (define ht/mut-keys/seq (in-hash-keys ht/mut))
  (define ht/weak-keys/seq (in-hash-keys ht/weak))
  (define ht/immut-vals/seq (in-hash-values ht/immut))
  (define ht/mut-vals/seq (in-hash-values ht/mut))
  (define ht/weak-vals/seq (in-hash-values ht/weak))

    
  (test #t
        =
        (for/sum ([(k v) (in-hash ht/immut)]) (+ k v))
        (for/sum ([(k v) (in-hash ht/mut)]) (+ k v))
        (for/sum ([(k v) (in-hash ht/weak)]) (+ k v))
        (for/sum ([(k v) (in-hash fake-ht/immut)]) (+ k v))
        (for/sum ([(k v) (in-hash fake-ht/mut)]) (+ k v))
        (for/sum ([(k v) (in-hash fake-ht/weak)]) (+ k v))
        (for/sum ([(k v) ht/immut/seq]) (+ k v))
        (for/sum ([(k v) ht/mut/seq]) (+ k v))
        (for/sum ([(k v) ht/weak/seq]) (+ k v))
        (for/sum ([k+v (in-hash-pairs ht/immut)]) (+ (car k+v) (cdr k+v)))
        (for/sum ([k+v (in-hash-pairs ht/mut)]) (+ (car k+v) (cdr k+v)))
        (for/sum ([k+v (in-hash-pairs ht/weak)]) (+ (car k+v) (cdr k+v)))
        (for/sum ([k+v (in-hash-pairs fake-ht/immut)]) (+ (car k+v) (cdr k+v)))
        (for/sum ([k+v (in-hash-pairs fake-ht/mut)]) (+ (car k+v) (cdr k+v)))
        (for/sum ([k+v (in-hash-pairs fake-ht/weak)]) (+ (car k+v) (cdr k+v)))
        (for/sum ([k+v ht/immut-pair/seq]) (+ (car k+v) (cdr k+v)))
        (for/sum ([k+v ht/mut-pair/seq]) (+ (car k+v) (cdr k+v)))
        (for/sum ([k+v ht/weak-pair/seq]) (+ (car k+v) (cdr k+v)))
        (+ (for/sum ([k (in-hash-keys ht/immut)]) k)
           (for/sum ([v (in-hash-values ht/immut)]) v))
        (+ (for/sum ([k (in-hash-keys ht/mut)]) k)
           (for/sum ([v (in-hash-values ht/mut)]) v))
        (+ (for/sum ([k (in-hash-keys ht/weak)]) k)
           (for/sum ([v (in-hash-values ht/weak)]) v))
        (+ (for/sum ([k (in-hash-keys fake-ht/immut)]) k)
           (for/sum ([v (in-hash-values fake-ht/immut)]) v))
        (+ (for/sum ([k (in-hash-keys fake-ht/mut)]) k)
           (for/sum ([v (in-hash-values fake-ht/mut)]) v))
        (+ (for/sum ([k (in-hash-keys fake-ht/weak)]) k)
           (for/sum ([v (in-hash-values fake-ht/weak)]) v))
        (+ (for/sum ([k ht/immut-keys/seq]) k)
           (for/sum ([v ht/immut-vals/seq]) v))
        (+ (for/sum ([k ht/mut-keys/seq]) k)
           (for/sum ([v ht/mut-vals/seq]) v))
        (+ (for/sum ([k ht/weak-keys/seq]) k)
           (for/sum ([v ht/weak-vals/seq]) v)))

  (test #t
        =
        (for/sum ([(k v) (in-hash ht/immut)]) k)
        (for/sum ([(k v) (in-hash ht/mut)]) k)
        (for/sum ([(k v) (in-hash ht/weak)]) k)
        (for/sum ([(k v) (in-hash fake-ht/immut)]) k)
        (for/sum ([(k v) (in-hash fake-ht/mut)]) k)
        (for/sum ([(k v) (in-hash fake-ht/weak)]) k)
        (for/sum ([(k v) ht/immut/seq]) k)
        (for/sum ([(k v) ht/mut/seq]) k)
        (for/sum ([(k v) ht/weak/seq]) k)
        (for/sum ([k+v (in-hash-pairs ht/immut)]) (car k+v))
        (for/sum ([k+v (in-hash-pairs ht/mut)]) (car k+v))
        (for/sum ([k+v (in-hash-pairs ht/weak)]) (car k+v))
        (for/sum ([k+v (in-hash-pairs fake-ht/immut)]) (car k+v))
        (for/sum ([k+v (in-hash-pairs fake-ht/mut)]) (car k+v))
        (for/sum ([k+v (in-hash-pairs fake-ht/weak)]) (car k+v))
        (for/sum ([k+v ht/immut-pair/seq]) (car k+v))
        (for/sum ([k+v ht/mut-pair/seq]) (car k+v))
        (for/sum ([k+v ht/weak-pair/seq]) (car k+v))
        (for/sum ([k (in-hash-keys ht/immut)]) k)
        (for/sum ([k (in-hash-keys ht/mut)]) k)
        (for/sum ([k (in-hash-keys ht/weak)]) k)
        (for/sum ([k (in-hash-keys fake-ht/immut)]) k)
        (for/sum ([k (in-hash-keys fake-ht/mut)]) k)
        (for/sum ([k (in-hash-keys fake-ht/weak)]) k)
        (for/sum ([k ht/immut-keys/seq]) k)
        (for/sum ([k ht/mut-keys/seq]) k)
        (for/sum ([k ht/weak-keys/seq]) k))

  (test #t
        =
        (for/sum ([(k v) (in-hash ht/immut)]) v)
        (for/sum ([(k v) (in-hash ht/mut)]) v)
        (for/sum ([(k v) (in-hash ht/weak)]) v)
        (for/sum ([(k v) (in-hash fake-ht/immut)]) v)
        (for/sum ([(k v) (in-hash fake-ht/mut)]) v)
        (for/sum ([(k v) (in-hash fake-ht/weak)]) v)
        (for/sum ([(k v) ht/immut/seq]) v)
        (for/sum ([(k v) ht/mut/seq]) v)
        (for/sum ([(k v) ht/weak/seq]) v)
        (for/sum ([k+v (in-hash-pairs ht/immut)]) (cdr k+v))
        (for/sum ([k+v (in-hash-pairs ht/mut)]) (cdr k+v))
        (for/sum ([k+v (in-hash-pairs ht/weak)]) (cdr k+v))
        (for/sum ([k+v (in-hash-pairs fake-ht/immut)]) (cdr k+v))
        (for/sum ([k+v (in-hash-pairs fake-ht/mut)]) (cdr k+v))
        (for/sum ([k+v (in-hash-pairs fake-ht/weak)]) (cdr k+v))
        (for/sum ([k+v ht/immut-pair/seq]) (cdr k+v))
        (for/sum ([k+v ht/mut-pair/seq]) (cdr k+v))
        (for/sum ([k+v ht/weak-pair/seq]) (cdr k+v))
        (for/sum ([v (in-hash-values ht/immut)]) v)
        (for/sum ([v (in-hash-values ht/mut)]) v)
        (for/sum ([v (in-hash-values ht/weak)]) v)
        (for/sum ([v (in-hash-values fake-ht/immut)]) v)
        (for/sum ([v (in-hash-values fake-ht/mut)]) v)
        (for/sum ([v (in-hash-values fake-ht/weak)]) v)
        (for/sum ([v ht/immut-vals/seq]) v)
        (for/sum ([v ht/mut-vals/seq]) v)
        (for/sum ([v ht/weak-vals/seq]) v)))
