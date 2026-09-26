# ACP multiline acceptance

Owner: PR #47. Restore qualifier whitespace spanning line breaks (render from newline the azoth), and preserve the historical first-line greedy module-prefix removal behavior. Scan command tokens once and match qualifier suffixes at their exact offset; repeated render words no longer rescan all later text. Added three compatibility cases. Both ACP tests pass, including the bounded repeated-input child (approximately 47 ms). This closes the identified multiline acceptance gap; it is not a proof of every possible grammar equivalence.
