;; Decentralized Social Network Contract
;; Store posts and interactions with user control over data and revenue sharing

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-POST-NOT-FOUND (err u402))
(define-constant ERR-USER-NOT-FOUND (err u403))
(define-constant ERR-INVALID-CONTENT (err u404))
(define-constant ERR-ALREADY-FOLLOWED (err u405))
(define-constant ERR-CANNOT-FOLLOW-SELF (err u406))
(define-constant ERR-NOT-FOLLOWING (err u407))
(define-constant ERR-INSUFFICIENT-BALANCE (err u408))
(define-constant ERR-CONTENT-LOCKED (err u409))

(define-constant MAX-CONTENT-LENGTH u280)
(define-constant PLATFORM-FEE u5) ;; 5%
(define-constant TIP-MINIMUM u1)

;; Data Variables
(define-data-var next-post-id uint u1)
(define-data-var total-users uint u0)
(define-data-var total-posts uint u0)
(define-data-var platform-revenue uint u0)

;; Data Maps
(define-map users
  { user: principal }
  {
    username: (string-ascii 50),
    bio: (string-ascii 200),
    followers: uint,
    following: uint,
    posts-count: uint,
    reputation: uint,
    earnings: uint,
    joined-at: uint,
    verified: bool
  }
)

(define-map posts
  { post-id: uint }
  {
    author: principal,
    content: (string-ascii 280),
    timestamp: uint,
    likes: uint,
    reposts: uint,
    replies: uint,
    tips-received: uint,
    monetized: bool,
    price: uint,
    visibility: (string-ascii 20)
  }
)

(define-map user-posts
  { user: principal, post-index: uint }
  { post-id: uint }
)

(define-map follows
  { follower: principal, following: principal }
  { timestamp: uint }
)

(define-map likes
  { post-id: uint, user: principal }
  { timestamp: uint }
)

(define-map reposts
  { post-id: uint, user: principal }
  {
    timestamp: uint,
    comment: (optional (string-ascii 100))
  }
)

(define-map tips
  { post-id: uint, tipper: principal }
  {
    amount: uint,
    timestamp: uint,
    message: (optional (string-ascii 100))
  }
)

(define-map content-purchases
  { post-id: uint, buyer: principal }
  {
    amount: uint,
    timestamp: uint
  }
)

;; Private Functions
(define-private (is-valid-content (content (string-ascii 280)))
  (and (> (len content) u0) (<= (len content) MAX-CONTENT-LENGTH))
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount PLATFORM-FEE) u100)
)

(define-private (increment-post-count (user principal))
  (let (
    (user-data (unwrap! (map-get? users { user: user }) (err u0)))
    (new-count (+ (get posts-count user-data) u1))
  )
    (map-set users
      { user: user }
      (merge user-data { posts-count: new-count })
    )
    (ok new-count)
  )
)

(define-private (add-user-post (user principal) (post-id uint))
  (let (
    (user-data (unwrap! (map-get? users { user: user }) (err u0)))
    (post-index (get posts-count user-data))
  )
    (map-set user-posts { user: user, post-index: post-index } { post-id: post-id })
    (ok post-index)
  )
)

;; Public Functions
(define-public (register-user (username (string-ascii 50)) (bio (string-ascii 200)))
  (let (
    (user tx-sender)
    (existing-user (map-get? users { user: user }))
  )
    (asserts! (is-none existing-user) ERR-USER-NOT-FOUND)
    (asserts! (> (len username) u0) ERR-INVALID-CONTENT)
    
    (map-set users
      { user: user }
      {
        username: username,
        bio: bio,
        followers: u0,
        following: u0,
        posts-count: u0,
        reputation: u100,
        earnings: u0,
        joined-at: stacks-block-height,
        verified: false
      }
    )
    
    (var-set total-users (+ (var-get total-users) u1))
    (ok u1)
  )
)

(define-public (create-post (content (string-ascii 280)) (monetized bool) (price uint) (visibility (string-ascii 20)))
  (let (
    (post-id (var-get next-post-id))
    (author tx-sender)
    (user-data (unwrap! (map-get? users { user: author }) ERR-USER-NOT-FOUND))
  )
    (asserts! (is-valid-content content) ERR-INVALID-CONTENT)
    (asserts! (or (not monetized) (> price u0)) ERR-INVALID-CONTENT)
    
    ;; Create post
    (map-set posts
      { post-id: post-id }
      {
        author: author,
        content: content,
        timestamp: stacks-block-height,
        likes: u0,
        reposts: u0,
        replies: u0,
        tips-received: u0,
        monetized: monetized,
        price: price,
        visibility: visibility
      }
    )
    
    ;; Add to user's posts
    (unwrap-panic (add-user-post author post-id))
    (unwrap-panic (increment-post-count author))
    
    ;; Update global counters
    (var-set next-post-id (+ post-id u1))
    (var-set total-posts (+ (var-get total-posts) u1))
    
    (ok post-id)
  )
)

(define-public (follow-user (user-to-follow principal))
  (let (
    (follower tx-sender)
    (existing-follow (map-get? follows { follower: follower, following: user-to-follow }))
    (follower-data (unwrap! (map-get? users { user: follower }) ERR-USER-NOT-FOUND))
    (following-data (unwrap! (map-get? users { user: user-to-follow }) ERR-USER-NOT-FOUND))
  )
    (asserts! (not (is-eq follower user-to-follow)) ERR-CANNOT-FOLLOW-SELF)
    (asserts! (is-none existing-follow) ERR-ALREADY-FOLLOWED)
    
    ;; Create follow relationship
    (map-set follows
      { follower: follower, following: user-to-follow }
      { timestamp: stacks-block-height }
    )
    
    ;; Update follower's following count
    (map-set users
      { user: follower }
      (merge follower-data { following: (+ (get following follower-data) u1) })
    )
    
    ;; Update followed user's followers count
    (map-set users
      { user: user-to-follow }
      (merge following-data { followers: (+ (get followers following-data) u1) })
    )
    
    (ok true)
  )
)

(define-public (unfollow-user (user-to-unfollow principal))
  (let (
    (follower tx-sender)
    (existing-follow (unwrap! (map-get? follows { follower: follower, following: user-to-unfollow }) ERR-NOT-FOLLOWING))
    (follower-data (unwrap! (map-get? users { user: follower }) ERR-USER-NOT-FOUND))
    (following-data (unwrap! (map-get? users { user: user-to-unfollow }) ERR-USER-NOT-FOUND))
  )
    ;; Remove follow relationship
    (map-delete follows { follower: follower, following: user-to-unfollow })
    
    ;; Update follower's following count
    (map-set users
      { user: follower }
      (merge follower-data { following: (- (get following follower-data) u1) })
    )
    
    ;; Update followed user's followers count
    (map-set users
      { user: user-to-unfollow }
      (merge following-data { followers: (- (get followers following-data) u1) })
    )
    
    (ok true)
  )
)

(define-public (like-post (post-id uint))
  (let (
    (user tx-sender)
    (post-data (unwrap! (map-get? posts { post-id: post-id }) ERR-POST-NOT-FOUND))
    (existing-like (map-get? likes { post-id: post-id, user: user }))
  )
    (asserts! (is-none existing-like) ERR-ALREADY-FOLLOWED)
    
    ;; Create like
    (map-set likes
      { post-id: post-id, user: user }
      { timestamp: stacks-block-height }
    )
    
    ;; Update post likes count
    (map-set posts
      { post-id: post-id }
      (merge post-data { likes: (+ (get likes post-data) u1) })
    )
    
    (ok true)
  )
)

(define-public (tip-post (post-id uint) (amount uint) (message (optional (string-ascii 100))))
  (let (
    (tipper tx-sender)
    (post-data (unwrap! (map-get? posts { post-id: post-id }) ERR-POST-NOT-FOUND))
    (author (get author post-data))
    (author-data (unwrap! (map-get? users { user: author }) ERR-USER-NOT-FOUND))
    (platform-fee (calculate-platform-fee amount))
    (author-share (- amount platform-fee))
  )
    (asserts! (>= amount TIP-MINIMUM) ERR-INSUFFICIENT-BALANCE)
    (asserts! (not (is-eq tipper author)) ERR-NOT-AUTHORIZED)
    
    ;; Record tip
    (map-set tips
      { post-id: post-id, tipper: tipper }
      {
        amount: amount,
        timestamp: stacks-block-height,
        message: message
      }
    )
    
    ;; Update post tips
    (map-set posts
      { post-id: post-id }
      (merge post-data { tips-received: (+ (get tips-received post-data) amount) })
    )
    
    ;; Update author earnings
    (map-set users
      { user: author }
      (merge author-data { earnings: (+ (get earnings author-data) author-share) })
    )
    
    ;; Update platform revenue
    (var-set platform-revenue (+ (var-get platform-revenue) platform-fee))
    
    (ok true)
  )
)

(define-public (purchase-content (post-id uint))
  (let (
    (buyer tx-sender)
    (post-data (unwrap! (map-get? posts { post-id: post-id }) ERR-POST-NOT-FOUND))
    (author (get author post-data))
    (price (get price post-data))
    (existing-purchase (map-get? content-purchases { post-id: post-id, buyer: buyer }))
    (author-data (unwrap! (map-get? users { user: author }) ERR-USER-NOT-FOUND))
    (platform-fee (calculate-platform-fee price))
    (author-share (- price platform-fee))
  )
    (asserts! (get monetized post-data) ERR-CONTENT-LOCKED)
    (asserts! (is-none existing-purchase) ERR-ALREADY-FOLLOWED)
    (asserts! (not (is-eq buyer author)) ERR-NOT-AUTHORIZED)
    
    ;; Record purchase
    (map-set content-purchases
      { post-id: post-id, buyer: buyer }
      {
        amount: price,
        timestamp: stacks-block-height
      }
    )
    
    ;; Update author earnings
    (map-set users
      { user: author }
      (merge author-data { earnings: (+ (get earnings author-data) author-share) })
    )
    
    ;; Update platform revenue
    (var-set platform-revenue (+ (var-get platform-revenue) platform-fee))
    
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-user (user principal))
  (map-get? users { user: user })
)

(define-read-only (get-post (post-id uint))
  (map-get? posts { post-id: post-id })
)

(define-read-only (get-user-post (user principal) (post-index uint))
  (map-get? user-posts { user: user, post-index: post-index })
)

(define-read-only (is-following (follower principal) (following principal))
  (is-some (map-get? follows { follower: follower, following: following }))
)

(define-read-only (has-liked (post-id uint) (user principal))
  (is-some (map-get? likes { post-id: post-id, user: user }))
)

(define-read-only (get-tip (post-id uint) (tipper principal))
  (map-get? tips { post-id: post-id, tipper: tipper })
)

(define-read-only (has-purchased-content (post-id uint) (buyer principal))
  (is-some (map-get? content-purchases { post-id: post-id, buyer: buyer }))
)

(define-read-only (get-platform-stats)
  {
    total-users: (var-get total-users),
    total-posts: (var-get total-posts),
    platform-revenue: (var-get platform-revenue),
    next-post-id: (var-get next-post-id)
  }
)

