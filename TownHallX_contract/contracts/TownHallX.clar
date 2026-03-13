;; title: TownHallX
;; version: 1.0.0
;; summary: On-chain verification for mayoral campaigns and municipal referendums
;; description: TownHallX brings transparent on-chain verification to mayoral
;;   campaigns and municipal referendum cycles. Authorized election officials can
;;   register candidates, create referendums, and record votes -- all publicly
;;   auditable on the Stacks blockchain.

;; ------------------------------------------
;; Constants
;; ------------------------------------------

;; Contract deployer is the initial admin
(define-constant CONTRACT_OWNER tx-sender)

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_NOT_FOUND (err u102))
(define-constant ERR_ELECTION_NOT_ACTIVE (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_INVALID_CANDIDATE (err u105))
(define-constant ERR_INVALID_INPUT (err u106))
(define-constant ERR_REFERENDUM_NOT_ACTIVE (err u107))
(define-constant ERR_ALREADY_VOTED_REFERENDUM (err u108))

;; Election / referendum status
(define-constant STATUS_PENDING u0)
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_CLOSED u2)

;; ------------------------------------------
;; Data Variables
;; ------------------------------------------

(define-data-var election-count uint u0)
(define-data-var referendum-count uint u0)

;; ------------------------------------------
;; Data Maps
;; ------------------------------------------

;; Authorized election officials
(define-map officials principal bool)

;; Elections (mayoral campaigns)
(define-map elections
  uint
  {
    title: (string-ascii 100),
    creator: principal,
    status: uint,
    candidate-count: uint,
    created-at: uint
  }
)

;; Candidates within an election
(define-map candidates
  { election-id: uint, candidate-id: uint }
  {
    name: (string-ascii 80),
    party: (string-ascii 50),
    votes: uint
  }
)

;; Track whether a voter has voted in a given election
(define-map election-voters
  { election-id: uint, voter: principal }
  bool
)

;; Referendums
(define-map referendums
  uint
  {
    question: (string-ascii 200),
    creator: principal,
    status: uint,
    votes-for: uint,
    votes-against: uint,
    created-at: uint
  }
)

;; Track whether a voter has voted in a given referendum
(define-map referendum-voters
  { referendum-id: uint, voter: principal }
  bool
)

;; ------------------------------------------
;; Private Functions
;; ------------------------------------------

(define-private (is-official-or-owner (caller principal))
  (or (is-eq caller CONTRACT_OWNER)
      (default-to false (map-get? officials caller)))
)

;; ------------------------------------------
;; Public Functions -- Administration
;; ------------------------------------------

;; Add an election official (only contract owner)
(define-public (add-official (official principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (ok (map-set officials official true))
  )
)

;; Remove an election official (only contract owner)
(define-public (remove-official (official principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (ok (map-delete officials official))
  )
)

;; ------------------------------------------
;; Public Functions -- Elections (Mayoral Campaigns)
;; ------------------------------------------

;; Create a new election
(define-public (create-election (title (string-ascii 100)))
  (let
    (
      (caller tx-sender)
      (new-id (var-get election-count))
    )
    (asserts! (is-official-or-owner caller) ERR_UNAUTHORIZED)
    (asserts! (> (len title) u0) ERR_INVALID_INPUT)
    (map-set elections new-id {
      title: title,
      creator: caller,
      status: STATUS_PENDING,
      candidate-count: u0,
      created-at: stacks-block-height
    })
    (var-set election-count (+ new-id u1))
    (ok new-id)
  )
)

;; Register a candidate for an election (must be pending)
(define-public (register-candidate
    (election-id uint)
    (name (string-ascii 80))
    (party (string-ascii 50))
  )
  (let
    (
      (caller tx-sender)
      (election (unwrap! (map-get? elections election-id) ERR_NOT_FOUND))
      (current-count (get candidate-count election))
    )
    (asserts! (is-official-or-owner caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status election) STATUS_PENDING) ERR_ELECTION_NOT_ACTIVE)
    (asserts! (> (len name) u0) ERR_INVALID_INPUT)
    (map-set candidates
      { election-id: election-id, candidate-id: current-count }
      { name: name, party: party, votes: u0 }
    )
    (map-set elections election-id
      (merge election { candidate-count: (+ current-count u1) })
    )
    (ok current-count)
  )
)

;; Activate an election so voting can begin
(define-public (activate-election (election-id uint))
  (let
    (
      (caller tx-sender)
      (election (unwrap! (map-get? elections election-id) ERR_NOT_FOUND))
    )
    (asserts! (is-official-or-owner caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status election) STATUS_PENDING) ERR_ELECTION_NOT_ACTIVE)
    (asserts! (> (get candidate-count election) u0) ERR_INVALID_INPUT)
    (ok (map-set elections election-id
      (merge election { status: STATUS_ACTIVE })))
  )
)

;; Close an election
(define-public (close-election (election-id uint))
  (let
    (
      (caller tx-sender)
      (election (unwrap! (map-get? elections election-id) ERR_NOT_FOUND))
    )
    (asserts! (is-official-or-owner caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status election) STATUS_ACTIVE) ERR_ELECTION_NOT_ACTIVE)
    (ok (map-set elections election-id
      (merge election { status: STATUS_CLOSED })))
  )
)

;; Cast a vote for a candidate in an active election
(define-public (vote-for-candidate (election-id uint) (candidate-id uint))
  (let
    (
      (voter tx-sender)
      (election (unwrap! (map-get? elections election-id) ERR_NOT_FOUND))
      (candidate (unwrap! (map-get? candidates { election-id: election-id, candidate-id: candidate-id }) ERR_INVALID_CANDIDATE))
    )
    (asserts! (is-eq (get status election) STATUS_ACTIVE) ERR_ELECTION_NOT_ACTIVE)
    (asserts! (is-none (map-get? election-voters { election-id: election-id, voter: voter })) ERR_ALREADY_VOTED)
    (map-set election-voters { election-id: election-id, voter: voter } true)
    (map-set candidates
      { election-id: election-id, candidate-id: candidate-id }
      (merge candidate { votes: (+ (get votes candidate) u1) })
    )
    (ok true)
  )
)

;; ------------------------------------------
;; Public Functions -- Referendums
;; ------------------------------------------

;; Create a new referendum
(define-public (create-referendum (question (string-ascii 200)))
  (let
    (
      (caller tx-sender)
      (new-id (var-get referendum-count))
    )
    (asserts! (is-official-or-owner caller) ERR_UNAUTHORIZED)
    (asserts! (> (len question) u0) ERR_INVALID_INPUT)
    (map-set referendums new-id {
      question: question,
      creator: caller,
      status: STATUS_PENDING,
      votes-for: u0,
      votes-against: u0,
      created-at: stacks-block-height
    })
    (var-set referendum-count (+ new-id u1))
    (ok new-id)
  )
)

;; Activate a referendum
(define-public (activate-referendum (referendum-id uint))
  (let
    (
      (caller tx-sender)
      (referendum (unwrap! (map-get? referendums referendum-id) ERR_NOT_FOUND))
    )
    (asserts! (is-official-or-owner caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status referendum) STATUS_PENDING) ERR_REFERENDUM_NOT_ACTIVE)
    (ok (map-set referendums referendum-id
      (merge referendum { status: STATUS_ACTIVE })))
  )
)

;; Close a referendum
(define-public (close-referendum (referendum-id uint))
  (let
    (
      (caller tx-sender)
      (referendum (unwrap! (map-get? referendums referendum-id) ERR_NOT_FOUND))
    )
    (asserts! (is-official-or-owner caller) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status referendum) STATUS_ACTIVE) ERR_REFERENDUM_NOT_ACTIVE)
    (ok (map-set referendums referendum-id
      (merge referendum { status: STATUS_CLOSED })))
  )
)

;; Vote on a referendum (true = for, false = against)
(define-public (vote-on-referendum (referendum-id uint) (in-favor bool))
  (let
    (
      (voter tx-sender)
      (referendum (unwrap! (map-get? referendums referendum-id) ERR_NOT_FOUND))
    )
    (asserts! (is-eq (get status referendum) STATUS_ACTIVE) ERR_REFERENDUM_NOT_ACTIVE)
    (asserts! (is-none (map-get? referendum-voters { referendum-id: referendum-id, voter: voter })) ERR_ALREADY_VOTED_REFERENDUM)
    (map-set referendum-voters { referendum-id: referendum-id, voter: voter } true)
    (map-set referendums referendum-id
      (merge referendum
        (if in-favor
          { votes-for: (+ (get votes-for referendum) u1), votes-against: (get votes-against referendum) }
          { votes-for: (get votes-for referendum), votes-against: (+ (get votes-against referendum) u1) }
        )
      )
    )
    (ok true)
  )
)

;; ------------------------------------------
;; Read-Only Functions
;; ------------------------------------------

;; Get election details
(define-read-only (get-election (election-id uint))
  (map-get? elections election-id)
)

;; Get candidate details
(define-read-only (get-candidate (election-id uint) (candidate-id uint))
  (map-get? candidates { election-id: election-id, candidate-id: candidate-id })
)

;; Check if a voter has voted in an election
(define-read-only (has-voted (election-id uint) (voter principal))
  (default-to false (map-get? election-voters { election-id: election-id, voter: voter }))
)

;; Get referendum details
(define-read-only (get-referendum (referendum-id uint))
  (map-get? referendums referendum-id)
)

;; Check if a voter has voted in a referendum
(define-read-only (has-voted-referendum (referendum-id uint) (voter principal))
  (default-to false (map-get? referendum-voters { referendum-id: referendum-id, voter: voter }))
)

;; Get total election count
(define-read-only (get-election-count)
  (var-get election-count)
)

;; Get total referendum count
(define-read-only (get-referendum-count)
  (var-get referendum-count)
)

;; Check if a principal is an authorized official
(define-read-only (is-official (who principal))
  (default-to false (map-get? officials who))
)
