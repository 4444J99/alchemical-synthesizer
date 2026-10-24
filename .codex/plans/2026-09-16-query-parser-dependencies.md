# Query-parser dependency repair

Owner: Alchemical PR #47. Current Dependabot alerts 9-12 identify qs in both application lockfiles, with patched version 6.16.0. Both previously resolved 6.15.2. Update both lockfiles; the product requires a qs override because express 4.22.2/body-parser 1.20.6 constrain the older minor line. Visual Cortex dependency ranges accept 6.16.0 directly. Retain application framework majors.

Validation: npm ls qs ws passes in both applications (qs 6.16.0 and ws 8.21.3); clean npm ci passes in both; product smoke passes all 21 checks; the combined twelve security regressions pass after the update. Workflow lint passed before this lockfile-only change. Hosted dependency/security alert clearance, browser CDN load verification, broad release predicates and deployment remain separate evidence.
