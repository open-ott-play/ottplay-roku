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
ineligible, so it neither merges nor re-requests a merge. Confirm that the
timeline shows the removal and that the pull request is still open. Converting
the pull request back to a draft also stops it from being merged, and it is the
right choice when the work needs a longer pause or a redesign.

The opt-in is intentionally not permanent: adding the label again resumes
automatic merging for the current head, and reopening the pull request or
marking it ready for review again re-adds the label by itself. To keep a change
out of `main` until a person decides, keep it as a draft or merge it manually
after review instead of relying on a removed label.

Removing the label does not remove the bot approval. The approval covers one
head commit; a new commit needs a fresh independent approval before the pull
request can be merged, whether automatically or by hand.
