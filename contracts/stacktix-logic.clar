;; StacksTix Logic Contract - SIP-009 NFT Implementation

;; PURPOSE:
;; This contract implements the business logic for the StacksTix NFT ticketing
;; platform. It is fully SIP-009 compliant, allowing tickets to be recognized
;; as standard NFTs by Stacks wallets and marketplaces.

;; FEATURES:
;; - SIP-009 NFT standard compliance
;; - Event creation and management
;; - Ticket purchase (NFT minting)
;; - Ticket validation at events
;; - Ticket transfers (secondary market)
;; - Refund system
;; - Validator management
;; - Revenue withdrawal for organizers

;; Written by: Rogersterkaa

;; Import SIP-009 NFT trait definition
;; This ensures our contract implements all required NFT standard functions
(impl-trait .sip-09.nft-trait)

;;;;;;;;;;;;;;;;;;;;;
;; CONSTANTS       ;;
;;;;;;;;;;;;;;;;;;;;;

;; Business logic error codes (200 series to distinguish from storage errors)
(define-constant ERR-NOT-AUTHORIZED (err u200))        ;; Caller not authorized for this action
(define-constant ERR-EVENT-NOT-FOUND (err u201))       ;; Event ID does not exist
(define-constant ERR-TICKET-NOT-FOUND (err u202))      ;; Ticket ID does not exist
(define-constant ERR-NOT-OWNER (err u203))             ;; Caller is not the ticket owner
(define-constant ERR-EVENT-INACTIVE (err u204))        ;; Event has been cancelled
(define-constant ERR-EVENT-SOLD-OUT (err u205))        ;; All tickets have been sold
(define-constant ERR-INSUFFICIENT-PAYMENT (err u206))  ;; Payment amount too low
(define-constant ERR-EVENT-NOT-STARTED (err u207))     ;; Event hasn't started yet
(define-constant ERR-EVENT-ENDED (err u208))           ;; Event has already ended
(define-constant ERR-TICKET-ALREADY-USED (err u209))   ;; Ticket has been validated already
(define-constant ERR-NOT-VALIDATOR (err u210))         ;; Caller is not an authorized validator
(define-constant ERR-TRANSFER-NOT-ALLOWED (err u211))  ;; Event doesn't allow transfers
(define-constant ERR-REFUND-NOT-ALLOWED (err u212))    ;; Event doesn't allow refunds
(define-constant ERR-WITHDRAW-NOT-ALLOWED (err u213))  ;; Nothing to withdraw
(define-constant ERR-INVALID-RECIPIENT (err u214))     ;; Invalid recipient address

;; Platform fee percentage (2% of ticket price)
;; Calculated as: (price * 2) / 100
(define-constant PLATFORM-FEE-PERCENT u2)

;;;;;;;;;;;;;;;;;;;;;
;; DATA VARIABLES  ;;
;;;;;;;;;;;;;;;;;;;;;

;; Storage contract principal - set this after deploying storage contract
;; This should be updated via set-storage-contract after deployment
(define-data-var storage-contract principal tx-sender)

;; Platform wallet for collecting fees
;; This should be updated via set-platform-wallet after deployment
(define-data-var platform-wallet principal tx-sender)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SIP-009 INTERFACE IMPLEMENTATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; SIP-009 Required Function: Get the last token ID minted
;; Returns the highest ticket ID that has been assigned
;; @returns: (response uint uint) - The last token ID or error
(define-read-only (get-last-token-id)
  (let ((next-id (contract-call? (var-get storage-contract) get-next-ticket-id)))
    ;; Return next-id minus 1 (since next-id is the NEXT available, not last minted)
    ;; If next-id is 1, no tickets exist yet, so return 0
    (ok (if (> next-id u0) (- next-id u1) u0))
  )
)

;; SIP-009 Required Function: Get the token URI (metadata location)
;; Returns the metadata URI for a specific ticket NFT
;; @param token-id: The ticket/NFT ID
;; @returns: (response (optional string-utf8) uint) - URI or none if not set/found
(define-read-only (get-token-uri (token-id uint))
  (begin
    ;; Get ticket to find which event it belongs to
    (match (contract-call? (var-get storage-contract) get-ticket token-id)
      ticket 
        ;; Ticket found, get event metadata
        (match (contract-call? (var-get storage-contract) get-event (get event-id ticket))
          event (ok (get metadata-uri event))  ;; Return event's metadata URI
          (ok none)                             ;; Event not found (shouldn't happen)
        )
      (ok none)  ;; Ticket not found
    )
  )
)

;; SIP-009 Required Function: Get the owner of a token
;; Returns the current owner principal of a ticket NFT
;; @param token-id: The ticket/NFT ID
;; @returns: (response (optional principal) uint) - Owner or none if not found
(define-read-only (get-owner (token-id uint))
  (begin
    ;; Query storage contract for ticket owner
    (match (contract-call? (var-get storage-contract) get-ticket-owner token-id)
      owner (ok (some owner))  ;; Wrap owner in 'some' for SIP-009 compliance
      (ok none)                 ;; Ticket not found
    )
  )
)

;; SIP-009 Required Function: Transfer a token from sender to recipient
;; Implements NFT transfer with business logic validation
;; @param token-id: The ticket/NFT ID to transfer
;; @param sender: The current owner (must match tx-sender)
;; @param recipient: The new owner
;; @returns: (response bool uint) - Success or error code
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    ;; Validate recipient is a standard principal (not a contract)
    ;; This prevents accidental burning to contract addresses
    (asserts! (is-standard principal recipient) ERR-INVALID-RECIPIENT)
    
    ;; Get ticket data to verify ownership and check business rules
    (let ((ticket (unwrap! (contract-call? (var-get storage-contract) get-ticket token-id) ERR-TICKET-NOT-FOUND)))
      
      ;; Verify the sender parameter matches the actual ticket owner
      (asserts! (is-eq (get owner ticket) sender) ERR-NOT-OWNER)
      
      ;; Verify the transaction sender is the ticket owner
      ;; This prevents someone from transferring another person's ticket
      (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
      
      ;; Get event data to check transfer policy
      (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event (get event-id ticket)) ERR-EVENT-NOT-FOUND)))
        
        ;; Check if the event allows ticket transfers (set by organizer)
        (asserts! (get transferable event) ERR-TRANSFER-NOT-ALLOWED)
        
        ;; Check if ticket has already been used for event entry
        ;; Used tickets cannot be transferred (prevents fraud)
        (asserts! (not (get is-used ticket)) ERR-TICKET-ALREADY-USED)
        
        ;; All checks passed - update ticket owner in storage
        (try! (contract-call? (var-get storage-contract) update-ticket-owner token-id recipient))
        
        ;; Emit SIP-009 compliant transfer event for wallets/explorers
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

;; Create a new event with ticket sales
;; Anyone can create an event and become the organizer
;; @param name: Event title (max 100 characters)
;; @param description: Event details (max 500 characters)
;; @param location: Venue/address (max 100 characters)
;; @param start-time: Block height when event starts
;; @param end-time: Block height when event ends
;; @param ticket-price: Price per ticket in microSTX (1 STX = 1,000,000 microSTX)
;; @param total-supply: Maximum number of tickets to sell
;; @param refund-allowed: Whether buyers can get refunds before event
;; @param transferable: Whether tickets can be resold/transferred (enables secondary market)
;; @param metadata-uri: Optional URI to off-chain metadata (IPFS, Arweave, etc.)
;; @returns: (response uint uint) - The new event ID or error
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
    ;; Generate unique event ID from storage contract
    (let ((event-id (try! (contract-call? (var-get storage-contract) increment-event-id))))
      
      ;; Insert event data into storage
      ;; Organizer is set to tx-sender (caller becomes event owner)
      (try! (contract-call? (var-get storage-contract) insert-event
        event-id
        tx-sender           ;; Organizer
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
      
      ;; Emit event creation event for indexers/frontends
      (print {
        event: "event-created",
        event-id: event-id,
        organizer: tx-sender,
        name: name,
        start-time: start-time,
        ticket-price: ticket-price
      })
      
      ;; Return the new event ID
      (ok event-id)
    )
  )
)

;; Update the metadata URI for an event
;; Only the event organizer can update metadata
;; Useful for updating images, descriptions, or other off-chain data
;; @param event-id: The event to update
;; @param metadata-uri: New URI or none to clear
;; @returns: (response bool uint) - Success or error
(define-public (update-event-metadata (event-id uint) (metadata-uri (optional (string-utf8 256))))
  (begin
    ;; Get event data to verify ownership
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is the event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Update metadata in storage contract
      (try! (contract-call? (var-get storage-contract) update-event-metadata event-id metadata-uri))
      
      (ok true)
    )
  )
)

;; Cancel an event
;; Only the event organizer can cancel
;; Sets event to inactive, preventing new ticket sales
;; Note: Does NOT automatically refund existing tickets
;; @param event-id: The event to cancel
;; @returns: (response bool uint) - Success or error
(define-public (cancel-event (event-id uint))
  (begin
    ;; Get event data to verify ownership
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is the event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Set event status to inactive in storage
      (try! (contract-call? (var-get storage-contract) update-event-status event-id false))
      
      ;; Emit cancellation event
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

;; Purchase a ticket for an event (mints NFT)
;; Creates a new SIP-009 NFT ticket and transfers payment
;; Automatically splits payment between organizer and platform
;; @param event-id: The event to buy ticket for
;; @returns: (response uint uint) - The new ticket ID or error
(define-public (purchase-ticket (event-id uint))
  (begin
    ;; Get event details to validate purchase
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Validate event is active (not cancelled)
      (asserts! (get is-active event) ERR-EVENT-INACTIVE)
      
      ;; Check ticket availability
      (let ((sold-count (get sold-count event))
            (total-supply (get total-supply event)))
        
        ;; Verify tickets are still available
        (asserts! (< sold-count total-supply) ERR-EVENT-SOLD-OUT)
        
        ;; Get ticket price for payment processing
        (let ((ticket-price (get ticket-price event)))
          
          ;; Process payment: transfer STX from buyer to this contract
          ;; Contract will hold funds until organizer withdraws
          (try! (stx-transfer? ticket-price tx-sender (as-contract tx-sender)))
          
          ;; Generate unique ticket ID
          (let ((ticket-id (try! (contract-call? (var-get storage-contract) increment-ticket-id))))
            
            ;; Create ticket (mint NFT) in storage
            (try! (contract-call? (var-get storage-contract) insert-ticket
              ticket-id
              event-id
              tx-sender          ;; Buyer becomes owner
              block-height       ;; Record purchase time
            ))
            
            ;; Update sold count to reflect new sale
            (try! (contract-call? (var-get storage-contract) update-event-sold-count event-id (+ sold-count u1)))
            
            ;; Calculate platform fee (2% of ticket price)
            (let ((platform-fee (/ (* ticket-price PLATFORM-FEE-PERCENT) u100))
                  (organizer-amount (- ticket-price platform-fee)))
              
              ;; Update event balance tracking
              ;; Lock organizer portion (available for withdrawal later)
              (let ((current-balance (default-to 
                { available-balance: u0, locked-balance: u0, total-withdrawn: u0 }
                (contract-call? (var-get storage-contract) get-event-balance event-id))))
                
                (try! (contract-call? (var-get storage-contract) set-event-balance
                  event-id
                  (get available-balance current-balance)
                  (+ (get locked-balance current-balance) organizer-amount)
                ))
              )
              
              ;; Transfer platform fee to platform wallet
              (try! (as-contract (stx-transfer? platform-fee tx-sender (var-get platform-wallet))))
            )
            
            ;; Emit SIP-009 mint event for wallets/explorers
            (print {
              event: "nft-mint-event",
              asset-identifier: (as-contract tx-sender),
              token-id: ticket-id,
              recipient: tx-sender
            })
            
            ;; Return ticket ID to buyer
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

;; Validate a ticket at event entry
;; Only authorized validators can call this
;; Marks ticket as used to prevent re-entry
;; @param ticket-id: The ticket to validate
;; @returns: (response bool uint) - Success or error
(define-public (validate-ticket (ticket-id uint))
  (begin
    ;; Get ticket details
    (let ((ticket (unwrap! (contract-call? (var-get storage-contract) get-ticket ticket-id) ERR-TICKET-NOT-FOUND)))
      
      ;; Check if ticket has already been used (prevent double-entry)
      (asserts! (not (get is-used ticket)) ERR-TICKET-ALREADY-USED)
      
      ;; Get event details for validation checks
      (let ((event-id (get event-id ticket))
            (event (unwrap! (contract-call? (var-get storage-contract) get-event (get event-id ticket)) ERR-EVENT-NOT-FOUND)))
        
        ;; Verify caller is an authorized validator for this event
        (let ((validator-data (unwrap! (contract-call? (var-get storage-contract) get-validator event-id tx-sender) ERR-NOT-VALIDATOR)))
          (asserts! (get is-active validator-data) ERR-NOT-VALIDATOR)
        )
        
        ;; Check event timing: must be between start and end time
        (asserts! (>= block-height (get start-time event)) ERR-EVENT-NOT-STARTED)
        (asserts! (<= block-height (get end-time event)) ERR-EVENT-ENDED)
        
        ;; Mark ticket as used in storage (prevents re-entry)
        (try! (contract-call? (var-get storage-contract) mark-ticket-used ticket-id))
        
        ;; Increment validator's count for analytics
        (try! (contract-call? (var-get storage-contract) increment-validator-count event-id tx-sender))
        
        ;; Emit validation event
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

;; Request a refund for a ticket
;; Only available if event allows refunds and hasn't started yet
;; Burns the ticket NFT and returns payment to buyer
;; @param ticket-id: The ticket to refund
;; @returns: (response bool uint) - Success or error
(define-public (refund-ticket (ticket-id uint))
  (begin
    ;; Get ticket details
    (let ((ticket (unwrap! (contract-call? (var-get storage-contract) get-ticket ticket-id) ERR-TICKET-NOT-FOUND)))
      
      ;; Verify caller owns the ticket
      (asserts! (is-eq tx-sender (get owner ticket)) ERR-NOT-OWNER)
      
      ;; Verify ticket hasn't been used
      (asserts! (not (get is-used ticket)) ERR-TICKET-ALREADY-USED)
      
      ;; Get event details to check refund policy
      (let ((event-id (get event-id ticket))
            (event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
        
        ;; Check if event allows refunds
        (asserts! (get refund-allowed event) ERR-REFUND-NOT-ALLOWED)
        
        ;; Check that event hasn't started yet
        (asserts! (< block-height (get start-time event)) ERR-EVENT-NOT-STARTED)
        
        ;; Get ticket price for refund
        (let ((ticket-price (get ticket-price event)))
          
          ;; Calculate organizer refund (ticket price minus platform fee)
          ;; Platform fee is not refunded
          (let ((organizer-refund (- ticket-price (/ (* ticket-price PLATFORM-FEE-PERCENT) u100))))
            
            ;; Update event balance (reduce locked balance)
            (let ((current-balance (unwrap! (contract-call? (var-get storage-contract) get-event-balance event-id) ERR-EVENT-NOT-FOUND)))
              
              (try! (contract-call? (var-get storage-contract) set-event-balance
                event-id
                (get available-balance current-balance)
                (- (get locked-balance current-balance) organizer-refund)
              ))
            )
            
            ;; Refund full ticket price to buyer
            (try! (as-contract (stx-transfer? ticket-price tx-sender (get owner ticket))))
            
            ;; Delete ticket (burn NFT) from storage
            (try! (contract-call? (var-get storage-contract) delete-ticket ticket-id))
            
            ;; Decrease sold count
            (try! (contract-call? (var-get storage-contract) update-event-sold-count 
              event-id 
              (- (get sold-count event) u1)))
            
            ;; Emit refund event
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

;; Add an authorized validator for an event
;; Only event organizer can add validators
;; Validators can check tickets at event entry
;; @param event-id: The event to add validator for
;; @param validator: The principal address of the validator
;; @returns: (response bool uint) - Success or error
(define-public (add-validator (event-id uint) (validator principal))
  (begin
    ;; Get event to verify ownership
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Add validator in storage (set active = true)
      (try! (contract-call? (var-get storage-contract) set-validator event-id validator true))
      
      (ok true)
    )
  )
)

;; Remove a validator's authorization for an event
;; Only event organizer can remove validators
;; @param event-id: The event to remove validator from
;; @param validator: The validator's principal address
;; @returns: (response bool uint) - Success or error
(define-public (remove-validator (event-id uint) (validator principal))
  (begin
    ;; Get event to verify ownership
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Remove validator in storage (set active = false)
      (try! (contract-call? (var-get storage-contract) set-validator event-id validator false))
      
      (ok true)
    )
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REVENUE WITHDRAWAL        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Withdraw accumulated revenue from ticket sales
;; Only event organizer can withdraw
;; Transfers locked balance to organizer
;; @param event-id: The event to withdraw revenue from
;; @returns: (response bool uint) - Success or error
(define-public (withdraw-event-revenue (event-id uint))
  (begin
    ;; Get event details
    (let ((event (unwrap! (contract-call? (var-get storage-contract) get-event event-id) ERR-EVENT-NOT-FOUND)))
      
      ;; Verify caller is event organizer
      (asserts! (is-eq tx-sender (get organizer event)) ERR-NOT-AUTHORIZED)
      
      ;; Get current event balance
      (let ((event-balance (unwrap! (contract-call? (var-get storage-contract) get-event-balance event-id) ERR-EVENT-NOT-FOUND)))
        
        ;; Calculate withdrawable amount (locked balance)
        (let ((withdrawable-amount (get locked-balance event-balance)))
          
          ;; Verify there is something to withdraw
          (asserts! (> withdrawable-amount u0) ERR-WITHDRAW-NOT-ALLOWED)
          
          ;; Update event balance (move locked to zero)
          (try! (contract-call? (var-get storage-contract) set-event-balance
            event-id
            (get available-balance event-balance)
            u0  ;; Clear locked balance
          ))
          
          ;; Transfer funds to organizer
          ;; Use as-contract to transfer from contract's principal
          (try! (as-contract (stx-transfer? withdrawable-amount tx-sender (get organizer event))))
          
          ;; Update total withdrawn tracking
          (try! (contract-call? (var-get storage-contract) increment-withdrawn
            event-id
            withdrawable-amount
          ))
          
          ;; Emit withdrawal event
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
  )
)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ADMIN CONFIGURATION       ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Set the storage contract principal
;; Should be called after deploying storage contract
;; Only contract deployer can call this
;; @param new-storage-contract: The storage contract's principal
;; @returns: (response bool uint) - Success or error
(define-public (set-storage-contract (new-storage-contract principal))
  (begin
    ;; Only deployer can set storage contract
    (asserts! (is-eq tx-sender (var-get storage-contract)) ERR-NOT-AUTHORIZED)
    (var-set storage-contract new-storage-contract)
    (ok true)
  )
)

;; Set the platform wallet for fee collection
;; Only contract deployer can call this
;; @param new-platform-wallet: The platform wallet's principal
;; @returns: (response bool uint) - Success or error
(define-public (set-platform-wallet (new-platform-wallet principal))
  (begin
    ;; Only deployer can set platform wallet
    (asserts! (is-eq tx-sender (var-get storage-contract)) ERR-NOT-AUTHORIZED)
    (var-set platform-wallet new-platform-wallet)
    (ok true)
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MVP FRONTEND QUERY FUNCTIONS   ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Get complete event details
(define-read-only (get-event-details (event-id uint))
  (contract-call? (var-get storage-contract) get-event event-id)
)

;; Get ticket details
(define-read-only (get-ticket-details (ticket-id uint))
  (contract-call? (var-get storage-contract) get-ticket ticket-id)
)

;; Get tickets remaining for an event
(define-read-only (get-tickets-remaining (event-id uint))
  (match (contract-call? (var-get storage-contract) get-event event-id)
    event (some (- (get total-supply event) (get sold-count event)))
    none
  )
)

;; Check if event is currently live
(define-read-only (is-event-live (event-id uint))
  (match (contract-call? (var-get storage-contract) get-event event-id)
    event (and 
      (get is-active event)
      (>= block-height (get start-time event))
      (<= block-height (get end-time event))
    )
    false
  )
)

;; Check if user is organizer
(define-read-only (is-event-organizer (event-id uint) (user principal))
  (match (contract-call? (var-get storage-contract) get-event event-id)
    event (is-eq (get organizer event) user)
    false
  )
)

;; Check if user is validator
(define-read-only (is-event-validator (event-id uint) (user principal))
  (match (contract-call? (var-get storage-contract) get-validator event-id user)
    validator (get is-active validator)
    false
  )
)

;; Get event revenue info
(define-read-only (get-event-revenue (event-id uint))
  (contract-call? (var-get storage-contract) get-event-balance event-id)
)

;; Get platform fee percentage
(define-read-only (get-platform-fee-percent)
  PLATFORM-FEE-PERCENT
)

;; Get event summary for listings
(define-read-only (get-event-summary (event-id uint))
  (match (contract-call? (var-get storage-contract) get-event event-id)
    event (some {
      event-id: event-id,
      name: (get name event),
      organizer: (get organizer event),
      location: (get location event),
      start-time: (get start-time event),
      end-time: (get end-time event),
      ticket-price: (get ticket-price event),
      tickets-remaining: (- (get total-supply event) (get sold-count event)),
      is-active: (get is-active event),
      transferable: (get transferable event)
    })
    none
  )
)