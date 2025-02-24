;; Define the contract's data variables
(define-map deposits principal { amount: uint })
(define-map loans principal { amount: uint, last-interaction-block: uint })

(define-data-var total-deposits uint u0)
(define-data-var pool-reserve uint u0)
(define-data-var loan-interest-rate uint u10) ;; Representing 10% interest rate

(define-constant err-no-interest (err u100))
(define-constant err-overpay (err u200))
(define-constant err-overborrow (err u300))

;; Users deposit sBTC into the contract
;; #[allow(unchecked_data)]
(define-public (deposit (amount uint))
    (let (
        (current-balance (default-to u0 (get amount (map-get? deposits tx-sender ))))
        )
        (try! (contract-call? .sbtc transfer amount tx-sender (as-contract tx-sender) none))
        (map-set deposits tx-sender { amount: (+ current-balance amount) })
        (var-set total-deposits (+ (var-get total-deposits) amount))
        (ok true)
    )
)

;; Users can borrow sBTC
(define-public (borrow (amount uint))
    (let (
        (user-deposit (default-to u0 (get amount (map-get? deposits tx-sender ))))
        (allowed-borrow (/ user-deposit u2))
        (current-loan-details (default-to { amount: u0, last-interaction-block: u0 } (map-get? loans tx-sender )))
        (accrued-interest (calculate-accrued-interest (get amount current-loan-details) (get last-interaction-block current-loan-details)))
        (total-due (+ (get amount current-loan-details) (unwrap! accrued-interest err-no-interest)))
        (new-loan (+ total-due amount))
    )
        (asserts! (<= amount allowed-borrow) err-overborrow)
        (try! (contract-call? .sbtc transfer amount (as-contract tx-sender) tx-sender none))
        (map-set loans tx-sender { amount: new-loan, last-interaction-block: stacks-block-height })
        (ok true)
    )
)

(define-read-only (get-amount-owed)
    (let (
        (current-loan-details (default-to { amount: u0, last-interaction-block: u0 } (map-get? loans tx-sender )))
        (accrued-interest (calculate-accrued-interest (get amount current-loan-details) (get last-interaction-block current-loan-details)))
        (total-due (+ (get amount current-loan-details) (unwrap! accrued-interest err-no-interest)))
    )
    (ok total-due)
    )
)


;; Users can repay their sBTC loans
(define-public (repay (amount uint))
    (let (
        (current-loan-details (default-to { amount: u0, last-interaction-block: u0 } (map-get? loans tx-sender )))
        (accrued-interest (unwrap! (calculate-accrued-interest (get amount current-loan-details) (get last-interaction-block current-loan-details)) err-no-interest))
        (total-due (+ (get amount current-loan-details) accrued-interest))
    )
        (asserts! (>= total-due amount) err-overpay)
        (try! (contract-call? .sbtc transfer amount tx-sender (as-contract tx-sender) none))
        (map-set loans tx-sender { amount: (- total-due amount), last-interaction-block: stacks-block-height })
        (var-set pool-reserve (+ (var-get pool-reserve) accrued-interest))
        (ok true)
    )
)

;; Users can claim yield
(define-public (claim-yield)
    (let (
        (user-deposit (default-to u0 (get amount (map-get? deposits tx-sender ))))
        (yield-amount (/ (* (var-get pool-reserve) user-deposit) (var-get total-deposits)))
    )
        (try! (contract-call? .sbtc transfer yield-amount (as-contract tx-sender) tx-sender none))
        (var-set pool-reserve (- (var-get pool-reserve) yield-amount))
        (ok true)
    )
)

(define-private (calculate-accrued-interest (principal uint) (start-block uint))
    (let (
        (elapsed-blocks (- stacks-block-height start-block))
        (interest (/ (* principal (var-get loan-interest-rate) elapsed-blocks) u10000))
    )
        (asserts! (not (is-eq start-block u0)) (ok u0))
       (ok interest)
    )
)