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

;; -----------------------------------------------------------
;; Public Functions
;; -----------------------------------------------------------

;; Mint a single carbon credit
(define-public (mint-carbon-credit (credit-uri-data (string-ascii 256)))
    (begin
        ;; Validate the caller is the contract owner
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)

        ;; Explicitly validate the credit URI before passing to `mint-single-credit`
        (asserts! (is-valid-credit-uri credit-uri-data) err-invalid-token-uri)

        ;; Mint the carbon credit
        (mint-single-credit credit-uri-data)))

;; Batch mint carbon credits
(define-public (batch-mint-carbon-credits (uris (list 50 (string-ascii 256))))
  (let ((batch-size (len uris)))
    (begin
      (asserts! (is-eq tx-sender contract-owner) err-owner-only)
      (asserts! (<= batch-size max-batch-size) err-invalid-batch-size)
      (asserts! (> batch-size u0) err-invalid-batch-size)
      (ok (fold mint-single-credit-in-batch uris (list))))))

;; Burn a carbon credit
(define-public (burn-carbon-credit (credit-id uint))
  (let ((credit-owner (unwrap! (nft-get-owner? carbon-credit credit-id) err-token-not-found)))
    (asserts! (is-eq tx-sender credit-owner) err-not-token-owner)
    (asserts! (not (is-credit-burned credit-id)) err-burn-failed)
    (try! (nft-burn? carbon-credit credit-id credit-owner))
    (map-set burned-credits credit-id true)
    (ok true)))

;; Transfer a carbon credit
(define-public (transfer-carbon-credit (credit-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq recipient tx-sender) err-not-token-owner)
    (asserts! (not (is-credit-burned credit-id)) err-burn-failed)
    (let ((actual-sender (unwrap! (nft-get-owner? carbon-credit credit-id) err-not-token-owner)))
      (asserts! (is-eq actual-sender sender) err-not-token-owner)
      (try! (nft-transfer? carbon-credit credit-id sender recipient))
      (ok true))))

;; Update the URI of an existing credit
(define-public (update-credit-uri (credit-id uint) (new-uri (string-ascii 256)))
  (let ((credit-owner (unwrap! (nft-get-owner? carbon-credit credit-id) err-token-not-found)))
    (asserts! (is-eq credit-owner tx-sender) err-not-token-owner)
    (asserts! (is-valid-credit-uri new-uri) err-invalid-token-uri)
    (map-set credit-uri credit-id new-uri)
    (ok true)))

;; -----------------------------------------------------------
;; Read-Only Functions
;; -----------------------------------------------------------

;; Fetch the URI of a carbon credit
(define-read-only (get-credit-uri (credit-id uint))
  (ok (map-get? credit-uri credit-id)))

;; Fetch the owner of a carbon credit
(define-read-only (get-credit-owner (credit-id uint))
  (ok (nft-get-owner? carbon-credit credit-id)))

;; Fetch the last minted credit ID
(define-read-only (get-last-credit-id)
  (ok (var-get last-credit-id)))

;; Check if a credit is burned
(define-read-only (is-credit-burned-status (credit-id uint))
  (ok (is-credit-burned credit-id)))

;; Fetch batch metadata
(define-read-only (get-batch-credit-ids (start-id uint) (count uint))
  (ok (map uint-to-response
      (unwrap-panic (as-max-len?
        (list-tokens start-id count)
        u50)))))

;; Helper to convert uint to response
(define-private (uint-to-response (id uint))
  {
    credit-id: id,
    uri: (unwrap-panic (get-credit-uri id)),
    owner: (unwrap-panic (get-credit-owner id)),
    burned: (unwrap-panic (is-credit-burned-status id))
  })

;; Helper to list tokens
(define-private (list-tokens (start uint) (count uint))
  (map +
    (list start)
    (generate-sequence count)))

;; -----------------------------------------------------------
;; Contract Initialization
;; -----------------------------------------------------------
(begin
  (var-set last-credit-id u0)) ;; Initialize the last credit ID
