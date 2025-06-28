;; Decentralized VPN Network Smart Contract
;; A trustless VPN service marketplace built on Stacks blockchain

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_NOT_FOUND (err u404))
(define-constant ERR_ALREADY_EXISTS (err u409))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_INVALID_PARAMETERS (err u400))
(define-constant ERR_NODE_OFFLINE (err u503))
(define-constant ERR_SESSION_EXPIRED (err u408))

;; Data Variables
(define-data-var contract-enabled bool true)
(define-data-var platform-fee-rate uint u25) ;; 2.5% in basis points
(define-data-var min-stake-amount uint u1000000) ;; 1 STX in microSTX
(define-data-var session-timeout uint u3600) ;; 1 hour in seconds

;; Data Maps
(define-map vpn-nodes
  { node-id: uint }
  {
    owner: principal,
    ip-address: (string-ascii 45),
    location: (string-ascii 100),
    bandwidth: uint, ;; Mbps
    stake-amount: uint,
    is-active: bool,
    reputation-score: uint,
    total-sessions: uint,
    created-at: uint
  }
)

(define-map user-sessions
  { session-id: uint }
  {
    user: principal,
    node-id: uint,
    start-time: uint,
    duration: uint,
    data-used: uint, ;; in MB
    cost-per-hour: uint,
    total-cost: uint,
    is-active: bool,
    created-at: uint
  }
)

(define-map node-earnings
  { node-id: uint }
  {
    total-earned: uint,
    pending-withdrawal: uint,
    last-payout: uint
  }
)

(define-map user-balances
  { user: principal }
  {
    deposited: uint,
    spent: uint,
    last-activity: uint
  }
)

(define-map node-reviews
  { review-id: uint }
  {
    reviewer: principal,
    node-id: uint,
    rating: uint, ;; 1-5 stars
    comment: (string-ascii 500),
    created-at: uint
  }
)

;; Data Variables for Counters
(define-data-var next-node-id uint u1)
(define-data-var next-session-id uint u1)
(define-data-var next-review-id uint u1)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-private (is-valid-rating (rating uint))
  (and (>= rating u1) (<= rating u5))
)

;; Public Functions

;; Register a new VPN node
(define-public (register-node (ip-address (string-ascii 45)) 
                             (location (string-ascii 100)) 
                             (bandwidth uint) 
                             (cost-per-hour uint))
  (let (
    (node-id (var-get next-node-id))
    (stake-required (var-get min-stake-amount))
  )
    (asserts! (var-get contract-enabled) ERR_UNAUTHORIZED)
    (asserts! (> bandwidth u0) ERR_INVALID_PARAMETERS)
    (asserts! (> cost-per-hour u0) ERR_INVALID_PARAMETERS)
    (asserts! (>= (stx-get-balance tx-sender) stake-required) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer stake to contract
    (try! (stx-transfer? stake-required tx-sender (as-contract tx-sender)))
    
    ;; Register the node
    (map-set vpn-nodes 
      { node-id: node-id }
      {
        owner: tx-sender,
        ip-address: ip-address,
        location: location,
        bandwidth: bandwidth,
        stake-amount: stake-required,
        is-active: true,
        reputation-score: u50, ;; Start with neutral score
        total-sessions: u0,
        created-at: block-height
      }
    )
    
    ;; Initialize earnings
    (map-set node-earnings
      { node-id: node-id }
      {
        total-earned: u0,
        pending-withdrawal: u0,
        last-payout: block-height
      }
    )
    
    ;; Increment counter
    (var-set next-node-id (+ node-id u1))
    
    (ok node-id)
  )
)

;; Deposit funds for VPN usage
(define-public (deposit-funds (amount uint))
  (let (
    (current-balance (default-to { deposited: u0, spent: u0, last-activity: u0 } 
                                 (map-get? user-balances { user: tx-sender })))
  )
    (asserts! (var-get contract-enabled) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_PARAMETERS)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update user balance
    (map-set user-balances
      { user: tx-sender }
      {
        deposited: (+ (get deposited current-balance) amount),
        spent: (get spent current-balance),
        last-activity: block-height
      }
    )
    
    (ok amount)
  )
)

;; Start a VPN session
(define-public (start-session (node-id uint) (estimated-duration uint))
  (let (
    (session-id (var-get next-session-id))
    (node-info (unwrap! (map-get? vpn-nodes { node-id: node-id }) ERR_NOT_FOUND))
    (user-balance (default-to { deposited: u0, spent: u0, last-activity: u0 } 
                              (map-get? user-balances { user: tx-sender })))
  )
    (asserts! (var-get contract-enabled) ERR_UNAUTHORIZED)
    (asserts! (get is-active node-info) ERR_NODE_OFFLINE)
    (asserts! (> estimated-duration u0) ERR_INVALID_PARAMETERS)
    
    ;; Check if user has sufficient balance
    (let ((available-balance (- (get deposited user-balance) (get spent user-balance))))
      (asserts! (> available-balance u0) ERR_INSUFFICIENT_FUNDS)
      
      ;; Create session
      (map-set user-sessions
        { session-id: session-id }
        {
          user: tx-sender,
          node-id: node-id,
          start-time: block-height,
          duration: u0,
          data-used: u0,
          cost-per-hour: u100000, ;; Default cost
          total-cost: u0,
          is-active: true,
          created-at: block-height
        }
      )
      
      ;; Increment counter
      (var-set next-session-id (+ session-id u1))
      
      (ok session-id)
    )
  )
)

;; End a VPN session and process payment
(define-public (end-session (session-id uint) (data-used uint))
  (let (
    (session-info (unwrap! (map-get? user-sessions { session-id: session-id }) ERR_NOT_FOUND))
    (node-info (unwrap! (map-get? vpn-nodes { node-id: (get node-id session-info) }) ERR_NOT_FOUND))
    (user-balance (unwrap! (map-get? user-balances { user: (get user session-info) }) ERR_NOT_FOUND))
  )
    (asserts! (var-get contract-enabled) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get user session-info)) ERR_UNAUTHORIZED)
    (asserts! (get is-active session-info) ERR_SESSION_EXPIRED)
    
    (let (
      (session-duration (- block-height (get start-time session-info)))
      (total-cost (* session-duration (get cost-per-hour session-info)))
      (platform-fee (calculate-platform-fee total-cost))
      (node-earning (- total-cost platform-fee))
      (node-earnings-info (default-to { total-earned: u0, pending-withdrawal: u0, last-payout: u0 }
                                      (map-get? node-earnings { node-id: (get node-id session-info) })))
    )
      ;; Update session
      (map-set user-sessions
        { session-id: session-id }
        (merge session-info {
          duration: session-duration,
          data-used: data-used,
          total-cost: total-cost,
          is-active: false
        })
      )
      
      ;; Update user balance
      (map-set user-balances
        { user: (get user session-info) }
        (merge user-balance {
          spent: (+ (get spent user-balance) total-cost),
          last-activity: block-height
        })
      )
      
      ;; Update node earnings
      (map-set node-earnings
        { node-id: (get node-id session-info) }
        {
          total-earned: (+ (get total-earned node-earnings-info) node-earning),
          pending-withdrawal: (+ (get pending-withdrawal node-earnings-info) node-earning),
          last-payout: (get last-payout node-earnings-info)
        }
      )
      
      ;; Update node session count
      (map-set vpn-nodes
        { node-id: (get node-id session-info) }
        (merge node-info {
          total-sessions: (+ (get total-sessions node-info) u1)
        })
      )
      
      (ok total-cost)
    )
  )
)

;; Node owner withdraws earnings
(define-public (withdraw-earnings (node-id uint))
  (let (
    (node-info (unwrap! (map-get? vpn-nodes { node-id: node-id }) ERR_NOT_FOUND))
    (earnings-info (unwrap! (map-get? node-earnings { node-id: node-id }) ERR_NOT_FOUND))
  )
    (asserts! (var-get contract-enabled) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get owner node-info)) ERR_UNAUTHORIZED)
    (asserts! (> (get pending-withdrawal earnings-info) u0) ERR_INSUFFICIENT_FUNDS)
    
    (let ((withdrawal-amount (get pending-withdrawal earnings-info)))
      ;; Transfer earnings to node owner
      (try! (as-contract (stx-transfer? withdrawal-amount tx-sender (get owner node-info))))
      
      ;; Update earnings record
      (map-set node-earnings
        { node-id: node-id }
        (merge earnings-info {
          pending-withdrawal: u0,
          last-payout: block-height
        })
      )
      
      (ok withdrawal-amount)
    )
  )
)

;; Submit a review for a node
(define-public (submit-review (node-id uint) (rating uint) (comment (string-ascii 500)))
  (let (
    (review-id (var-get next-review-id))
    (node-info (unwrap! (map-get? vpn-nodes { node-id: node-id }) ERR_NOT_FOUND))
  )
    (asserts! (var-get contract-enabled) ERR_UNAUTHORIZED)
    (asserts! (is-valid-rating rating) ERR_INVALID_PARAMETERS)
    
    ;; Create review
    (map-set node-reviews
      { review-id: review-id }
      {
        reviewer: tx-sender,
        node-id: node-id,
        rating: rating,
        comment: comment,
        created-at: block-height
      }
    )
    
    ;; Increment counter
    (var-set next-review-id (+ review-id u1))
    
    (ok review-id)
  )
)

;; Read-only functions

(define-read-only (get-node-info (node-id uint))
  (map-get? vpn-nodes { node-id: node-id })
)

(define-read-only (get-session-info (session-id uint))
  (map-get? user-sessions { session-id: session-id })
)

(define-read-only (get-user-balance (user principal))
  (map-get? user-balances { user: user })
)

(define-read-only (get-node-earnings (node-id uint))
  (map-get? node-earnings { node-id: node-id })
)

(define-read-only (get-contract-info)
  {
    enabled: (var-get contract-enabled),
    platform-fee-rate: (var-get platform-fee-rate),
    min-stake-amount: (var-get min-stake-amount),
    session-timeout: (var-get session-timeout),
    total-nodes: (- (var-get next-node-id) u1),
    total-sessions: (- (var-get next-session-id) u1)
  }
)

;; Admin functions (contract owner only)

(define-public (toggle-contract (enabled bool))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (var-set contract-enabled enabled)
    (ok enabled)
  )
)

(define-public (update-platform-fee (new-rate uint))
  (begin
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_PARAMETERS) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok new-rate)
  )
)

;; ADD THESE FUNCTIONS TO YOUR EXISTING CONTRACT
;; (Add them before the last closing parenthesis)

;; Enhanced Node Management Functions

;; Toggle node active status
(define-public (toggle-node-status (node-id uint))
  (let (
    (node-info (unwrap! (map-get? vpn-nodes { node-id: node-id }) ERR_NOT_FOUND))
  )
    (asserts! (var-get contract-enabled) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get owner node-info)) ERR_UNAUTHORIZED)
    
    (map-set vpn-nodes
      { node-id: node-id }
      (merge node-info {
        is-active: (not (get is-active node-info))
      })
    )
    
    (ok (not (get is-active node-info)))
  )
)

;; Update node bandwidth
(define-public (update-node-bandwidth (node-id uint) (new-bandwidth uint))
  (let (
    (node-info (unwrap! (map-get? vpn-nodes { node-id: node-id }) ERR_NOT_FOUND))
  )
    (asserts! (var-get contract-enabled) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender (get owner node-info)) ERR_UNAUTHORIZED)
    (asserts! (> new-bandwidth u0) ERR_INVALID_PARAMETERS)
    
    (map-set vpn-nodes
      { node-id: node-id }
      (merge node-info {
        bandwidth: new-bandwidth
      })
    )
    
    (ok new-bandwidth)
  )
)

;; Get active nodes count
(define-read-only (get-active-nodes-count)
  (let (
    (total-nodes (- (var-get next-node-id) u1))
  )
    ;; This is a simplified version - in production you'd iterate through nodes
    total-nodes
  )
)

;; Get node performance metrics
(define-read-only (get-node-performance (node-id uint))
  (let (
    (node-info (unwrap! (map-get? vpn-nodes { node-id: node-id }) ERR_NOT_FOUND))
    (earnings-info (default-to { total-earned: u0, pending-withdrawal: u0, last-payout: u0 }
                               (map-get? node-earnings { node-id: node-id })))
  )
    (ok {
      total-sessions: (get total-sessions node-info),
      reputation-score: (get reputation-score node-info),
      total-earned: (get total-earned earnings-info),
      is-active: (get is-active node-info),
      bandwidth: (get bandwidth node-info)
    })
  )
)

;; Emergency pause for specific node (admin only)
(define-public (emergency-pause-node (node-id uint))
  (let (
    (node-info (unwrap! (map-get? vpn-nodes { node-id: node-id }) ERR_NOT_FOUND))
  )
    (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
    
    (map-set vpn-nodes
      { node-id: node-id }
      (merge node-info {
        is-active: false
      })
    )
    
    (ok true)
  )
)