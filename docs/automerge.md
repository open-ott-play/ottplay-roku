# Automatic merge for trusted pull requests

Same-repository pull requests from the trusted authors listed in
[`automerge-label.yml`](../.github/workflows/automerge-label.yml) are merged by
automation once the required checks pass and an independent approval exists.
The `automerge` label is the opt-in signal the reusable merge workflow reads; a
pull request without it is never merged automatically.

## What happens to a trusted pull request

1. Opening a pull request does not label it while it is a draft.
2. Marking it ready for review, reopening it, or opening it as non-draft lets
   [`automerge-label.yml`](../.github/workflows/automerge-label.yml) add the
   `automerge` label. Draft pull requests are skipped, so a draft can be prepared
   without being queued for a merge.
3. [`auto-approve.yml`](../.github/workflows/auto-approve.yml) submits the
   independent approval from the bot account.
4. [`auto-merge.yml`](../.github/workflows/auto-merge.yml) waits for the named
   required checks and the approval, then squash-merges the exact verified head
   commit. It re-reads the pull request before merging, so a withdrawn opt-in
   stops that evaluation instead of racing it.

A pushed commit does not re-add the label. Only a new `opened`, `reopened` or
`ready_for_review` event does, so a withdrawn pull request stays withdrawn while
it is being repaired.

## Opt out deliberately

Remove the label while the pull request is still open and its required checks
have not finished:

```sh
gh pr edit <number> --repo open-ott-play/ottplay-roku --remove-label automerge
```

The `unlabeled` event makes the merge workflow evaluate the pull request as
ineligible, so it neither merges nor re-requests a merge. Remove the label once the labeler's own
`opened` run has finished: removing it within seconds can lose that race,
because the queued run adds the label afterwards and the pull request
then merges. The timeline shows whether the last `labeled` event came
from a person or from `github-actions[bot]`; remove again if it did. Confirm that the
timeline shows the removal and that the pull request is still open. Converting
the pull request back to a draft also stops it from being merged, and it is the
right choice when the work needs a longer pause or a redesign.

The withdrawal holds until the next `opened`, `reopened` or `ready_for_review`
event: adding the label again resumes automatic merging for the current head,
and those events re-add it by themselves. A removed label is a pause for
repairs, not a permanent veto. To keep a change out of `main` until a person
decides, leave it as a draft or merge it manually, and do not rely on a removed
label alone.

Removing the label does not remove the bot approval. The approval covers one
head commit; a new commit needs a fresh independent approval before the pull
request can be merged, whether automatically or by hand.

## Renovate pull requests

Renovate runs under the `californiantiramisu` account here, so its pull
requests appear under that author and match the labeler allowlist on their
own. They receive `automerge` from a second source as well. The shared
preset they extend (`local>victron-venus/venus-os-ci-toolkit:renovate-fleet`,
which extends `renovate-ci`) sets `"addLabels": ["automerge"]`, so Renovate
applies the label itself when it opens the pull request;
[`automerge-label.yml`](../.github/workflows/automerge-label.yml) also matches
those pull requests, which makes the label look like it comes only from CI.

The label is still a merge opt-in, not Renovate's own automerge: the preset
sets `"automerge": false`, so Renovate never merges by itself.

Removing the label there is not undone by a rebase or a version update.
Renovate only synchronizes labels while the pull request carries exactly the
labels it recorded at creation; once another account changes them, it stops
updating them for that pull request. Only the `opened`, `reopened` and
`ready_for_review` events above add the label back.

The withdrawal does not transfer to a replacement pull request: a new one that
Renovate opens later starts with the preset label again. To stop Renovate from
touching an open dependency pull request, apply its `stop-updating` label
(`stopUpdatingLabel`), which this repository already defines. To stop labelling
dependency pull requests at all, set `addLabels` or `automerge: false` for the
matching `packageRules` in the preset instead of removing labels one by one.

## Verified on a live rebase

A manual Renovate 44.215.0 run against this repository opened pull request #43
(`renovate/ci-workflows`) on 21 November 2026. Its timeline shows a withdrawn
label surviving a rebase:

| Time (UTC) | Event |
| --- | --- |
| 23:00:25 | Renovate opens the pull request carrying the preset's `automerge` label. |
| 23:01:13 | `automerge` is removed by hand while the checks are still running. |
| 23:07:52 | `main` has moved, so Renovate force-pushes the branch: `d829dc5` becomes `a8c70fe`. |
| 23:09:53 | A person adds `automerge` back for the new head. |
| 23:10:41 | The pull request is squash-merged as `88823b6`. |

Between 23:01:13 and 23:09:53 the timeline has no `labeled` event, and the pull
request carried no `automerge` label across the force push. The rebase replaced
the head commit and still did not restore the label, so the withdrawal stayed
in force with the checks green. The label returned only because a person added
it, which is what allowed the merge at 23:10:41.

## Running Renovate for one repository

The fleet workflow covers the whole organisation, which makes it a slow way to
check this repository alone. A local run is enough, but six environment
details decide whether it works. The values below are examples: replace the
registry with a reachable mirror and the author with the account behind the
token.

```sh
export RENOVATE_TOKEN="$(gh auth token)"
export RENOVATE_PLATFORM=github
export RENOVATE_REPOSITORIES=open-ott-play/ottplay-roku
export RENOVATE_NPMRC='registry=https://npm.example.com/'
export npm_config_registry='https://npm.example.com/'
export RENOVATE_GIT_AUTHOR='renovate-bot <1234567+renovate-bot@users.noreply.github.com>'
export LOG_LEVEL=debug
npx --yes renovate@44.215.0 --dry-run=full
```

- **Pin the Renovate version.** An unpinned run resolves whatever is current,
  so its output cannot be compared with the fleet workflow or reproduced
  later. Renovate 44.215.0 is the version the checks above describe.
- **Run it on Node 24.** Renovate validates its runtime at startup: Node 26
  stops with `Unsupported node environment detected`, and Node 22 is too old
  and fails with `TypeError: RegExp.escape is not a function`. The engine
  range in `package.json` describes this application, not Renovate, so it does
  not grant permission to use those runtimes.
- **Give it a reachable npm registry, twice.** Where `registry.npmjs.org` is
  blocked, dependency lookups fail with `read ENOTCONN`. `RENOVATE_NPMRC`
  takes `.npmrc` lines, so `registry=https://npm.example.com/` sends
  Renovate's own package manager calls to a mirror. It does not cover `npx`,
  which downloads Renovate itself: that download reads `npm_config_registry`
  (or a real `~/.npmrc`), so set both or `npx` fails to fetch the pinned
  version.
- **Set the log level through the environment.** This Renovate release has no
  `--log-level` flag; `--log-level=debug` stops the run immediately with
  `error: unknown option '--log-level=debug'`. Export `LOG_LEVEL=debug`
  instead. A debug run then prints `DEBUG:` lines right below the `INFO:
  Renovate started` header, starting with `DEBUG: Using RE2 regex engine`;
  without them the level did not take effect.
- **Set the git author to the pushing account.** The branch is pushed as
  `RENOVATE_GIT_AUTHOR` over `RENOVATE_TOKEN`, and a mismatch makes GitHub
  reject the push with `GH007: Your push would publish a private email
  address`. Use that account's noreply address, which for a bot account looks
  like `1234567+renovate-bot@users.noreply.github.com`, with the numeric id
  and login from the token's account.

The run is scoped only by `RENOVATE_REPOSITORIES`: the CLI does not accept a
`--repositories` flag, and without the variable it uses whatever the shared
configuration lists. Start with `--dry-run=full`, which prints the pull
requests it would create or update without pushing anything; drop the flag for
a real pull request, which opens under the token's account and author. The
preset's `prHourlyLimit: 1` then applies to that run too: a second dependency
pull request in the same UTC hour is skipped with `Hourly PRs limit reached`,
so wait for the next hour instead of lowering the limit.
