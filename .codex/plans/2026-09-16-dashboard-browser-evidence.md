# Dashboard browser acceptance

Tested source: d77df6d6cd6e90d7616da4a37fdb115e46ee8240. Browser skill connected to Chrome. An isolated Express fixture mounted the actual REST router and dashboard on loopback with a temporary data directory and a 240-second self-termination/cleanup timer. No production account or deployment was touched.

Observed through browser accessibility state: signup displayed the new key and free-plan usage; reload returned to signed-out state; password login exposed the existing-key input; restoring the signup key displayed the active-session message, usage and masked key; sign-out returned to the login form. No browser storage/profile inspection was used. The test tab was closed.

Observed defect: sign-out retained the old Signed in message in the login form. This follow-up clears authentication messages and old plan/usage values on sign-out. Syntax validation applies to this small follow-up; its browser recheck remains required. The fixture omitted telemetry WebSockets and production integrations, so this is account-flow evidence only.
