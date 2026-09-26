# REST resource admission

Owner: Alchemical PR #47.

Add a process-local, bounded peer-address budget before account JSON parsing/password work: signup and login share ten requests per minute. Audio reads have a separate 120-request-per-minute budget. Excess requests receive 429 and Retry-After. Track at most 10,000 peers; refuse new identities at capacity rather than evicting active budgets. Socket identity ignores untrusted forwarding headers. Behind a reverse proxy, callers share its budget until an explicit trusted-proxy deployment policy is established. Limits reset on process restart and are not distributed protection.

Validation: four tests pass, covering expiry, separate peers, spoofed forwarding, bounded cardinality, initialization errors, and actual REST routing (shared account limit before malformed-JSON parsing plus audio rejection). Existing product smoke passes 21 checks. Integration test data is isolated in a temporary directory. No account creation, password hashing or external audio source is needed for rejection tests.

Deployment-wide abuse controls and hosted CodeQL assessment remain separate evidence. Browser interaction verification, account/key identity consistency, and ACP multiline compatibility remain open source acceptance work in this PR.
