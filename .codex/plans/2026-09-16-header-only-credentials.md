# Header-only API credentials

Owner: Alchemical PR #47. Open CodeQL alerts 4 and 5 identify query-string credential extraction in the shared REST/MCP/ACP authentication helper. Remove query authentication and preserve Bearer and x-api-key header support. Repository caller inspection found the dashboard uses headers and the stdio adapter synthesizes headers from its environment; no in-repository query-key caller needs migration. Document the intentional external-client migration in product README.

Validation: the existing isolated account HTTP test now rejects a valid key supplied solely in the URL with 401, accepts x-api-key, and retains Bearer identity/revocation coverage. No request is sent to a production endpoint. Hosted scan clearance and deployment remain separate obligations.
