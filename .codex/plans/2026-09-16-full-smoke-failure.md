# Full smoke verification failure

Owner: Alchemical PR #47. Tested head aba6d03 under limen.host_admission.hold_lease heavy, owner alchemical-security-release-20260916, surface codex_work_mode, TTL300. Each subprocess deadline180 seconds. Verified fixed smoke log names absent and HTTP3939 free before invocation; existing dist absent.

bash tools/smoke.sh --strict exited1: 55 passed, 2 failed, zero skipped. Failing predicates: rebroadcast dry-run and Ouroboros integration. Shell errors show C_ACCENT=vis.get(...) and SUB_URL=json.dumps(...) reaching eval as literal expression text, followed by unbound variables. Current python3 is Homebrew Python3.14.7 and a direct f-string sanity probe passes. Root cause not yet proven; inspect shell/Python boundary and reproduce narrowly before repair. All other printed smoke shards passed. Release packaging and checksum commands did not run because smoke failed.

Next action: repair these script-loading failures with safe value serialization, rerun implicated media shards under host admission, then run release packaging/checksums. Do not promote the earlier product-only smoke result to full release acceptance.
