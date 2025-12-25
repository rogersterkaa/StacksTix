;; Stackstix Logic Contract - SIP-009 NFT Implementation
;; Business logic layer that calls storage contract
;; Written by Rogersterkaa
;; Implements SIP-009 NFT standard for ticket NFTs

;; Import SIP-009 trait
(impl-trait .sip-09.nft-trait)

;;;;;;;;;;;;;;;;;;;;;
;; CONSTANTS       ;;
;;;;;;;;;;;;;;;;;;;;;
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-EVENT-NOT-FOUND (err u201))
(define-constant ERR-TICKET-NOT-FOUND (err u202))
(define-constant ERR-NOT-OWNER (err u203))
(define-constant ERR-EVENT-INACTIVE (err u204))
(define-constant ERR-EVENT-SOLD-OUT (err u205))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u206))
(define-constant ERR-EVENT-NOT-STARTED (err u207))
(define-constant ERR-EVENT-ENDED (err u208))
(define-constant ERR-TICKET-ALREADY-USED (err u209))
(define-constant ERR-NOT-VALIDATOR (err u210))
(define-constant ERR-TRANSFER-NOT-ALLOWED (err u211))
(define-constant ERR-REFUND-NOT-ALLOWED (err u212))
(define-constant ERR-WITHDRAW-NOT-ALLOWED (err u213))
(define-constant ERR-INVALID-RECIPIENT (err u214))

;; Platform fee percentage (2%)
(define-constant PLATFORM-FEE-PERCENT u2)

;; Storage contract principal (set during initialization)
(define-data-var storage-contract principal tx-sender)
(define-data-var platform-wallet principal tx-sender)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SIP-009 INTERFACE IMPLEMENTATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; SIP-009: Get last token ID
(define-read-only (get-last-token-id)
  (begin
        (try! (contract-call? (var-get storage-contract) get-next-ticket-id))
        (ok (try! (contract-call? (var-get storage-contract) get-next-ticket-id)))
  )
)

;; SIP-009: Get token URI
(define-read-only (get-token-uri (token-id uint))
  (begin
    (match (contract-call? (var-get storage-contract) get-ticket token-id)
      ticket (match (contract-call? (var-get storage-contract) get-event (get event-id ticket))
        event (ok (get metadata-uri event))
        (ok none)
      )
      (ok none)
    )
  )
)

;; SIP-009: Get owner of token
(define-read-only (get-owner (token-id uint))
  (begin
    (match (contract-call? (var-get storage-contract) get-ticket-owner token-id)
      some-owner (ok some-owner)
      (ok none)
    )
  )
)

;; SIP-009: Transfer token
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Validate inputs
    (asserts! (is-standard principal recipient) ERR-INVALID-RECIPIENT)
    
    ;; Get ticket data
    (let ((ticket (unwrap! (contract-call? (var-get storage-contract) get-ticket token-id) ERR-TICKET-NOT-FOUND)))
      
      ;; Verify sender owns the ticket
      (asserts! (is-eq (get owner ticket) sender) ERR-NOT-OWNER)
      
      ;; Verify caller is sender
      (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
      
      ;; Get event to check transferability
      (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event (get event-id ticket)) ERR-EVENT-NOT-FOUND)))
        
        ;; Check if ticket is transferable
        (asserts! (get transferable event) ERR-TRANSFER-NOT-ALLOWED)
        
        ;; Check if ticket is already used
        (asserts! (not (get is-used ticket)) ERR-TICKET-ALREADY-USED)
        
        ;; Update ticket owner in storage
        (try! (contract-call? (var-get storage-contract) update-ticket-owner token-id recipient))
        
        ;; Emit SIP-009 transfer event
        (print {
          event: "nft-transfer-event",
          asset-identifier: (as-contract tx-sender),
          token-id: token-id,
          sender: sender,
          recipient: recipient
        })
        
        (ok true)
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; EVENT MANAGEMENT FUNCTIONS ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (create-event
    (name (string-utf8 100))
    (description (string-utf8 500))
    (location (string-utf8 100))
    (start-time uint)
    (end-time uint)
    (ticket-price uint)
    (total-supply uint)
    (refund-allowed bool)
    (transferable bool)
    (metadata-uri (optional (string-utf8 256))))
  (begin
    ;; Generate new event ID from storage
    (let ((event-id (try! (contract-call? (var-get storage-contract) increment-event-id))))
      
      ;; Insert event into storage
      (try! (contract-call? (var-get storage-contract) insert-event
        event-id
        tx-sender
        name
        description
        location
        start-time
        end-time
        ticket-price
        total-supply
        refund-allowed
        transferable
        metadata-uri
      ))
      
      ;; Emit event creation event
      (print {
        event: "event-created",
        event-id: event-id,
        organizer: tx-sender,
        name: name,
        start-time: start-time,
        ticket-price: ticket-price
      })
      
      (ok event-id)
    )
  )
)

(define-public (update-event-metadata (event-id uint) (metadata-uri (optional (string-utf8 256))))
  (begin
    ;; Get event to verify ownership
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Update metadata in storage
      (try! (contract-call? (var-get storage-contract) update-event-metadata event-id metadata-uri))
      
      (ok true)
    )
  )
)

(define-public (cancel-event (event-id uint))
  (begin
    ;; Get event to verify ownership
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Update event status to inactive
      (try! (contract-call? (var-get storage-contract) update-event-status event-id false))
      
      (print {
        event: "event-cancelled",
        event-id: event-id,
        organizer: tx-sender
      })
      
      (ok true)
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TICKET PURCHASE (MINTING) ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (purchase-ticket (event-id uint))
  (begin
    ;; Get event details
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Validate event is active
      (asserts! (get is-active event) ERR-EVENT-INACTIVE)
      
      ;; Check ticket availability
      (let ((sold-count (get sold-count event))
            (total-supply (get total-supply event)))
        (asserts! (< sold-count total-supply) ERR-EVENT-SOLD-OUT)
        
        ;; Get ticket price
        (let ((ticket-price (get ticket-price event)))
          
          ;; Process payment
          (try! (stx-transfer? ticket-price tx-sender (as-contract tx-sender)))
          
          ;; Generate new ticket ID
          (let ((ticket-id (try! (contract-call? (var-get storage-contract) increment-ticket-id))))
            
            ;; Insert ticket into storage
            (try! (contract-call? (var-get storage-contract) insert-ticket
              ticket-id
              event-id
              tx-sender
              block-height
            ))
            
            ;; Update sold count
            (try! (contract-call? (var-get storage-contract) update-event-sold-count event-id (+ sold-count u1)))
            
            ;; Calculate and update balances
            (let ((platform-fee (/ (* ticket-price PLATFORM-FEE-PERCENT) u100))
                  (organizer-amount (- ticket-price platform-fee)))
              
              ;; Update event balance (lock organizer portion)
              (let ((current-balance (default-to 
                { available-balance: u0, locked-balance: u0, total-withdrawn: u0 }
                (contract-call? (var-get storage-contract) get-event-balance event-id))))
                
                (try! (contract-call? (var-get storage-contract) set-event-balance
                  event-id
                  (get available-balance current-balance)
                  (+ (get locked-balance current-balance) organizer-amount)
                ))
              )
              
              ;; Transfer platform fee
              (try! (as-contract (stx-transfer? platform-fee tx-sender (var-get platform-wallet))))
            )
            
            ;; Emit SIP-009 mint event
            (print {
              event: "nft-mint-event",
              asset-identifier: (as-contract tx-sender),
              token-id: ticket-id,
              recipient: tx-sender
            })
            
            (ok ticket-id)
          )
        )
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TICKET VALIDATION       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (validate-ticket (ticket-id uint))
  (begin
    ;; Get ticket details
    (let ((ticket (unwrap! (contract-call? (var-get storage-contract) get-ticket ticket-id) ERR-TICKET-NOT-FOUND)))
      
      ;; Check if ticket already used
      (asserts! (not (get is-used ticket)) ERR-TICKET-ALREADY-USED)
      
      ;; Get event details
      (let ((event-id (get event-id ticket))
            (event (unwrap! (contract-call? (var-get storage-contract) get-event (get event-id ticket)) ERR-EVENT-NOT-FOUND)))
        
        ;; Check validator authorization
        (let ((validator-data (unwrap-panic (contract-call? (var-get storage-contract) get-validator event-id tx-sender))))
          (asserts! (get is-active validator-data) ERR-NOT-VALIDATOR)
        )
        
        ;; Check event timing
        (asserts! (>= block-height (get start-time event)) ERR-EVENT-NOT-STARTED)
        (asserts! (<= block-height (get end-time event)) ERR-EVENT-ENDED)
        
        ;; Mark ticket as used
        (try! (contract-call? (var-get storage-contract) mark-ticket-used ticket-id))
        
        ;; Increment validator count
        (try! (contract-call? (var-get storage-contract) increment-validator-count event-id tx-sender))
        
        (print {
          event: "ticket-validated",
          ticket-id: ticket-id,
          event-id: event-id,
          validator: tx-sender,
          timestamp: block-height
        })
        
        (ok true)
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REFUND SYSTEM           ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (refund-ticket (ticket-id uint))
  (begin
    ;; Get ticket details
    (let ((ticket (unwrap! (contract-call? (var-get storage-contract) get-ticket ticket-id) ERR-TICKET-NOT-FOUND)))
      
      ;; Verify ticket owner
      (asserts! (is-eq tx-sender (get owner ticket)) ERR-NOT-OWNER)
      
      ;; Check if ticket already used
      (asserts! (not (get is-used ticket)) ERR-TICKET-ALREADY-USED)
      
      ;; Get event details
      (let ((event-id (get event-id ticket))
            (event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
        
        ;; Check if refunds are allowed
        (asserts! (get refund-allowed event) ERR-REFUND-NOT-ALLOWED)
        
        ;; Check event hasn't started
        (asserts! (< block-height (get start-time event)) ERR-EVENT-NOT-STARTED)
        
        ;; Get ticket price
        (let ((ticket-price (get ticket-price event)))
          
          ;; Calculate refund amounts
          (let ((organizer-refund (- ticket-price (/ (* ticket-price PLATFORM-FEE-PERCENT) u100))))
            
            ;; Update event balance
            (let ((current-balance (unwrap! (contract-call? (var-get storage-contract) get-event-balance event-id) ERR-EVENT-NOT-FOUND)))
              
              (try! (contract-call? (var-get storage-contract) set-event-balance
                event-id
                (get available-balance current-balance)
                (- (get locked-balance current-balance) organizer-refund)
              ))
            )
            
            ;; Refund buyer
            (try! (as-contract (stx-transfer? ticket-price tx-sender (get owner ticket))))
            
            ;; Delete ticket (burn)
            (try! (contract-call? (var-get storage-contract) delete-ticket ticket-id))
            
            ;; Update sold count
            (try! (contract-call? (var-get storage-contract) update-event-sold-count 
              event-id 
              (- (get sold-count event) u1)))
            
            (print {
              event: "ticket-refunded",
              ticket-id: ticket-id,
              event-id: event-id,
              owner: (get owner ticket),
              amount: ticket-price
            })
            
            (ok true)
          )
        )
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VALIDATOR MANAGEMENT       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (add-validator (event-id uint) (validator principal))
  (begin
    ;; Get event to verify ownership
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Add validator in storage
      (try! (contract-call? (var-get storage-contract) set-validator event-id validator true))
      
      (ok true)
    )
  )
)

(define-public (remove-validator (event-id uint) (validator principal))
  (begin
    ;; Get event to verify ownership
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Remove validator in storage
      (try! (contract-call? (var-get storage-contract) set-validator event-id validator false))
      
      (ok true)
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REVENUE WITHDRAWAL        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (withdraw-event-revenue (event-id uint))
  (begin
    ;; Get event details
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Get event balance
      (let ((event-balance (unwrap! (contract-call? (var-get storage-contract) get-event-balance event-id) ERR-EVENT-NOT-FOUND)))
        
        ;; Calculate withdrawable amount
        (let ((withdrawable-amount (get locked-balance event-balance)))
          
          ;; Ensure there is an amount to withdraw
          (asserts! (> withdrawable-amount u0) ERR-WITHDRAW-NOT-ALLOWED)
          
          ;; Update event balance
          (try! (contract-call? (var-get storage-contract) set-event-balance
            event-id
            (get available-balance event-balance u0)
          ))
          
          ;; Transfer funds to organizer
          (try! (as-contract (stx-transfer? withdrawable-amount (as-contract tx-sender) tx-sender)))
          
          ;; Update total withdrawn
          (try! (contract-call? (var-get storage-contract) update-event-total-withdrawn
            event-id
            (+ (get total-withdrawn event-balance) withdrawable-amount)
          ))
          
          (print {
            event: "event-revenue-withdrawn",
            event-id: event-id,
            organizer: tx-sender,
            amount: withdrawable-amount
          })
          
          (ok true)
        )
      )
    )
))   