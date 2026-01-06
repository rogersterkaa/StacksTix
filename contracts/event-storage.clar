;; StacksTix Storage Contract

;; PURPOSE:
;; This contract serves as the data storage layer for the StacksTix NFT ticketing
;; platform. It stores all state data (events, tickets, validators, balances) and
;; can only be modified by the authorized logic contract.

;; ARCHITECTURE:
;; - Separation of concerns: Storage is isolated from business logic
;; - Security: Only the privileged logic contract can modify data
;; - Indexing: Multiple index maps for efficient queries
;; - Emergency controls: Pausable for critical situations

;; Written by: Rogersterkaa


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CONSTANTS - Error Codes ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Authorization and access control errors
(define-constant ERR-NOT-AUTHORIZED (err u100))  ;; Caller is not authorized to perform this action

;; Entity not found errors
(define-constant ERR-EVENT-NOT-FOUND (err u101))      ;; Event ID does not exist in storage
(define-constant ERR-TICKET-NOT-FOUND (err u102))     ;; Ticket ID does not exist in storage
(define-constant ERR-VALIDATOR-NOT-FOUND (err u103))  ;; Validator not registered for this event

;; Data validation errors
(define-constant ERR-OVERFLOW (err u104))          ;; Numeric overflow detected
(define-constant ERR-INVALID-SUPPLY (err u105))    ;; Total supply must be greater than zero
(define-constant ERR-INVALID-TIME-RANGE (err u106)) ;; End time must be after start time
(define-constant ERR-EVENT-IN-PAST (err u107))     ;; Cannot create event in the past
(define-constant ERR-EXCEEDS-SUPPLY (err u108))    ;; Sold count cannot exceed total supply
(define-constant ERR-TICKET-ALREADY-USED (err u109)) ;; Ticket has already been validated/used
(define-constant ERR-CONTRACT-PAUSED (err u110))   ;; Contract is paused for emergency
(define-constant ERR-INVALID-PRICE (err u111))     ;; Ticket price must be non-negative

;; Maximum safe unsigned integer value for overflow protection
;; This is the max value for uint in Clarity
(define-constant MAX-UINT u340282366920938463463374607431768211455)


;;;;;;;;;;;;;;;;;;;;
;; DATA VARIABLES ;;
;;;;;;;;;;;;;;;;;;;;

;; The principal of the authorized logic contract that can modify this storage
;; Initially set to deployer, should be updated to logic contract address after deployment
(define-data-var contract-owner principal tx-sender)

;; Emergency pause switch - when true, all state-modifying operations are blocked
;; Can only be toggled by contract owner for critical situations
(define-data-var contract-paused bool false)

;; Auto-incrementing counter for generating unique event IDs
;; Starts at 1, increments with each new event
(define-data-var next-event-id uint u1)

;; Auto-incrementing counter for generating unique ticket (NFT) IDs
;; Starts at 1, increments with each ticket mint
(define-data-var next-ticket-id uint u1)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; DATA MAPS - Core Storage ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; EVENTS MAP
;; Stores complete event information indexed by event-id
;; Each event represents a ticketed occasion (concert, conference, etc.)
(define-map events 
  { event-id: uint }  ;; Key: Unique event identifier
  {
    organizer: principal,                      ;; Event creator/owner who can manage it
    name: (string-utf8 100),                   ;; Event title (max 100 UTF-8 characters)
    description: (string-utf8 500),            ;; Event details (max 500 UTF-8 characters)
    location: (string-utf8 100),               ;; Venue/address (max 100 UTF-8 characters)
    start-time: uint,                          ;; Block height when event begins
    end-time: uint,                            ;; Block height when event ends
    ticket-price: uint,                        ;; Price per ticket in microSTX (1 STX = 1,000,000 microSTX)
    total-supply: uint,                        ;; Maximum number of tickets available
    sold-count: uint,                          ;; Current number of tickets sold
    is-active: bool,                           ;; Whether event is active (can be cancelled)
    refund-allowed: bool,                      ;; Whether ticket refunds are permitted
    transferable: bool,                        ;; Whether tickets can be transferred (SIP-009)
    metadata-uri: (optional (string-utf8 256)), ;; Optional URI to off-chain metadata (IPFS, etc.)
    created-at: uint                           ;; Block height when event was created
  }
)

;; TICKETS MAP
;; Stores NFT ticket data (SIP-009 compliant)
;; Each ticket is a unique NFT representing event admission
(define-map tickets
  { ticket-id: uint }  ;; Key: Unique ticket/NFT identifier
  {
    event-id: uint,              ;; Which event this ticket is for
    owner: principal,            ;; Current owner of the NFT ticket
    is-used: bool,               ;; Whether ticket has been validated/used for entry
    purchase-time: uint,         ;; Block height when ticket was purchased
    used-time: (optional uint)   ;; Block height when ticket was validated (none if unused)
  }
)

;; EVENT VALIDATORS MAP
;; Stores authorized staff/validators who can check tickets at events
;; Composite key allows multiple validators per event
(define-map event-validators
  { event-id: uint, validator: principal }  ;; Key: Event + Validator address
  { 
    is-active: bool,        ;; Whether this validator is currently authorized
    validated-count: uint,  ;; Number of tickets this validator has checked
    added-at: uint          ;; Block height when validator was added
  }
)

;; EVENT BALANCES MAP
;; Tracks financial state for each event
;; Separates available/locked funds for proper accounting
(define-map event-balances
  { event-id: uint }  ;; Key: Event identifier
  { 
    available-balance: uint,  ;; Funds ready for withdrawal by organizer
    locked-balance: uint,     ;; Funds locked (e.g., pending refunds)
    total-withdrawn: uint     ;; Cumulative amount withdrawn by organizer
  }
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; INDEX MAPS - For Efficient Queries ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; OWNER-TICKETS INDEX
;; Allows quick lookup of all tickets owned by a specific principal
;; Used for "my tickets" queries in wallets/frontends
(define-map owner-tickets
  { owner: principal, ticket-id: uint }  ;; Key: Owner + Ticket ID
  { event-id: uint }                     ;; Value: Which event the ticket is for
)

;; ORGANIZER-EVENTS INDEX
;; Allows quick lookup of all events created by a specific organizer
;; Used for "my events" queries in organizer dashboards
(define-map organizer-events
  { organizer: principal, event-id: uint }  ;; Key: Organizer + Event ID
  { created-at: uint }                      ;; Value: Creation timestamp
)

;; EVENT-TICKETS INDEX
;; Allows quick lookup of all tickets for a specific event
;; Used for event analytics and attendee lists
(define-map event-tickets
  { event-id: uint, ticket-id: uint }  ;; Key: Event + Ticket ID
  { owner: principal }                 ;; Value: Current ticket owner
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; AUTHORIZATION HELPERS ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Check if the caller is the authorized contract owner (logic contract)
;; This ensures only the business logic layer can modify storage
;; @returns: (response bool uint) - Success if authorized, error otherwise
(define-private (is-contract-owner)
  (ok (asserts! (is-eq contract-caller (var-get contract-owner)) ERR-NOT-AUTHORIZED))
)

;; Check if the contract is not currently paused
;; Prevents state modifications during emergency situations
;; @returns: (response bool uint) - Success if not paused, error otherwise
(define-private (is-not-paused)
  (ok (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED))
)

;; Combined check: Verify caller is authorized AND contract is not paused
;; Used by most state-modifying functions for security
;; @returns: (response bool uint) - Success if both checks pass
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

;; Get the current contract owner (should be logic contract address)
;; @returns: principal - The authorized contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Get the current pause status of the contract
;; @returns: bool - True if paused, false if active
(define-read-only (get-contract-paused)
  (var-get contract-paused)
)

;; Get the next event ID that will be assigned
;; @returns: uint - The next available event ID
(define-read-only (get-next-event-id)
  (var-get next-event-id)
)

;; Get the next ticket ID that will be assigned
;; @returns: uint - The next available ticket/NFT ID
(define-read-only (get-next-ticket-id)
  (var-get next-ticket-id)
)



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; READ-ONLY HELPERS - Existence Checks ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Check if an event exists in storage
;; @param event-id: The event ID to check
;; @returns: bool - True if event exists, false otherwise
(define-read-only (event-exists (event-id uint))
  (is-some (map-get? events { event-id: event-id }))
)

;; Check if a ticket exists in storage
;; @param ticket-id: The ticket ID to check
;; @returns: bool - True if ticket exists, false otherwise
(define-read-only (ticket-exists (ticket-id uint))
  (is-some (map-get? tickets { ticket-id: ticket-id }))
)

;; Check if a validator is registered for an event
;; @param event-id: The event ID
;; @param validator: The validator's principal
;; @returns: bool - True if validator is registered, false otherwise
(define-read-only (validator-exists (event-id uint) (validator principal))
  (is-some (map-get? event-validators { event-id: event-id, validator: validator }))
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ADMIN FUNCTIONS - Contract Management ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Transfer contract ownership to a new principal (usually the logic contract)
;; Should be called once after deployment to set logic contract as owner
;; @param new-owner: The new owner's principal address
;; @returns: (response bool uint) - Success or error
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

;; Toggle the contract pause state for emergency situations
;; When paused, all state-modifying functions are blocked
;; @param paused: True to pause, false to unpause
;; @returns: (response bool uint) - Success with event log
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

;; Retrieve complete event data by ID
;; @param event-id: The event ID to look up
;; @returns: (optional event-data) - Event details or none if not found
(define-read-only (get-event (event-id uint))
  (map-get? events { event-id: event-id })
)

;; Insert a new event into storage
;; Validates all input parameters before insertion
;; Creates necessary indexes and initializes balances
;; @param event-id: Unique identifier for the event
;; @param organizer: Principal who owns/manages the event
;; @param name: Event title
;; @param description: Event details
;; @param location: Venue information
;; @param start-time: Block height when event starts
;; @param end-time: Block height when event ends
;; @param ticket-price: Price per ticket in microSTX
;; @param total-supply: Maximum tickets available
;; @param refund-allowed: Whether refunds are permitted
;; @param transferable: Whether tickets can be transferred
;; @param metadata-uri: Optional URI to off-chain metadata
;; @returns: (response bool uint) - Success or error code
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
    ;; Verify caller is authorized and contract is not paused
    (try! (check-authorized-and-active))
    
    ;; Validate input parameters
    (asserts! (> total-supply u0) ERR-INVALID-SUPPLY)          ;; Must have at least 1 ticket
    (asserts! (< start-time end-time) ERR-INVALID-TIME-RANGE)  ;; End must be after start
    (asserts! (>= start-time block-height) ERR-EVENT-IN-PAST)  ;; Cannot create past events
    (asserts! (>= ticket-price u0) ERR-INVALID-PRICE)          ;; Price cannot be negative
    
    ;; Insert event data into main storage map
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
        sold-count: u0,              ;; Start with zero sales
        is-active: true,             ;; New events are active by default
        refund-allowed: refund-allowed,
        transferable: transferable,
        metadata-uri: metadata-uri,
        created-at: block-height     ;; Record creation time
      }
    )
    
    ;; Create organizer index for "my events" queries
    (map-set organizer-events
      { organizer: organizer, event-id: event-id }
      { created-at: block-height }
    )
    
    ;; Initialize financial tracking with zero balances
    (map-set event-balances
      { event-id: event-id }
      { available-balance: u0, locked-balance: u0, total-withdrawn: u0 }
    )
    
    ;; Emit event creation log for indexers/frontends
    (print { 
      event: "event-created", 
      event-id: event-id, 
      organizer: organizer,
      name: name
    })
    (ok true)
  )
)

;; Update the sold ticket count for an event
;; Used when tickets are purchased or refunded
;; @param event-id: The event to update
;; @param new-count: The new sold count
;; @returns: (response bool uint) - Success or error
(define-public (update-event-sold-count (event-id uint) (new-count uint))
  (begin
    ;; Verify authorization
    (try! (check-authorized-and-active))
    
    ;; Get current event data
    (let ((event (unwrap! (map-get? events { event-id: event-id }) ERR-EVENT-NOT-FOUND)))
      ;; Validate new count doesn't exceed total supply
      (asserts! (<= new-count (get total-supply event)) ERR-EXCEEDS-SUPPLY)
      
      ;; Update sold count while preserving other fields
      (map-set events
        { event-id: event-id }
        (merge event { sold-count: new-count })
      )
      (ok (print { event: "sold-count-updated", event-id: event-id, new-count: new-count }))
    )
  )
)

;; Update the active status of an event
;; Used to cancel events or reactivate them
;; @param event-id: The event to update
;; @param is-active: New active status (false = cancelled)
;; @returns: (response bool uint) - Success or error
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

;; Update the metadata URI for an event
;; Allows organizers to update off-chain metadata (images, detailed info, etc.)
;; @param event-id: The event to update
;; @param metadata-uri: New URI or none to clear
;; @returns: (response bool uint) - Success or error
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

;; Retrieve complete ticket data by ID
;; @param ticket-id: The ticket/NFT ID to look up
;; @returns: (optional ticket-data) - Ticket details or none if not found
(define-read-only (get-ticket (ticket-id uint))
  (map-get? tickets { ticket-id: ticket-id })
)

;; Get the current owner of a ticket (for SIP-009 compliance)
;; @param ticket-id: The ticket/NFT ID
;; @returns: (optional principal) - Owner's address or none if ticket doesn't exist
(define-read-only (get-ticket-owner (ticket-id uint))
  (match (map-get? tickets { ticket-id: ticket-id })
    ticket (some (get owner ticket))  ;; Return owner if ticket exists
    none                               ;; Return none if ticket not found
  )
)

;; Insert a new ticket into storage (mint)
;; Creates all necessary indexes for efficient queries
;; @param ticket-id: Unique ticket/NFT identifier
;; @param event-id: Which event this ticket is for
;; @param owner: Initial owner of the ticket
;; @param purchase-time: Block height when purchased
;; @returns: (response bool uint) - Success or error
(define-public (insert-ticket 
    (ticket-id uint)
    (event-id uint)
    (owner principal)
    (purchase-time uint))
  (begin
    ;; Verify authorization
    (try! (check-authorized-and-active))
    
    ;; Validate event exists before creating ticket
    (asserts! (event-exists event-id) ERR-EVENT-NOT-FOUND)
    
    ;; Insert ticket data into main storage map
    (map-set tickets
      { ticket-id: ticket-id }
      {
        event-id: event-id,
        owner: owner,
        is-used: false,            ;; New tickets are unused
        purchase-time: purchase-time,
        used-time: none            ;; No use time yet
      }
    )
    
    ;; Create owner index for "my tickets" queries
    (map-set owner-tickets
      { owner: owner, ticket-id: ticket-id }
      { event-id: event-id }
    )
    
    ;; Create event index for analytics/attendee lists
    (map-set event-tickets
      { event-id: event-id, ticket-id: ticket-id }
      { owner: owner }
    )
    
    ;; Emit mint event for indexers
    (print { 
      event: "ticket-minted", 
      ticket-id: ticket-id, 
      event-id: event-id,
      owner: owner 
    })
    (ok true)
  )
)

;; Update ticket ownership (for SIP-009 transfers)
;; Updates all indexes to maintain query efficiency
;; @param ticket-id: The ticket to transfer
;; @param new-owner: The new owner's principal
;; @returns: (response bool uint) - Success or error
(define-public (update-ticket-owner (ticket-id uint) (new-owner principal))
  (begin
    (try! (check-authorized-and-active))
    (let (
      (ticket (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR-TICKET-NOT-FOUND))
      (old-owner (get owner ticket))
      (event-id (get event-id ticket))
    )
      ;; Update ticket owner in main storage
      (map-set tickets
        { ticket-id: ticket-id }
        (merge ticket { owner: new-owner })
      )
      
      ;; Update owner index: remove old owner entry
      (map-delete owner-tickets { owner: old-owner, ticket-id: ticket-id })
      ;; Add new owner entry
      (map-set owner-tickets
        { owner: new-owner, ticket-id: ticket-id }
        { event-id: event-id }
      )
      
      ;; Update event index with new owner
      (map-set event-tickets
        { event-id: event-id, ticket-id: ticket-id }
        { owner: new-owner }
      )
      
      ;; Emit transfer event
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

;; Mark a ticket as used/validated for event entry
;; Records the block height when ticket was validated
;; @param ticket-id: The ticket to mark as used
;; @returns: (response bool uint) - Success or error
(define-public (mark-ticket-used (ticket-id uint))
  (begin
    (try! (check-authorized-and-active))
    (let ((ticket (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR-TICKET-NOT-FOUND)))
      ;; Prevent double-use of tickets
      (asserts! (not (get is-used ticket)) ERR-TICKET-ALREADY-USED)
      
      ;; Update ticket status
      (map-set tickets
        { ticket-id: ticket-id }
        (merge ticket { 
          is-used: true,
          used-time: (some block-height)  ;; Record when ticket was used
        })
      )
      (ok (print { event: "ticket-used", ticket-id: ticket-id, time: block-height }))
    )
  )
)

;; Delete a ticket from storage (for refunds/burns)
;; Removes ticket from all maps and indexes
;; @param ticket-id: The ticket to delete
;; @returns: (response bool uint) - Success or error
(define-public (delete-ticket (ticket-id uint))
  (begin
    (try! (check-authorized-and-active))
    (let ((ticket (unwrap! (map-get? tickets { ticket-id: ticket-id }) ERR-TICKET-NOT-FOUND)))
      ;; Delete from main storage
      (map-delete tickets { ticket-id: ticket-id })
      ;; Delete from owner index
      (map-delete owner-tickets { owner: (get owner ticket), ticket-id: ticket-id })
      ;; Delete from event index
      (map-delete event-tickets { event-id: (get event-id ticket), ticket-id: ticket-id })
      (ok (print { event: "ticket-deleted", ticket-id: ticket-id }))
    )
  )
)

;; Batch mark multiple tickets as used (for efficiency at event entry)
;; Processes up to 50 tickets in one transaction
;; @param ticket-ids: List of ticket IDs to mark as used
;; @returns: (response (list 50 bool) uint) - List of success/failure for each ticket
(define-public (batch-mark-tickets-used (ticket-ids (list 50 uint)))
  (begin
    (try! (check-authorized-and-active))
    (ok (map mark-ticket-used-internal ticket-ids))
  )
)

;; Internal helper for batch ticket validation
;; @param ticket-id: Single ticket to mark as used
;; @returns: bool - True if successfully marked, false otherwise
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
        false  ;; Already used
      )
    false  ;; Ticket not found
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;
;; VALIDATOR MANAGEMENT ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Retrieve validator data for an event
;; @param event-id: The event ID
;; @param validator: The validator's principal
;; @returns: (optional validator-data) - Validator info or none if not registered
(define-read-only (get-validator (event-id uint) (validator principal))
  (map-get? event-validators { event-id: event-id, validator: validator })
)

;; Add or update a validator for an event
;; Validators are authorized to check tickets at event entry
;; @param event-id: The event to add validator for
;; @param validator: The validator's principal address
;; @param is-active: Whether validator is active (false = revoked)
;; @returns: (response bool uint) - Success or error
(define-public (set-validator (event-id uint) (validator principal) (is-active bool))
  (begin
    (try! (check-authorized-and-active))
    ;; Verify event exists
    (asserts! (event-exists event-id) ERR-EVENT-NOT-FOUND)
    
    ;; Add/update validator
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

;; Increment the count of tickets validated by a specific validator
;; Used for analytics and validator performance tracking
;; @param event-id: The event ID
;; @param validator: The validator who checked a ticket
;; @returns: (response bool uint) - Success or error
(define-public (increment-validator-count (event-id uint) (validator principal))
  (begin
    (try! (check-authorized-and-active))
    (let ((validator-data (unwrap! 
      (map-get? event-validators { event-id: event-id, validator: validator }) 
      ERR-VALIDATOR-NOT-FOUND)))
      
      ;; Increment validated count
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

;; Retrieve financial balance data for an event
;; @param event-id: The event ID
;; @returns: (optional balance-data) - Balance info or none if not found
(define-read-only (get-event-balance (event-id uint))
  (map-get? event-balances { event-id: event-id })
)

;; Update the financial balance for an event
;; Tracks available funds, locked funds, and withdrawal history
;; @param event-id: The event to update
;; @param available: Available balance for withdrawal
;; @param locked: Locked balance (e.g., for pending refunds)
;; @returns: (response bool uint) - Success or error
(define-public (set-event-balance (event-id uint) (available uint) (locked uint))
  (begin
    (try! (check-authorized-and-active))
    (asserts! (event-exists event-id) ERR-EVENT-NOT-FOUND)
    
    ;; Get current balance or default to zero
    (let ((current-balance (default-to 
      { available-balance: u0, locked-balance: u0, total-withdrawn: u0 }
      (map-get? event-balances { event-id: event-id }))))
      
      ;; Update balances while preserving withdrawal history
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

;; Increment the total withdrawn amount for an event
;; Called when organizer withdraws revenue
;; @param event-id: The event ID
;; @param amount: Amount withdrawn in microSTX
;; @returns: (response bool uint) - Success or error
(define-public (increment-withdrawn (event-id uint) (amount uint))
  (begin
    (try! (check-authorized-and-active))
    (let ((balance (unwrap! (map-get? event-balances { event-id: event-id }) ERR-EVENT-NOT-FOUND)))
      ;; Add to total withdrawn
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

;; Generate and return the next available event ID
;; Increments the counter for subsequent calls
;; @returns: (response uint uint) - The new event ID or overflow error
(define-public (increment-event-id)
  (begin
    (try! (check-authorized-and-active))
    (let ((current-id (var-get next-event-id)))
      ;; Prevent overflow beyond max uint value
      (asserts! (< current-id MAX-UINT) ERR-OVERFLOW)
      ;; Increment for next call
      (var-set next-event-id (+ current-id u1))
      ;; Return current ID for use
      (ok current-id)
    )
  )
)

;; Generate and return the next available ticket ID
;; Increments the counter for subsequent calls
;; @returns: (response uint uint) - The new ticket ID or overflow error
(define-public (increment-ticket-id)
  (begin
    (try! (check-authorized-and-active))
    (let ((current-id (var-get next-ticket-id)))
      ;; Prevent overflow beyond max uint value
      (asserts! (< current-id MAX-UINT) ERR-OVERFLOW)
      ;; Increment for next call
      (var-set next-ticket-id (+ current-id u1))
      ;; Return current ID for use
      (ok current-id)
    )
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; QUERY HELPERS - For Frontend/Analytics ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Get index data showing which event a specific user's ticket is for
;; @param owner: The ticket owner's principal
;; @param ticket-id: The ticket ID
;; @returns: (optional {event-id: uint}) - Event info or none
(define-read-only (get-owner-ticket-info (owner principal) (ticket-id uint))
  (map-get? owner-tickets { owner: owner, ticket-id: ticket-id })
)

;; Get index data showing when an organizer created a specific event
;; @param organizer: The event organizer's principal
;; @param event-id: The event ID
;; @returns: (optional {created-at: uint}) - Creation time or none
(define-read-only (get-organizer-event-info (organizer principal) (event-id uint))
  (map-get? organizer-events { organizer: organizer, event-id: event-id })
)

;; Check if a specific principal owns a ticket
;; @param ticket-id: The ticket ID to check
;; @param owner: The principal to verify ownership
;; @returns: bool - True if owner matches, false otherwise
(define-read-only (is-ticket-owner (ticket-id uint) (owner principal))
  (match (get-ticket ticket-id)
    ticket (is-eq (get owner ticket) owner)
    false  ;; Ticket doesn't exist, so owner is false
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CONTRACT INITIALIZATION ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Emit deployment event when contract is initialized
;; Logs the initial owner for off-chain tracking
(begin
  (print { 
    event: "storage-contract-deployed", 
    owner: (var-get contract-owner)
  })
)