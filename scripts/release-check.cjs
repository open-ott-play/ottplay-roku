"use strict";

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");

const root = path.resolve(__dirname, "..");
const git = (...args) => execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

function main() {
  const config = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
  const tag = process.env.GITHUB_REF_NAME;
  if (!/^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(tag || "") || tag !== `v${config.version}`) {
    throw new Error("Release tag must exactly match package.json version");
  }
  const commit = git("rev-parse", "HEAD");
  if (git("rev-parse", `refs/tags/${tag}^{commit}`) !== commit) throw new Error("Tag does not point at checked-out source");
  if (git("status", "--porcelain", "--untracked-files=normal")) throw new Error("Release source tree must be clean");
  const receipt = JSON.parse(fs.readFileSync(path.join(root, "dist/release.json"), "utf8"));
  if (receipt.version !== config.version || receipt.sourceCommit !== commit || receipt.sourceDirty !== false || receipt.signedPackage !== false || receipt.hardwareTested !== false) {
    throw new Error("Release provenance does not match this validated unsigned build");
  }
  const data = fs.readFileSync(path.join(root, "dist/ottplay-roku-sideload.zip"));
  const hash = crypto.createHash("sha256").update(data).digest("hex");
  if (receipt.sha256 !== hash || receipt.bytes !== data.length || fs.readFileSync(path.join(root, "dist/SHA256SUMS"), "utf8") !== `${hash}  ottplay-roku-sideload.zip\n`) {
    throw new Error("Release artifact checksum mismatch");
  }
  const series = config.version.split(".").slice(0, 2).join(".");
  for (const previousTag of git("tag", "--list", "v*", "--merged", "HEAD").split("\n")) {
    if (previousTag === tag || !/^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(previousTag)) continue;
    let previous;
    try { previous = JSON.parse(git("show", `${previousTag}:package.json`)); } catch { continue; }
    if (previous.version.split(".").slice(0, 2).join(".") === series && Number.isInteger(previous.rokuBuild) && previous.rokuBuild >= config.rokuBuild) {
      throw new Error("rokuBuild must increase from prior tags in the same major/minor series");
    }
  }
  console.log(`Release identity and checksums verified: ${tag}, ${commit}`);
}

try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
