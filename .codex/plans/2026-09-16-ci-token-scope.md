# CI token scope

Owner: Alchemical PR #47. Live open CodeQL findings 1 and 2 identify missing workflow permissions in ci.yml and ci-minimal.yml. Both workflows need repository read access for checkout and local validation; neither performs repository writes. Declare contents: read at workflow scope, leaving all other token permissions none. Preserve smoke, regression, release-artifact, validation and secret checks. The first actionlint run exposed an existing ambiguous shell AND/OR conditional in seed validation. Replace it with explicit if/else; actionlint then validates both workflows. This repairs the source declaration; executed hosted scans and alert clearance remain unverified.

Other medium findings remain recorded by current CodeQL alerts: untrusted CDN scripts (8/9/10), query-string credentials (4/5), and the prototype-pollution utility example (3). They remain obligations rather than exclusions from health.
