#lang racket/base

(require racket/contract/base
         racket/promise)

(provide/contract
 [current-date (-> date*?)]
 [date->seconds ((date?) (any/c) . ->* . exact-integer?)]
 [date*->seconds ((date?) (any/c) . ->* . real?)]
 [date->string ((date?) (any/c) . ->* . string?)]
 [date-display-format (parameter/c (symbols 'american 'chinese 'german 'indian 'irish 'julian 'iso-8601 'rfc2822))]
 [find-seconds (((integer-in 0 61)
                 (integer-in 0 59)
                 (integer-in 0 23)
                 (integer-in 1 31)
                 (integer-in 1 12)
                 exact-nonnegative-integer?)
                (any/c)
                . ->* .
                exact-integer?)]
 [date->julian/scaliger (date? . -> . exact-integer?)]
 [julian/scaliger->string (exact-integer? . -> . string?)]
 [date->julian/scalinger (date? . -> . exact-integer?)]
 [julian/scalinger->string (exact-integer? . -> . string?)])

(define (current-date)
  (seconds->date (* #i1/1000 (current-inexact-milliseconds))))

;; Support for Julian calendar added by Shriram;
;; current version only works until 2099 CE Gregorian

(define date-display-format 
  (make-parameter 'american #f 'date-display-format))

(define (month/number->string x)
  (case x
    [(12) "December"] [(1) "January"]  [(2) "February"]
    [(3) "March"]     [(4) "April"]    [(5) "May"]
    [(6) "June"]      [(7) "July"]     [(8) "August"]
    [(9) "September"] [(10) "October"] [(11) "November"]
    [else ""]))

(define (day/number->string x)
  (case x
    [(0) "Sunday"]
    [(1) "Monday"]
    [(2) "Tuesday"]
    [(3) "Wednesday"]
    [(4) "Thursday"]
    [(5) "Friday"]
    [(6) "Saturday"]
    [else ""]))

(define (add-zero n)
  (if (< n 10)
      (string-append "0" (number->string n))
      (number->string n)))

(define (date->string date [time? #f])
  (define year (number->string (date-year date)))
  (define num-month (number->string (date-month date)))
  (define week-day (day/number->string (date-week-day date)))
  (define month (month/number->string (date-month date)))
  (define day (number->string (date-day date)))
  (define day-th
    (if (<= 11 (date-day date) 13)
        "th"
        (case (modulo (date-day date) 10)
          [(1) "st"]
          [(2) "nd"]
          [(3) "rd"]
          [(0 4 5 6 7 8 9) "th"])))
  (define hour (date-hour date))
  (define am-pm (if (>= hour 12) "pm" "am"))
  (define hour24 (add-zero hour))
  (define hour12
    (number->string 
     (cond
       [(zero? hour) 12]
       [(> hour 12) (- hour 12)]
       [else hour])))
  (define minute (add-zero (date-minute date)))
  (define second (add-zero (date-second date)))
  (define-values 
    (day-strs time-strs)
    (case (date-display-format)
      [(american) 
       (values (list week-day ", " month " " day day-th ", " year)
               (list " " hour12 ":" minute ":" second am-pm))]
      [(chinese)
       (values
        (list year "/" num-month "/" day
              " \u661F\u671F" (case (date-week-day date)
                                [(0) "\u5929"]
                                [(1) "\u4E00"]
                                [(2) "\u4E8C"]
                                [(3) "\u4e09"]
                                [(4) "\u56DB"]
                                [(5) "\u4E94"]
                                [(6) "\u516D"]
                                [else ""]))
        (list " " hour24 ":" minute ":" second))]
      [(indian) 
       (values (list day "-" num-month "-" year)
               (list " " hour12 ":" minute ":" second am-pm))]
      [(german) 
       (values (list day ". " 
                     (case (date-month date)
                       [(1) "Januar"]
                       [(2) "Februar"]
                       [(3) "M\344rz"]
                       [(4) "April"]
                       [(5) "Mai"]
                       [(6) "Juni"]
                       [(7) "Juli"]
                       [(8) "August"]
                       [(9) "September"]
                       [(10) "Oktober"]
                       [(11) "November"]
                       [(12) "Dezember"]
                       [else ""])
                     " " year)
               (list ", " hour24 ":" minute))]
      [(irish) 
       (values (list week-day ", " day day-th " " month " " year)
               (list ", " hour12 ":" minute am-pm))]
      [(julian)
       (values (list (julian/scaliger->string
                      (date->julian/scaliger date)))
               (list ", " hour24 ":" minute ":" second))]
      [(iso-8601)
       (values
        (list year "-" (add-zero (date-month date)) "-" (add-zero (date-day date)))
        (list "T" hour24 ":" minute ":" second))]
      [(rfc2822)
       (values
        (list (substring week-day 0 3) ", " day " " (substring month 0 3) " " year)
        (list* " " hour24 ":" minute ":" second " "
               (let* ([delta (date-time-zone-offset date)]
                      [hours (quotient delta 3600)]
                      [minutes (modulo (quotient delta 60) 60)])
                 (list
                  (if (negative? delta) "-" "+")
                  (add-zero (abs hours))
                  (add-zero minutes)))))]
      [else (error 'date->string "unknown date-display-format: ~s"
                   (date-display-format))]))
  (apply string-append 
         (if time?
             (append day-strs time-strs)
             day-strs)))

(define (find-extreme-date-seconds start offset)
  (let/ec found
    (letrec ([find-between
              (lambda (lo hi)
                (let ([mid (floor (/ (+ lo hi) 2))])
                  (if (or (and (positive? offset) (= lo mid))
                          (and (negative? offset) (= hi mid)))
                      (found lo)
                      (let ([mid-ok?
                             (with-handlers ([exn:fail? (lambda (exn) #f)])
                               (seconds->date mid)
                               #t)])
                        (if mid-ok?
                            (find-between mid hi)
                            (find-between lo mid))))))])
      (let loop ([lo start][offset offset])
        (let ([hi (+ lo offset)])
          (with-handlers ([exn:fail? 
                           (lambda (exn) 
                             ; failed - must be between lo & hi
                             (find-between lo hi))])
            (seconds->date hi))
          ; succeeded; double offset again
          (loop hi (* 2 offset)))))))

(define get-min-seconds
  (let ([d (delay/sync (find-extreme-date-seconds (current-seconds) -1))])
    (lambda ()
      (force d))))
(define get-max-seconds
  (let ([d (delay/sync (find-extreme-date-seconds (current-seconds) 1))])
    (lambda ()
      (force d))))

(define (date->seconds date [local-time? #t])
  (find-seconds 
   (date-second date) 
   (date-minute date) 
   (date-hour date) 
   (date-day date) 
   (date-month date) 
   (date-year date)
   local-time?))

(define (date*->seconds date [local-time? #t])
  (define s (date->seconds date local-time?))
  (if (date*? date)
      (+ s (/ (date*-nanosecond date) #e1e9))
      s))

(define (find-seconds sec min hour day month year [local-time? #t])
  (define wanted (list year month day hour min sec))
  (define-values (secs found?) (find-seconds* wanted local-time?))
  (unless found?
    (error 'find-seconds
           (string-append "non-existent date"
                          "\n  wanted: ~s"
                          "\n  nearest below: ~s is ~s"
                          "\n  nearest above: ~s is ~s")
           (reverse wanted)
           secs
           (reverse (date->list (seconds->date secs local-time?)))
           (add1 secs)
           (reverse (date->list (seconds->date (add1 secs) local-time?)))))
  secs)

;; find-seconds* : list-of-6-nat boolean -> (values nat boolean)
;; Returns (values secs found?) s.t.
;;  - if found? is true: (seconds->date secs local-time?) = wanted
;;  - if found? is false: secs is glb for wanted
;; Note: seconds->date is non-monotonic (eg, DST), but should be
;; well-behaved enough for binary search to work.
(define (find-seconds* wanted local-time?)
  (let loop ([below-secs (get-min-seconds)]
             [above-secs (get-max-seconds)])
    ;; Inv: below-secs < above-secs
    ;; Inv: (seconds->date below-secs local-time?)
    ;;      < inputs
    ;;      < (seconds->date above-secs local-time?)
    (let* ([secs (floor (/ (+ below-secs above-secs) 2))]
           [date (seconds->date secs local-time?)]
           [compare
            (let loop ([inputs wanted]
                       [tests (date->list date)])
              (cond
                [(null? inputs) 'equal]
                [else (let ([input (car inputs)]
                            [test (car tests)])
                        (if (= input test)
                            (loop (cdr inputs) (cdr tests))
                            (if (<= input test)
                                'input-smaller
                                'test-smaller)))]))])
      ; (printf "~a ~a ~a\n" compare secs (date->string date))
      (cond
        [(eq? compare 'equal)
         (values secs #t)]
        [(or (= secs below-secs) (= secs above-secs))
         (values below-secs #f)]
        [(eq? compare 'input-smaller) 
         (loop below-secs secs)]
        [(eq? compare 'test-smaller) 
         (loop secs above-secs)]))))

;; returns components in order for lexicographic comparison
(define (date->list d)
  (list (date-year d)
        (date-month d)
        (date-day d)
        (date-hour d)
        (date-minute d)
        (date-second d)))

;; date->julian/scaliger :
;; date -> number [julian-day]

;; Note: This code is correct until 2099 CE Gregorian

(define (date->julian/scaliger date)
  (define day (date-day date))
  (define month (date-month date))
  (define d-year (date-year date))
  (define year (+ 4712 d-year))
  (define adj-year (if (< month 3) (sub1 year) year))
  (define cycle-number (quotient adj-year 4))
  (define cycle-position (remainder adj-year 4))
  (define base-day (+ (* 1461 cycle-number) (* 365 cycle-position)))
  (define month-day-number 
    (case month
      ((3) 0)
      ((4) 31)
      ((5) 61)
      ((6) 92)
      ((7) 122)
      ((8) 153)
      ((9) 184)
      ((10) 214)
      ((11) 245)
      ((12) 275)
      ((1) 306)
      ((2) 337)))
  (define total-days (+ base-day month-day-number day))
  (define total-days/march-adjustment (+ total-days 59))
  (define gregorian-adjustment 
    (cond
      ((< adj-year 1700) 11)
      ((< adj-year 1800) 12)
      (else 13)))
  (define final-date 
    (- total-days/march-adjustment
       gregorian-adjustment))
  final-date)

;; julian/scaliger->string :
;; number [julian-day] -> string [julian-day-format]

(define (julian/scaliger->string julian-day)
  (apply string-append
         (cons "JD "
               (reverse
                (let loop ((reversed-digits (map number->string
                                                 (let loop ((jd julian-day))
                                                   (if (zero? jd) null
                                                       (cons (remainder jd 10)
                                                             (loop (quotient jd 10))))))))
                  (cond
                    ((or (null? reversed-digits)
                         (null? (cdr reversed-digits))
                         (null? (cdr (cdr reversed-digits)))
                         (null? (cdr (cdr (cdr reversed-digits)))))
                     (list (apply string-append (reverse reversed-digits))))
                    (else (cons (apply string-append
                                       (list " "
                                             (caddr reversed-digits)
                                             (cadr reversed-digits)
                                             (car reversed-digits)))
                                (loop (cdr (cdr (cdr reversed-digits))))))))))))

;; Misspelled names for backward compatibility:
(define (date->julian/scalinger d) (date->julian/scaliger d))
(define (julian/scalinger->string i) (julian/scaliger->string i))
