# Aether static path security

Owner: Alchemical security PR #47.

Reproduced: safeResolve(".", "/%") threw URIError. Lexical path containment also permitted an existing symlink to resolve outside the serving root. Decode within the rejection boundary, canonicalize root and file paths, check containment before and after directory-index resolution, and serve only regular files. Keep trusted serving directories controlled by the deployment; this does not claim protection against a privileged local writer racing filesystem replacement.

Importing serve.js now exposes the unbound server for tests; direct execution retains listen and signal handling. Read-stream errors destroy the response rather than becoming unhandled process errors.

Verification: node --test deploy/aether/serve.test.js passed both tests. Cases include malformed encoding, NUL, encoded/plain traversal, file/directory/index symlink escape, allowed internal symlinks, missing files, and HTTP rejection followed by healthy liveness and static responses. The HTTP test uses a temporary static root; the source checkout does not contain the container-provided player directory. No deployment or hosted CodeQL clearance is inferred.

Remaining source obligations: ACP parser complexity, persistent dashboard credentials, REST rate limits. Retain other security alerts in the denominator.
