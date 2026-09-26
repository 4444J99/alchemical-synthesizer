"use strict";
// Credentials live only in this page after a one-time migration from older builds.
const session = (() => {
  let key = "", email = "";
  try {
    // Preserve access once for users of the old persistent-key dashboard, then
    // remove the stored copy so all later sessions remain page-memory only.
    key = localStorage.getItem("foundry_key") || "";
    email = localStorage.getItem("foundry_email") || "";
    localStorage.removeItem("foundry_key");
    localStorage.removeItem("foundry_email");
  } catch (_) { /* Storage may be disabled; memory-only sign-in still works. */ }
  let generation = 0;
  return {
    get key() { return key; },
    get email() { return email; },
    get generation() { return generation; },
    set(nextKey, nextEmail) { key = nextKey || ""; email = nextEmail || ""; generation++; },
    clear() { key = ""; email = ""; generation++; }
  };
})();
