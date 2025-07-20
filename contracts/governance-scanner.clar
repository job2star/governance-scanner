;; governance-scanner.clar
;; Governance Tracking and Analysis Smart Contract
;; This contract provides a comprehensive framework for tracking, analyzing, 
;; and managing governance-related activities on the blockchain.
;; It creates a transparent, verifiable registry of governance interactions,
;; allowing detailed monitoring and analysis of decision-making processes.

;; ========== Error Constants ==========
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-SCANNER (err u101))
(define-constant ERR-ALREADY-REGISTERED (err u102))
(define-constant ERR-NOT-REGISTERED (err u103))
(define-constant ERR-INVALID-PROPOSAL (err u104))
(define-constant ERR-PROPOSAL-EXISTS (err u105))
(define-constant ERR-INSUFFICIENT-VOTES (err u106))
(define-constant ERR-VOTE-ALREADY-CAST (err u107))
(define-constant ERR-PROPOSAL-CLOSED (err u108))

;; ========== Data Space Definitions ==========
;; Contract Administrator
(define-data-var contract-admin principal tx-sender)

;; Registry of Authorized Governance Scanners
(define-map authorized-scanners
  principal
  {
    active: bool,
    registered-at: uint
  }
)

;; Governance Proposal Tracking
(define-map governance-proposals
  { proposal-id: uint }
  {
    creator: principal,
    title: (string-ascii 200),
    description: (string-ascii 1000),
    proposed-at: uint,
    voting-starts: uint,
    voting-ends: uint,
    status: (string-ascii 20), ;; "DRAFT", "ACTIVE", "PASSED", "REJECTED"
    votes-for: uint,
    votes-against: uint,
    total-voting-power: uint
  }
)

;; Vote Tracking
(define-map proposal-votes
  {
    proposal-id: uint,
    voter: principal
  }
  {
    vote-weight: uint,
    vote-direction: bool
  }
)

;; Counters and Statistics
(define-data-var next-proposal-id uint u1)
(define-data-var total-proposals uint u0)
(define-data-var total-active-proposals uint u0)

;; ========== Private Functions ==========
;; Check if caller is contract admin
(define-private (is-contract-admin)
  (is-eq tx-sender (var-get contract-admin))
)

;; Check if a scanner is authorized
(define-private (is-authorized-scanner (scanner principal))
  (default-to false 
    (map-get? 
      (lambda (scanner-data) (get active scanner-data)) 
      (map-get? authorized-scanners scanner)
    )
  )
)

;; ========== Read-Only Functions ==========
;; Get proposal details
(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

;; Get total governance statistics
(define-read-only (get-governance-stats)
  {
    total-proposals: (var-get total-proposals),
    active-proposals: (var-get total-active-proposals)
  }
)

;; ========== Public Functions ==========
;; Transfer contract administration
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-contract-admin) ERR-UNAUTHORIZED)
    (var-set contract-admin new-admin)
    (ok true)
  )
)

;; Register a new governance scanner
(define-public (register-scanner (scanner principal))
  (begin
    (asserts! (is-contract-admin) ERR-UNAUTHORIZED)
    (asserts! (not (is-authorized-scanner scanner)) ERR-ALREADY-REGISTERED)
    (map-set authorized-scanners scanner {
      active: true,
      registered-at: block-height
    })
    (ok true)
  )
)

;; Propose a new governance action
(define-public (create-proposal
    (title (string-ascii 200))
    (description (string-ascii 1000))
    (voting-period uint)
  )
  (let (
      (proposal-id (var-get next-proposal-id))
      (current-block block-height)
    )
    (asserts! (is-authorized-scanner tx-sender) ERR-UNAUTHORIZED)
    (map-set governance-proposals { proposal-id: proposal-id } {
      creator: tx-sender,
      title: title,
      description: description,
      proposed-at: current-block,
      voting-starts: (+ current-block u10),
      voting-ends: (+ current-block voting-period),
      status: "ACTIVE",
      votes-for: u0,
      votes-against: u0,
      total-voting-power: u0
    })
    (var-set next-proposal-id (+ proposal-id u1))
    (var-set total-proposals (+ (var-get total-proposals) u1))
    (var-set total-active-proposals (+ (var-get total-active-proposals) u1))
    (ok proposal-id)
  )
)

;; Cast a vote on a proposal
(define-public (cast-vote
    (proposal-id uint)
    (vote bool)
    (vote-weight uint)
  )
  (let (
      (proposal (unwrap! 
        (map-get? governance-proposals { proposal-id: proposal-id }) 
        ERR-INVALID-PROPOSAL
      ))
    )
    ;; Validate voting conditions
    (asserts! 
      (and 
        (is-eq (get status proposal) "ACTIVE")
        (>= block-height (get voting-starts proposal))
        (<= block-height (get voting-ends proposal))
      ) 
      ERR-PROPOSAL-CLOSED
    )
    
    ;; Check if vote already exists
    (asserts! 
      (is-none 
        (map-get? proposal-votes { 
          proposal-id: proposal-id, 
          voter: tx-sender 
        })
      ) 
      ERR-VOTE-ALREADY-CAST
    )

    ;; Record the vote
    (map-set proposal-votes { 
      proposal-id: proposal-id, 
      voter: tx-sender 
    } {
      vote-weight: vote-weight,
      vote-direction: vote
    })

    ;; Update proposal vote totals
    (map-set governance-proposals { proposal-id: proposal-id }
      (merge proposal 
        {
          votes-for: (if vote 
            (+ (get votes-for proposal) vote-weight)
            (get votes-for proposal)
          ),
          votes-against: (if (not vote)
            (+ (get votes-against proposal) vote-weight)
            (get votes-against proposal)
          ),
          total-voting-power: (+ (get total-voting-power proposal) vote-weight)
        }
      )
    )

    (ok true)
  )
)

;; Close a proposal
(define-public (close-proposal (proposal-id uint))
  (let (
      (proposal (unwrap! 
        (map-get? governance-proposals { proposal-id: proposal-id }) 
        ERR-INVALID-PROPOSAL
      ))
    )
    ;; Only can close after voting period
    (asserts! 
      (>= block-height (get voting-ends proposal)) 
      ERR-PROPOSAL-CLOSED
    )

    ;; Determine proposal outcome
    (let ((new-status 
        (if (> (get votes-for proposal) (get votes-against proposal))
          "PASSED"
          "REJECTED"
        ))
      )
      (map-set governance-proposals { proposal-id: proposal-id }
        (merge proposal { status: new-status })
      )
      (var-set total-active-proposals 
        (- (var-get total-active-proposals) u1)
      )
      (ok new-status)
    )
  )
)