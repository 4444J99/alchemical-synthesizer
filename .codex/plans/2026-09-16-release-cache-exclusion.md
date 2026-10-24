# Release cache exclusion

Owner: Alchemical PR #47. Previous verified archives included eight Python cache entries generated during smoke checks. Exclude __pycache__, pyc and pytest cache paths alongside existing dependency/build exclusions. Keep source and tests in the release. Validate shell syntax and archive exclusion behavior with a temporary fixture containing source plus generated caches; existing package build/checksum evidence applies to the unchanged packaging structure, while final release bytes will differ after this source change.
