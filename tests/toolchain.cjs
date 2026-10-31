"use strict";

const assert = require("node:assert/strict");
const decoder = require("decode-uri-component");
const resolver = require("source-map-resolve");

assert.equal(typeof decoder, "function");
assert.equal(decoder("folder%20name"), "folder name");
// Exercise the actual legacy caller, rather than merely checking audit output.
const map = { version: 3, sources: ["source.js"], names: [], mappings: "" };
const encoded = encodeURIComponent(JSON.stringify(map));
const result = resolver.resolveSourceMapSync(`//# sourceMappingURL=data:application/json,${encoded}`, "https://example.test/app.js", () => { throw new Error("Unexpected file access"); });
assert.deepEqual(result.map, map);
console.log("Patched decoder and legacy source-map caller compatibility verified");
