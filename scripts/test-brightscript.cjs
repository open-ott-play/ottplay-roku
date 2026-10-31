"use strict";

const { spawnSync } = require("node:child_process");
const path = require("node:path");
const fs = require("node:fs");
const os = require("node:os");

const root = path.resolve(__dirname, "..");
// The test root deliberately has no SceneGraph components or network configuration.
// The interpreter executes the production pure helpers, not a JavaScript rewrite.
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "ottplay-roku-tests-"));
try {
  fs.writeFileSync(path.join(temp, "manifest"), "title=OTTPlay tests\nmajor_version=0\nminor_version=1\nbuild_version=1\n");
  const source = "https://media.example/lists/home.m3u?auth=test";
  const channel = { title: "News, one", group: "News, world", id: "one", url: "https://media.example/live/one.m3u8" };
  // @rokucommunity/brs does not model FormatJson string escaping correctly.
  // Feed valid persisted JSON to the real BrightScript reader; do not modify
  // production serialization to accommodate an interpreter limitation.
  fs.writeFileSync(path.join(temp, "state-fixture.json"), JSON.stringify({
    version: 1, playlistUrl: source, category: "favorites",
    selectedKey: JSON.stringify([source, channel.id, channel.group, channel.title, channel.url]),
    favorites: [{ source, channel }, { source, channel }, { source: "file:///secret", channel }],
  }));
  const result = spawnSync(process.execPath, [
    require.resolve("@rokucommunity/brs/bin/cli.js"), "--no-color", "--root", temp,
    path.join(root, "app/source/lib/Playlist.brs"),
    path.join(root, "app/source/lib/State.brs"),
    path.join(root, "tests/parser.brs"),
  ], { cwd: root, encoding: "utf8", timeout: 60000, maxBuffer: 1024 * 1024 });
  process.stdout.write(result.stdout || "");
  process.stderr.write(result.stderr || "");
  const marker = /\[OTT TEST RESULT\] PASS\s+(\d+)/.exec(result.stdout || "");
  if (result.error || result.status !== 0 || !marker || Number(marker[1]) < 30 || /\[FAIL\]/.test(result.stdout || "")) {
    console.error("BrightScript helper tests failed or did not finish; no hardware test is implied.");
    process.exitCode = 1;
  }
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
