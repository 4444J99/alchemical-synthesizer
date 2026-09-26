# Account/key ownership acceptance

Owner: Alchemical PR #47. No PR review comments were present at inspection.

The usage response now exposes only the authenticated key owner email in addition to existing usage fields. The dashboard compares it with the password-login email before accepting a restored key, and rejects stale results if the current session email changed during validation. The revoke endpoint previously permitted any authenticated key to revoke another known key. Require the target active key to belong to the authenticated owner before mutation.

Verification: a temporary-data, ephemeral-HTTP two-account test confirms usage identity, rejection of cross-account revocation with the other key still active, and permitted own-key revocation. The combined security regression batch passes all 11 tests; dashboard syntax and git diff --check pass. Browser interaction remains unverified. This does not establish broad authorization completeness, hosted scan clearance, integration, or deployment.
