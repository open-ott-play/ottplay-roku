"use strict";

// The legacy source-map-resolve caller expects a CommonJS function. Upstream's
// patched 0.5.1 release is ESM. Node 22.12+ / 24 can synchronously load this module.
// Keep the algorithm upstream; this adapter only preserves its old export shape.
module.exports = require("decode-uri-component-patched").default;
