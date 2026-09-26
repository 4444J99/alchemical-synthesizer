"use strict";
// Credentials live only in this page. Remove credentials saved by older builds.
const session = (() => {
  try {
    localStorage.removeItem("foundry_key");
    localStorage.removeItem("foundry_email");
  } catch (_) { /* Storage may be disabled; memory-only sign-in still works. */ }
  let key = "", email = "", generation = 0;
  return {
    get key() { return key; },
    get email() { return email; },
    get generation() { return generation; },
    set(nextKey, nextEmail) { key = nextKey || ""; email = nextEmail || ""; generation++; },
    clear() { key = ""; email = ""; generation++; }
  };
})();
