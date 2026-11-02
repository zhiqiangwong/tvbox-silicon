# Notes for coding agents

## Building and releasing

- This checkout uses `origin` for `zhiqiangwong/tvbox-silicon` (the fork) and `upstream` for
  `jo32/tvbox-silicon` (the original repository). Keep compatibility work on its own branch; push only when authorized.
- **Fetch and integrate upstream changes before you build or release.** Run `git fetch upstream` and
  `git fetch origin`, then ensure the current build branch includes `upstream/main` and the relevant fork changes.
  On a compatibility branch, merge `upstream/main`; rebase is an alternative only for unpublished local commits.
  Preserve local work and resolve conflicts before building. Autofix PRs and other sessions merge
  into upstream `main` often. A build made from an out-of-date tree ships without their fixes and has to be rebuilt and
  notarized again, which costs 25 minutes or more.
- Check again right before publishing (`git fetch upstream && git merge-base --is-ancestor upstream/main HEAD`),
  and fetch `origin` to check for concurrent fork changes. If the build baseline changed, integrate the changes and
  rebuild. Never deploy the website or push from a tree behind upstream `main`.
