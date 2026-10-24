# Dashboard session security

Owner: Alchemical PR #47.

Remove API keys and email from localStorage on startup. Store new credentials only in page memory, clear on sign-out, and do not reuse a previous account key after a different account login. Show a newly issued signup key once so the user can retain it in their own custody. Add an explicit existing-key field, validate it through the authenticated usage endpoint, clear the field immediately, and explain reload behavior in the account panel. Clear displayed credential material on sign-out.

Validation: two isolated VM tests pass for legacy removal, preservation of unrelated storage, no persistent writes, reload sign-out, explicit clearing, and disabled storage. node --check product/public/dashboard/app.js passes. Browser-level interaction verification remains required before claiming full dashboard acceptance. API-key ownership versus the logged-in email must also be checked in follow-up acceptance; the server currently authenticates API requests by key, independently of the password-login UI state. No hosted security clearance or deployment is claimed.

Remaining source obligations include REST rate limiting and parser multiline compatibility review. All medium-severity alerts remain in scope.
