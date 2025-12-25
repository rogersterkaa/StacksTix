;; StacksTix-storage-contract
;; StackTix-Decentralized NFT Ticketing Platform
;; This contract allows storing and retrieving event data on-chain.
;; Written by Rogersterkaa
;; Here we are going to implement data storage layer for SIP-009 NFT ticketing system
;; This contract stores all state and can only be modified by the privileged logic contract


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CONSTANTS - Error Codes ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-EVENT-NOT-FOUND (err u101))
(define-constant ERR-TICKET-NOT-FOUND (err u102))
(define-constant ERR-VALIDATOR-NOT-FOUND (err u103))
(define-constant ERR-OVERFLOW (err u104))
(define-constant ERR-INVALID-SUPPLY (err u105))
(define-constant ERR-INVALID-TIME-RANGE (err u106))
(define-constant ERR-EVENT-IN-PAST (err u107))
(define-constant ERR-EXCEEDS-SUPPLY (err u108))
(define-constant ERR-TICKET-ALREADY-USED (err u109))
(define-constant ERR-CONTRACT-PAUSED (err u110))
(define-constant ERR-INVALID-PRICE (err u111))

;; Maximum safe uint value for overflow checks
(define-constant MAX_UINT u340282366920938463463374607431768211455)


;;;;;;;;;;;;;;;;;;;;
;; DATA VARIABLES ;;
;;;;;;;;;;;;;;;;;;;;
;; The privileged logic contract that can modify storage
(define-data-var contract-owner principal tx-sender)

;; Emergency pause mechanism
(define-data-var contract-paused bool false)

;; Counters for generating unique IDs
(define-data-var next-event-id uint u1)
(define-data-var next-ticket-id uint u1)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; DATA MAPS - Core Storage ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Event details with full metadata
(define-map events 
  { event-id: uint }
  {
    organizer: principal,
    name: (string-utf8 100),
    description: (string-utf8 500),
    location: (string-utf8 100),
    start-time: uint,
    end-time: uint,
    ticket-price: uint,
    total-supply: uint,
    sold-count: uint,
    is-active: bool,
    refund-allowed: bool,
    transferable: bool,
    metadata-uri: (optional (string-utf8 256)),
    created-at: uint
  }
)

;; Ticket NFT data (SIP-009 compliant)
(define-map tickets
  { ticket-id: uint }
  {
    event-id: uint,
    owner: principal,
    is-used: bool,
    purchase-time: uint,
    used-time: (optional uint)
  }
)

;; Event validators/staff authorization
(define-map event-validators
  { event-id: uint, validator: principal }
  { is-active: bool, validated-count: uint, added-at: uint }
)

;; Event financial tracking
(define-map event-balances
  { event-id: uint }
  { 
    available-balance: uint, 
    locked-balance: uint,
    total-withdrawn: uint 
  }
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; INDEX MAPS - For Efficient Queries ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Track tickets by owner for wallet queries
(define-map owner-tickets
  { owner: principal, ticket-id: uint }
  { event-id: uint }
)

;; Track events by organizer
(define-map organizer-events
  { organizer: principal, event-id: uint }
  { created-at: uint }
)

;; Track tickets by event for analytics
(define-map event-tickets
  { event-id: uint, ticket-id: uint }
  { owner: principal }
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; AUTHORIZATION HELPERS ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-private (is-contract-owner)
  (ok (asserts! (is-eq contract-caller (var-get contract-owner)) ERR-NOT-AUTHORIZED))
)

(define-private (is-not-paused)
  (ok (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED))
)

(define-private (check-authorized-and-active)
  (begin
    (try! (is-contract-owner))
    (try! (is-not-paused))
    (ok true)
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; READ-ONLY GETTERS - Contract Configuration ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (get-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-next-event-id)
  (var-get next-event-id)
)

(define-read-only (get-next-ticket-id)
  (var-get next-ticket-id)
)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; READ-ONLY HELPERS - Existence Checks ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-read-only (event-exists (event-id uint))
  (is-some (map-get? events { event-id: event-id }))
)

(define-read-only (ticket-exists (ticket-id uint))
  (is-some (map-get? tickets { ticket-id: ticket-id }))
)

(define-read-only (validator-exists (event-id uint) (validator principal))
  (is-some (map-get? event-validators { event-id: event-id, validator: validator }))
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ADMIN FUNCTIONS - Contract Management ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (set-contract-owner (new-owner principal))
  (begin
    (try! (is-contract-owner))
    (var-set contract-owner new-owner)
    (print { 
      event: "owner-changed", 
      old-owner: (var-get contract-owner), 
      new-owner: new-owner 
    })
    (ok true)
  )
)

(define-public (set-contract-paused (paused bool))
  (begin
    (try! (is-contract-owner))
    (var-set contract-paused paused)
    (ok (print { event: "pause-status-changed", paused: paused }))
  )
)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  EVENT STORAGE FUNCTIONS ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-event (event-id uint))
  (map-get? events { event-id: event-id })
)

(define-public (insert-event 
    (event-id uint)
    (organizer principal)
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
    (try! (check-authorized-and-active))
    
    ;; Validations
    (asserts! (> total-supply u0) ERR-INVALID-SUPPLY)
    (asserts! (< start-time end-time) ERR-INVALID-TIME-RANGE)
    (asserts! (>= start-time block-height) ERR-EVENT-IN-PAST)
    (asserts! (>= ticket-price u0) ERR-INVALID-PRICE)
    
    ;; Insert event
    (map-set events
      { event-id: event-id }
      {
        organizer: organizer,
        name: name,
        description: description,
        location: location,
        start-time: start-time,
        end-time: end-time,
        ticket-price: ticket-price,
        total-supply: total-supply,
        sold-count: u0,
        is-active: true,
        refund-allowed: refund-allowed,
        transferable: transferable,
        metadata-uri: metadata-uri,
        created-at: block-height
      }
    )
    
    ;; Create index
    (map-set organizer-events
      { organizer: organizer, event-id: event-id }
      { created-at: block-height }
    )
    
    ;; Initialize balance
    (map-set event-balances
      { event-id: event-id }
      { available-balance: u0, locked-balance: u0, total-withdrawn: u0 }
    )
    
    (print { 
      event: "event-created", 
      event-id: event-id, 
      organizer: organizer,
      name: name
    })
    (ok true)
  )
)

(define-public (update-event-sold-count (event-id uint) (new-count uint))
  (begin
    (try! (check-authorized-and-active))
    (let ((event (unwrap! (map-get? events { event-id: event-id }) ERR-EVENT-NOT-FOUND)))
      ;; Validate new count doesn't exceed supply
      (asserts! (<= new-count (get total-supply event)) ERR-EXCEEDS-SUPPLY)
      
      (map-set events
        { event-id: event-id }
        (merge event { sold-count: new-count })
      )
      (ok (print { event: "sold-count-updated", event-id: event-id, new-count: new-count }))
    )
  )
)

(define-public (update-event-status (event-id uint) (is-active bool))
  (begin
    (try! (check-authorized-and-active))
    (let ((event (unwrap! (map-get? events { event-id: event-id }) ERR-EVENT-NOT-FOUND)))
      (map-set events
        { event-id: event-id }
        (merge event { is-active: is-active })
      )
      (ok (print { event: "event-status-updated", event-id: event-id, is-active: is-active }))
    )
  )
)

(define-public (update-event-metadata (event-id uint) (metadata-uri (optional (string-utf8 256))))
  (begin
    (try! (check-authorized-and-active))
    (let ((event (unwrap! (map-get? events { event-id: event-id }) ERR-EVENT-NOT-FOUND)))
      (map-set events
        { event-id: event-id }
        (merge event { metadata-uri: metadata-uri })
      )
      (ok (print { event: "metadata-updated", event-id: event-id }))
    )
  )
)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TICKET STORAGE FUNCTIONS ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-ticket (ticket-id uint))
  (map-get? tickets { ticket-id: ticket-id })
)

(define-read-only (get-ticket-owner (ticket-id uint))
  (match (map-get? tickets { ticket-id: ticket-id })
    ticket (some (get owner ticket))
    none
  )
)

(define-public (insert-ticket 
    (ticket-id uint)
    (event-id uint)
    (owner principal)
    (purchase-time uint))
  (begin
    (try! (check-authorized-and-active))
    
    ;; Validate event exists
    (asserts! (event-exists event-id) ERR_EVENT_NOT_FOUND)
    
    ;; Insert ticket
    (map-set tickets
      { ticket-id: ticket-id }
      {
        event-id: event-id,
        owner: owner,
        is-used: false,
        purchase-time: purchase-time,
        used-time: none
      }
    )
    
    ;; Create indexes
    (map-set owner-tickets
      { owner: owner, ticket-id: ticket-id }
      { event-id: event-id }
    )
    
    (map-set event-tickets
      { event-id: event-id, ticket-id: ticket-id }
      { owner: owner }
    )
    
    (print { 
      event: "ticket-minted", 
      ticket-id: ticket-id, 
      event-id: event-id,
      owner: owner 
    })
    (ok true)
  )
)

(define-public (update-ticket-owner (ticket-id uint) (new-owner principal))
  (begin
    (try! (check-authorized-and-active))
    (let (
      (ticket (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR-TICKET-NOT-FOUND))
      (old-owner (get owner ticket))
      (event-id (get event-id ticket))
    )
      ;; Update ticket owner
      (map-set tickets
        { ticket-id: ticket-id }
        (merge ticket { owner: new-owner })
      )
      
      ;; Update indexes
      (map-delete owner-tickets { owner: old-owner, ticket-id: ticket-id })
      (map-set owner-tickets
        { owner: new-owner, ticket-id: ticket-id }
        { event-id: event-id }
      )
      
      (map-set event-tickets
        { event-id: event-id, ticket-id: ticket-id }
        { owner: new-owner }
      )
      
      (print { 
        event: "ticket-transferred", 
        ticket-id: ticket-id,
        from: old-owner,
        to: new-owner
      })
      (ok true)
    )
  )
)

(define-public (mark-ticket-used (ticket-id uint))
  (begin
    (try! (check-authorized-and-active))
    (let ((ticket (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR-TICKET-NOT-FOUND)))
      ;; Prevent double-use
      (asserts! (not (get is-used ticket)) ERR-TICKET-ALREADY-USED)
      
      (map-set tickets
        { ticket-id: ticket-id }
        (merge ticket { 
          is-used: true,
          used-time: (some block-height)
        })
      )
      (ok (print { event: "ticket-used", ticket-id: ticket-id, time: block-height }))
    )
  )
)

(define-public (delete-ticket (ticket-id uint))
  (begin
    (try! (check-authorized-and-active))
    (let ((ticket (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR_TICKET_NOT_FOUND)))
      ;; Delete from all maps
      (map-delete tickets { ticket-id: ticket-id })
      (map-delete owner-tickets { owner: (get owner ticket), ticket-id: ticket-id })
      (map-delete event-tickets { event-id: (get event-id ticket), ticket-id: ticket-id })
      (ok (print { event: "ticket-deleted", ticket-id: ticket-id }))
    )
  )
)

;; Batch operation for efficiency
(define-public (batch-mark-tickets-used (ticket-ids (list 50 uint)))
  (begin
    (try! (check-authorized-and-active))
    (ok (map mark-ticket-used-internal ticket-ids))
  )
)

(define-private (mark-ticket-used-internal (ticket-id uint))
  (match (map-get? tickets { ticket-id: ticket-id })
    ticket 
      (if (not (get is-used ticket))
        (begin
          (map-set tickets
            { ticket-id: ticket-id }
            (merge ticket { 
              is-used: true,
              used-time: (some block-height)
            })
          )
          true
        )
        false
      )
    false
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;
;;VALIDATOR MANAGEMENT ;;
;;;;;;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-validator (event-id uint) (validator principal))
  (map-get? event-validators { event-id: event-id, validator: validator })
)

(define-public (set-validator (event-id uint) (validator principal) (is-active bool))
  (begin
    (try! (check-authorized-and-active))
    (asserts! (event-exists event-id) ERR-EVENT-NOT-FOUND)
    
    (map-set event-validators
      { event-id: event-id, validator: validator }
      { is-active: is-active, validated-count: u0, added-at: block-height }
    )
    (print { 
      event: "validator-updated", 
      event-id: event-id, 
      validator: validator,
      is-active: is-active 
    })
    (ok true)
  )
)

(define-public (increment-validator-count (event-id uint) (validator principal))
  (begin
    (try! (check-authorized-and-active))
    (let ((validator-data (unwrap! 
      (map-get? event-validators { event-id: event-id, validator: validator }) 
      ERR-VALIDATOR-NOT-FOUND)))
      
      (map-set event-validators
        { event-id: event-id, validator: validator }
        (merge validator-data { 
          validated-count: (+ (get validated-count validator-data) u1) 
        })
      )
      (ok true)
    )
  )
)



;;;;;;;;;;;;;;;;;;;;;;;;
;; BALANCE MANAGEMENT ;;
;;;;;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-event-balance (event-id uint))
  (map-get? event-balances { event-id: event-id })
)

(define-public (set-event-balance (event-id uint) (available uint) (locked uint))
  (begin
    (try! (check-authorized-and-active))
    (asserts! (event-exists event-id) ERR-EVENT-NOT-FOUND)
    
    (let ((current-balance (default-to 
      { available-balance: u0, locked-balance: u0, total-withdrawn: u0 }
      (map-get? event-balances { event-id: event-id }))))
      
      (map-set event-balances
        { event-id: event-id }
        { 
          available-balance: available, 
          locked-balance: locked,
          total-withdrawn: (get total-withdrawn current-balance)
        }
      )
      (ok true)
    )
  )
)

(define-public (increment-withdrawn (event-id uint) (amount uint))
  (begin
    (try! (check-authorized-and-active))
    (let ((balance (unwrap! (map-get? event-balances { event-id: event-id }) ERR-EVENT-NOT-FOUND)))
      (map-set event-balances
        { event-id: event-id }
        (merge balance { 
          total-withdrawn: (+ (get total-withdrawn balance) amount) 
        })
      )
      (ok true)
    )
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ID MANAGEMENT WITH OVERFLOW PROTECTION ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-public (increment-event-id)
  (begin
    (try! (check-authorized-and-active))
    (let ((current-id (var-get next-event-id)))
      (asserts! (< current-id MAX-UINT) ERR-OVERFLOW)
      (var-set next-event-id (+ current-id u1))
      (ok current-id)
    )
  )
)

(define-public (increment-ticket-id)
  (begin
    (try! (check-authorized-and-active))
    (let ((current-id (var-get next-ticket-id)))
      (asserts! (< current-id MAX-UINT) ERR-OVERFLOW)
      (var-set next-ticket-id (+ current-id u1))
      (ok current-id)
    )
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; QUERY HELPERS - For Frontend/Analytics ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-read-only (get-owner-ticket-info (owner principal) (ticket-id uint))
  (map-get? owner-tickets { owner: owner, ticket-id: ticket-id })
)

(define-read-only (get-organizer-event-info (organizer principal) (event-id uint))
  (map-get? organizer-events { organizer: organizer, event-id: event-id })
)

(define-read-only (is-ticket-owner (ticket-id uint) (owner principal))
  (match (get-ticket ticket-id)
    ticket (is-eq (get owner ticket) owner)
    false
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;  CONTRACT INITIALIZATIONN ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(begin
  (print { 
    event: "storage-contract-deployed", 
    owner: (var-get contract-owner)
  })
)