;; SIP-009 NFT Trait Definition
;; This trait defines the standard interface for NFT tokens on Stacks blockchain
;; Any NFT contract must implement these functions to be SIP-009 compliant
;; Written by Rogersterkaa

(define-trait nft-trait
  (
    ;; Get the last token ID minted
    ;; Returns: (response uint uint) - The highest token ID in existence
    (get-last-token-id () (response uint uint))
    
    ;; Get the URI (metadata location) for a specific token
    ;; @param token-id: The unique identifier of the token
    ;; Returns: (response (optional (string-utf8 256)) uint) - URI string or none if not set
    (get-token-uri (uint) (response (optional (string-utf8 256)) uint))
    
    ;; Get the current owner of a token
    ;; @param token-id: The unique identifier of the token
    ;; Returns: (response (optional principal) uint) - Owner's principal or none if token doesn't exist
    (get-owner (uint) (response (optional principal) uint))
    
    ;; Transfer a token from sender to recipient
    ;; @param token-id: The unique identifier of the token to transfer
    ;; @param sender: The current owner of the token
    ;; @param recipient: The new owner of the token
    ;; Returns: (response bool uint) - Success or error code
    (transfer (uint principal principal) (response bool uint))
  )
)
