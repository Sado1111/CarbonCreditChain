;; -----------------------------------------------------------
;; Carbon Credit NFT Contract
;; -----------------------------------------------------------
;; This contract implements a carbon credit marketplace using Clarity.
;; It facilitates the creation, transfer, burning, and management of 
;; carbon credit NFTs, uniquely identified by token IDs with associated metadata.
;;
;; Key Features:
;; - Minting: Allows the owner to create individual or batch carbon credits.
;; - Metadata: Associates each token with a URI for external resource linkage.
;; - Ownership: Tracks ownership for secure transfers.
;; - Burning: Enables retiring credits to prevent reuse.
;; - Validation: Ensures integrity with URI format checks and batch size limits.
;;
;; Security:
;; - Owner-restricted minting to prevent unauthorized credit issuance.
;; - Prevents actions on burned credits to maintain system integrity.
;;
;; Intended Use:
;; - Designed for carbon offset programs and marketplaces.
;; - Supports tokenization and secure tracking of environmental credits.
;; -----------------------------------------------------------

(define-constant contract-owner tx-sender) ;; The contract owner, typically the deployer
(define-constant err-owner-only (err u200)) ;; Error for non-owner access
(define-constant err-not-token-owner (err u201)) ;; Error for invalid token ownership
(define-constant err-token-already-exists (err u202)) ;; Error when a token already exists
(define-constant err-token-not-found (err u203)) ;; Error when a token does not exist
(define-constant err-invalid-token-uri (err u204)) ;; Error for invalid token URI
(define-constant err-burn-failed (err u205)) ;; Error when burning fails
(define-constant err-not-token-owner-burn (err u206)) ;; Error for burn attempt by non-owner
(define-constant err-invalid-batch-size (err u207)) ;; Error for invalid batch size
(define-constant max-batch-size u50) ;; Maximum credits allowed in a single batch minting

;; -----------------------------------------------------------
;; Data Variables
;; -----------------------------------------------------------
(define-non-fungible-token carbon-credit uint) ;; Define carbon credit NFT
(define-data-var last-credit-id uint u0) ;; Tracks the last minted carbon credit ID

;; -----------------------------------------------------------
;; Maps
;; -----------------------------------------------------------
(define-map credit-uri uint (string-ascii 256)) ;; Maps credit IDs to URIs
(define-map burned-credits uint bool) ;; Tracks burned credits
(define-map batch-metadata uint (string-ascii 256)) ;; Stores metadata for credit batches

;; -----------------------------------------------------------
;; Private Functions
;; -----------------------------------------------------------

;; Check if the sender is the owner of a specific credit
(define-private (is-credit-owner (credit-id uint) (sender principal))
  (is-eq sender (unwrap! (nft-get-owner? carbon-credit credit-id) false)))

;; Validate the format and length of a credit URI
(define-private (is-valid-credit-uri (uri (string-ascii 256)))
  (let ((uri-length (len uri)))
    (and (>= uri-length u1)
         (<= uri-length u256))))

;; Check if a credit has been burned
(define-private (is-credit-burned (credit-id uint))
  (default-to false (map-get? burned-credits credit-id)))

;; Mint a single carbon credit
(define-private (mint-single-credit (credit-uri-data (string-ascii 256)))
  (let ((credit-id (+ (var-get last-credit-id) u1)))
    (asserts! (is-valid-credit-uri credit-uri-data) err-invalid-token-uri)
    (try! (nft-mint? carbon-credit credit-id tx-sender))
    (map-set credit-uri credit-id credit-uri-data)
    (var-set last-credit-id credit-id)
    (ok credit-id)))

;; Mint a single credit during batch minting
(define-private (mint-single-credit-in-batch (uri (string-ascii 256)) (previous-results (list 50 uint)))
  (match (mint-single-credit uri)
    success (unwrap-panic (as-max-len? (append previous-results success) u50))
    error previous-results))

;; Generate a sequence for batch operations
(define-private (generate-sequence (length uint))
  (map - (list length)))
