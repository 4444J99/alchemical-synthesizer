# ACP prompt parsing security

Owner: Alchemical PR #47. Source predecessor 915bf1f.

The original interpret function exceeded a three-second subprocess deadline on 50,000 repetitions of "list " (250 KB). Replace repeated wildcard suffix searches with one first-command lookup and one suffix scan per line, retaining action priority. Replace the greedy module-filter prefix removal with a direct last-module offset. Structured directives and ordinary natural-language forms remain supported without introducing an arbitrary smaller prompt limit.

Validation: two ACP tests pass, including thirteen structured/ordinary/precedence cases and four large repeated-input cases in a child process with a three-second hard deadline. The repeated-input child finished in approximately 44 ms on this host. Existing product smoke: 21 passed, zero failed. Static-server regression tests passed separately on the unchanged static-server source. Performance evidence is local and bounded, not a hosted scan-clearance or deployment receipt.

Remaining source work: dashboard persistent credential storage and REST rate limits; other severity categories remain part of the health denominator. Review multiline grammar edge cases as part of parser acceptance; no full semantic-equivalence claim is made.
