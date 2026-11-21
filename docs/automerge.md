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
