# Security regression reachability and browser recheck

Owner: Alchemical PR #47.

Browser recheck of d1c5d4e51a760797d82dbdd43c6acf1f8eac9583 confirmed login then sign-out returns the login form without the stale Signed in message. Used actual dashboard and REST router with a loopback-only, temporary-data fixture; no production integrations. Closed the browser tab. Previous fixture session 36034 exited successfully after its cleanup timer. Follow-up fixture session 2635 has a 120-second self-cleanup timer.

Exact-head hosted observations: CI Minimal run 35065523895 job104694826735 failed with zero steps; CI run35065523776 job104694826183 failed with zero steps; CodeQL run35065521355 jobs104694821065/1240/1279 failed with zero steps. Admission cause and remedy are unverified. No executed test failure or scan clearance is established.

Add clean product dependency installation and all eleven security regressions to existing CI before the original smoke/release gates. Preserve all existing gates. Bound the job to ten minutes. This source change establishes scheduled reachability, not successful hosted execution. Owner of hosted execution remains the repository Actions administration lane; acceptance requires executed exact-head steps. No workflow rerun or account mutation is performed.
